// Package apkrelease fetches the latest Android APK from a GitHub Release and
// caches it on disk. CI publishes the APK as a release asset; the admin
// download endpoint syncs that asset into APK_DIR so the server never needs
// the Flutter toolchain or a git pull of a binary.
package apkrelease

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	defaultAPI   = "https://api.github.com"
	cachedName   = "whereabouts-release.apk"
	metaName     = ".apk-release.json"
	userAgent    = "whereabouts-apk-sync"
	metaTimeout  = 15 * time.Second
	fetchTimeout = 5 * time.Minute
)

// ErrNotFound means GitHub has no latest release, or the latest release has
// no APK asset.
var ErrNotFound = errors.New("no APK on the latest GitHub Release")

// Options configure a sync against GitHub Releases.
type Options struct {
	// Repo is "owner/name".
	Repo string
	// Token is a GitHub PAT (Contents: Read). Required for private repos.
	Token string
	// DestDir is APK_DIR, where the cached APK is stored.
	DestDir string
	// API is the GitHub API origin. Empty uses https://api.github.com.
	API string
	// Client is optional; empty uses a client that strips Authorization on
	// cross-host redirects (GitHub asset downloads 302 to a CDN).
	Client *http.Client
}

type release struct {
	TagName string  `json:"tag_name"`
	Assets  []asset `json:"assets"`
}

type asset struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	URL  string `json:"url"`
	Size int64  `json:"size"`
}

type cacheMeta struct {
	AssetID int64  `json:"asset_id"`
	TagName string `json:"tag_name"`
	Name    string `json:"name"`
}

// Sync ensures DestDir contains the APK from the repo's latest GitHub Release.
// If the cached file already matches that asset, it is reused. The returned
// path is the local APK.
func Sync(ctx context.Context, opts Options) (string, error) {
	if opts.DestDir == "" {
		return "", errors.New("APK_DIR is not configured")
	}
	owner, name, err := parseRepo(opts.Repo)
	if err != nil {
		return "", err
	}
	client := opts.Client
	if client == nil {
		client = defaultClient()
	}
	api := strings.TrimRight(opts.API, "/")
	if api == "" {
		api = defaultAPI
	}

	metaCtx, cancel := context.WithTimeout(ctx, metaTimeout)
	defer cancel()
	rel, err := fetchLatest(metaCtx, client, api, owner, name, opts.Token)
	if err != nil {
		return "", err
	}
	asset, err := pickAPKAsset(rel.Assets)
	if err != nil {
		return "", err
	}

	if err := os.MkdirAll(opts.DestDir, 0o755); err != nil {
		return "", fmt.Errorf("create APK_DIR: %w", err)
	}
	dest := filepath.Join(opts.DestDir, cachedName)
	if cacheFresh(opts.DestDir, dest, asset.ID) {
		return dest, nil
	}

	dlCtx, cancelDL := context.WithTimeout(ctx, fetchTimeout)
	defer cancelDL()
	if err := downloadAsset(dlCtx, client, asset.URL, opts.Token, dest); err != nil {
		return "", err
	}
	meta := cacheMeta{AssetID: asset.ID, TagName: rel.TagName, Name: asset.Name}
	if metaErr := writeMeta(opts.DestDir, meta); metaErr != nil {
		// The APK is usable even if the sidecar fails; the next sync will
		// re-download.
		return dest, nil
	}
	return dest, nil
}

func parseRepo(repo string) (owner, name string, err error) {
	repo = strings.TrimSpace(repo)
	parts := strings.Split(repo, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", errors.New("APK_GITHUB_REPO must be owner/name")
	}
	return parts[0], parts[1], nil
}

func pickAPKAsset(assets []asset) (asset, error) {
	for _, a := range assets {
		if strings.EqualFold(filepath.Ext(a.Name), ".apk") {
			return a, nil
		}
	}
	return asset{}, ErrNotFound
}

func cacheFresh(dir, dest string, assetID int64) bool {
	if _, err := os.Stat(dest); err != nil {
		return false
	}
	meta, err := readMeta(dir)
	if err != nil {
		return false
	}
	return meta.AssetID == assetID
}

func fetchLatest(ctx context.Context, client *http.Client, api, owner, name, token string) (*release, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/releases/latest", api, owner, name)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	setGitHubHeaders(req, token, "application/vnd.github+json")

	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("github releases/latest: %w", err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("%w: GitHub returned 404 (no release yet, or APK_GITHUB_TOKEN is missing for a private repo)", ErrNotFound)
	}
	if res.StatusCode == http.StatusUnauthorized || res.StatusCode == http.StatusForbidden {
		return nil, fmt.Errorf("GitHub auth failed (%d); set APK_GITHUB_TOKEN to a PAT with Contents: Read", res.StatusCode)
	}
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("github releases/latest: HTTP %d", res.StatusCode)
	}
	var rel release
	if err := json.Unmarshal(body, &rel); err != nil {
		return nil, fmt.Errorf("decode github release: %w", err)
	}
	return &rel, nil
}

func downloadAsset(ctx context.Context, client *http.Client, assetURL, token, dest string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, assetURL, nil)
	if err != nil {
		return err
	}
	setGitHubHeaders(req, token, "application/octet-stream")

	res, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("download github asset: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("download github asset: HTTP %d", res.StatusCode)
	}
	return writeAtomic(dest, res.Body)
}

func setGitHubHeaders(req *http.Request, token, accept string) {
	req.Header.Set("Accept", accept)
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
}

func defaultClient() *http.Client {
	return &http.Client{
		Timeout: fetchTimeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 10 {
				return errors.New("too many redirects")
			}
			// Asset downloads 302 onto a CDN. Do not forward the PAT.
			if len(via) > 0 && req.URL.Host != via[0].URL.Host {
				req.Header.Del("Authorization")
			}
			return nil
		},
	}
}

func metaPath(dir string) string {
	return filepath.Join(dir, metaName)
}

func readMeta(dir string) (cacheMeta, error) {
	var meta cacheMeta
	data, err := os.ReadFile(metaPath(dir))
	if err != nil {
		return meta, err
	}
	if err := json.Unmarshal(data, &meta); err != nil {
		return meta, err
	}
	return meta, nil
}

func writeMeta(dir string, meta cacheMeta) error {
	data, err := json.Marshal(meta)
	if err != nil {
		return err
	}
	tmp := metaPath(dir) + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, metaPath(dir))
}

func writeAtomic(dest string, r io.Reader) error {
	dir := filepath.Dir(dest)
	tmp, err := os.CreateTemp(dir, ".apk-partial-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := io.Copy(tmp, r); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, dest)
}
