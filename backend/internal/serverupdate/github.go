// Package serverupdate answers "is a newer server commit available?" by
// comparing the deployed git ref with the repository's default branch on
// GitHub. It only reads; applying an update is the updater sidecar's job.
package serverupdate

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	defaultAPI  = "https://api.github.com"
	userAgent   = "whereabouts-server-update"
	checkExpiry = 10 * time.Minute
)

// Checker looks up the latest commit on the repo's default branch and caches
// the result briefly so repeated admin panel loads do not hammer the GitHub
// API (which is rate-limited per IP/token).
type Checker struct {
	Repo     string // "owner/name"; empty disables checks
	Token    string // optional PAT; needed for private repos
	API      string // override for tests; empty uses api.github.com
	Client   *http.Client
	Branches map[string]string // test hook: repo -> default branch

	mu      sync.Mutex
	lastSHA string
	lastAt  time.Time
}

type repoInfo struct {
	DefaultBranch string `json:"default_branch"`
}

type commitInfo struct {
	SHA string `json:"sha"`
}

// LatestCommit returns the short SHA of the newest commit on the repository's
// default branch.
func (c *Checker) LatestCommit(ctx context.Context) (string, error) {
	if c == nil || c.Repo == "" {
		return "", errors.New("server update source repository is not configured")
	}
	c.mu.Lock()
	cachedSHA, cachedAt := c.lastSHA, c.lastAt
	c.mu.Unlock()
	if cachedSHA != "" && time.Since(cachedAt) < checkExpiry {
		return cachedSHA, nil
	}

	api := c.API
	if api == "" {
		api = defaultAPI
	}
	client := c.Client
	if client == nil {
		client = http.DefaultClient
	}

	branch := ""
	if c.Branches != nil {
		branch = c.Branches[c.Repo]
	}
	if branch == "" {
		var info repoInfo
		if err := c.get(ctx, client, api, "/repos/"+c.Repo, &info); err != nil {
			return "", err
		}
		branch = info.DefaultBranch
		if branch == "" {
			return "", fmt.Errorf("repository %s has no default branch", c.Repo)
		}
	}

	var commits []commitInfo
	if err := c.get(ctx, client, api, "/repos/"+c.Repo+"/commits?per_page=1&sha="+url.QueryEscape(branch), &commits); err != nil {
		return "", err
	}
	if len(commits) == 0 {
		return "", fmt.Errorf("no commits found on %s#%s", c.Repo, branch)
	}
	short := commits[0].SHA
	if len(short) > 7 {
		short = short[:7]
	}
	c.mu.Lock()
	c.lastSHA, c.lastAt = short, time.Now()
	c.mu.Unlock()
	return short, nil
}

func (c *Checker) get(ctx context.Context, client *http.Client, api, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(api, "/")+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", userAgent)
	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("github api %s returned %d", path, resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// HasSource reports whether update availability can be checked at all.
func (c *Checker) HasSource() bool { return c != nil && c.Repo != "" }
