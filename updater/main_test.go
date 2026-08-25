package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestStatusIsReadableWithoutApplyToken(t *testing.T) {
	u := &updater{repoDir: t.TempDir(), dataDir: t.TempDir()}
	req := httptest.NewRequest(http.MethodGet, "/status", nil)
	rec := httptest.NewRecorder()

	u.handleStatus(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status code = %d, want %d", rec.Code, http.StatusOK)
	}
	var payload struct {
		CanApply bool `json:"can_apply"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if payload.CanApply {
		t.Fatal("status must not advertise apply capability without a token")
	}
}

func TestDeployBranchUsesConfiguredBranch(t *testing.T) {
	u := &updater{repoDir: t.TempDir(), branch: "release"}
	if got := u.deployBranch(); got != "release" {
		t.Fatalf("deployBranch() = %q, want release", got)
	}
}

func TestDeployBranchDefaultsToMainWithoutOriginHead(t *testing.T) {
	u := &updater{repoDir: t.TempDir()}
	if got := u.deployBranch(); got != "main" {
		t.Fatalf("deployBranch() = %q, want main", got)
	}
}

// Bare `git pull` follows the clone's current upstream. After a feature-branch
// checkout, that upstream can vanish when the PR is merged and the remote
// branch is deleted — which is exactly what the in-admin Update button hit.
func TestSyncRepoFastForwardsDefaultBranchFromDeletedFeatureCheckout(t *testing.T) {
	origin := filepath.Join(t.TempDir(), "origin.git")
	work := filepath.Join(t.TempDir(), "work")
	clone := filepath.Join(t.TempDir(), "clone")

	git(t, "", "init", "--bare", "-b", "main", origin)
	git(t, "", "clone", origin, work)
	writeFile(t, filepath.Join(work, "README"), "one\n")
	git(t, work, "add", "README")
	git(t, work, "commit", "-m", "initial")
	git(t, work, "push", "-u", "origin", "main")

	git(t, work, "checkout", "-b", "feat/reliable-background-updates")
	writeFile(t, filepath.Join(work, "README"), "one\nfeature\n")
	git(t, work, "commit", "-am", "feature")
	git(t, work, "push", "-u", "origin", "HEAD")

	git(t, "", "clone", origin, clone)
	git(t, clone, "checkout", "-t", "origin/feat/reliable-background-updates")

	git(t, origin, "branch", "-D", "feat/reliable-background-updates")

	git(t, work, "checkout", "main")
	writeFile(t, filepath.Join(work, "README"), "one\nlater\n")
	git(t, work, "commit", "-am", "later on main")
	git(t, work, "push", "origin", "main")

	u := &updater{repoDir: clone}
	var log bytes.Buffer
	if err := u.syncRepo(&log); err != nil {
		t.Fatalf("syncRepo: %v\n%s", err, log.String())
	}

	if got := strings.TrimSpace(git(t, clone, "rev-parse", "--abbrev-ref", "HEAD")); got != "main" {
		t.Fatalf("clone branch = %q, want main\n%s", got, log.String())
	}
	want := strings.TrimSpace(git(t, origin, "rev-parse", "main"))
	got := strings.TrimSpace(git(t, clone, "rev-parse", "HEAD"))
	if got != want {
		t.Fatalf("clone HEAD = %s, want origin/main %s\n%s", got, want, log.String())
	}
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{
		"-c", "user.name=Test",
		"-c", "user.email=test@example.com",
		"-c", "commit.gpgsign=false",
		"-c", "init.defaultBranch=main",
	}, args...)...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.Env = append(os.Environ(),
		"GIT_AUTHOR_NAME=Test",
		"GIT_AUTHOR_EMAIL=test@example.com",
		"GIT_COMMITTER_NAME=Test",
		"GIT_COMMITTER_EMAIL=test@example.com",
		"GIT_CONFIG_NOSYSTEM=1",
		"GIT_CONFIG_GLOBAL=/dev/null",
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return string(out)
}

func writeFile(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
}
