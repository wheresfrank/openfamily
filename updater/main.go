// Command updater is a tiny sidecar service that applies server updates on
// behalf of the OpenFamily API.
//
// The API container cannot update itself: it has no git checkout of the repo
// and no access to the Docker daemon. This service runs in the same compose
// project with two mounts that give it that ability:
//
//   - the compose project directory (the git clone) at REPO_DIR, and
//   - /var/run/docker.sock, so it can run "docker compose up -d --build".
//
// It exposes a minimal API on the internal compose network only (no published
// ports):
//
//	GET  /healthz  liveness probe
//	GET  /status   current job state (JSON)
//	POST /apply    start an update; requires X-Updater-Token to match UPDATER_TOKEN
//	GET  /log      tail of the current/last update log (text/plain)
//
// An update fetches origin, checks out the remote default branch (or
// UPDATE_BRANCH), fast-forwards it with --ff-only, then runs
// "docker compose up -d --build" in REPO_DIR. The job state is persisted to a
// state file so a restart of this container can mark an interrupted update as
// failed instead of leaving it "running" forever.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	defaultAddr    = ":8081"
	stateFileName  = "update-state.json"
	logFileName    = "update.log"
	logTailBytes   = 64 * 1024 // /log returns at most the last 64KB
	commandTimeout = 30 * time.Minute
)

type jobStatus string

const (
	jobIdle        jobStatus = "idle"
	jobRunning     jobStatus = "running"
	jobSuccess     jobStatus = "success"
	jobFailed      jobStatus = "failed"
	jobInterrupted jobStatus = "interrupted"
)

// jobState is the persisted lifecycle record of the most recent update.
type jobState struct {
	Status      jobStatus `json:"status"`
	StartedAt   time.Time `json:"started_at"`
	FinishedAt  time.Time `json:"finished_at,omitempty"`
	PreviousRef string    `json:"previous_ref,omitempty"`
	NewRef      string    `json:"new_ref,omitempty"`
	Error       string    `json:"error,omitempty"`
}

type updater struct {
	mu        sync.Mutex
	repoDir   string
	dataDir   string
	token     string
	deployRef string // path of the deployed-ref file shared with the api
	branch    string // UPDATE_BRANCH; empty means origin/HEAD, then main
	busy      bool
}

func main() {
	addr := getenv("LISTEN_ADDR", defaultAddr)
	repoDir := getenv("REPO_DIR", "/repo")
	dataDir := getenv("DATA_DIR", "/data")
	deployRef := getenv("DEPLOY_REF_FILE", "/data/deploy/deployed-ref")

	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		slog.Error("cannot create data dir", "dir", dataDir, "err", err)
		os.Exit(1)
	}
	if err := os.MkdirAll(filepath.Dir(deployRef), 0o755); err != nil {
		slog.Error("cannot create deploy ref dir", "dir", filepath.Dir(deployRef), "err", err)
		os.Exit(1)
	}

	u := &updater{
		repoDir:   repoDir,
		dataDir:   dataDir,
		token:     os.Getenv("UPDATER_TOKEN"),
		deployRef: deployRef,
		branch:    strings.TrimSpace(os.Getenv("UPDATE_BRANCH")),
	}
	u.recoverInterrupted()
	u.writeDeployRef()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("GET /status", u.handleStatus)
	mux.HandleFunc("POST /apply", u.handleApply)
	mux.HandleFunc("GET /log", u.handleLog)

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	slog.Info("updater listening", "addr", addr, "repo", repoDir)
	if err := srv.ListenAndServe(); err != nil {
		slog.Error("updater exited", "err", err)
		os.Exit(1)
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// recoverInterrupted marks a stale "running" job as interrupted: this process
// just started, so any previous run was killed with its container and can
// never finish.
func (u *updater) recoverInterrupted() {
	st, ok := u.loadState()
	if !ok || st.Status != jobRunning {
		return
	}
	st.Status = jobInterrupted
	st.Error = "update was interrupted by a container restart before it could finish; verify container health, then run the update again"
	st.FinishedAt = time.Now().UTC()
	u.saveState(st)
	slog.Warn("recovered interrupted update job")
}

func (u *updater) statePath() string { return filepath.Join(u.dataDir, stateFileName) }
func (u *updater) logPath() string   { return filepath.Join(u.dataDir, logFileName) }

// writeDeployRef records the repo's current git ref to the file shared with
// the api container, so the admin panel can show which commit is deployed.
func (u *updater) writeDeployRef() {
	ref, err := gitRev(u.repoDir)
	if err != nil {
		slog.Warn("cannot determine deployed ref", "err", err)
		return
	}
	tmp := u.deployRef + ".tmp"
	if os.WriteFile(tmp, []byte(ref+"\n"), 0o644) == nil {
		_ = os.Rename(tmp, u.deployRef)
	}
}

func (u *updater) loadState() (jobState, bool) {
	b, err := os.ReadFile(u.statePath())
	if err != nil {
		return jobState{}, false
	}
	var st jobState
	if json.Unmarshal(b, &st) != nil {
		return jobState{}, false
	}
	return st, true
}

func (u *updater) saveState(st jobState) {
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return
	}
	tmp := u.statePath() + ".tmp"
	if os.WriteFile(tmp, b, 0o644) == nil {
		_ = os.Rename(tmp, u.statePath())
	}
}

// handleStatus reports the current checkout and last update job. It is safe to
// read on the internal Compose network without the apply token; this lets the
// API identify manually deployed builds even when automatic updates are off.
func (u *updater) handleStatus(w http.ResponseWriter, r *http.Request) {
	u.mu.Lock()
	busy := u.busy
	u.mu.Unlock()
	st, ok := u.loadState()
	if !ok {
		st = jobState{Status: jobIdle}
	}
	currentRef, _ := gitRev(u.repoDir)
	writeJSON(w, http.StatusOK, map[string]any{
		"available":   true,
		"busy":        busy,
		"can_apply":   u.token != "",
		"job":         st,
		"current_ref": currentRef,
	})
}

// handleApply starts an update unless one is already running.
func (u *updater) handleApply(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !u.authorized(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	u.mu.Lock()
	if u.busy {
		u.mu.Unlock()
		writeJSON(w, http.StatusConflict, map[string]string{"error": "an update is already in progress"})
		return
	}
	prev, _ := gitRev(u.repoDir)
	st := jobState{Status: jobRunning, StartedAt: time.Now().UTC(), PreviousRef: prev}
	u.saveState(st)
	u.busy = true
	u.mu.Unlock()

	go u.run(st)
	writeJSON(w, http.StatusAccepted, map[string]string{"status": "running"})
}

func (u *updater) authorized(r *http.Request) bool {
	return u.token != "" && r.Header.Get("X-Updater-Token") == u.token
}

// run performs the update: fetch origin, check out the deploy branch, fast-
// forward it, then docker compose up -d --build. Output is written to the log
// file so the admin UI can display it.
func (u *updater) run(st jobState) {
	defer func() {
		u.mu.Lock()
		u.busy = false
		u.mu.Unlock()
	}()

	logFile, err := os.Create(u.logPath())
	if err != nil {
		st.Status = jobFailed
		st.Error = "cannot open log file: " + err.Error()
		st.FinishedAt = time.Now().UTC()
		u.saveState(st)
		return
	}
	defer logFile.Close()

	fmt.Fprintf(logFile, "update started %s\n", st.StartedAt.Format(time.RFC3339))

	fail := func(format string, args ...any) {
		st.Status = jobFailed
		st.Error = fmt.Sprintf(format, args...)
		st.FinishedAt = time.Now().UTC()
		fmt.Fprintf(logFile, "\nUPDATE FAILED: %s\n", st.Error)
		u.saveState(st)
		slog.Error("update failed", "err", st.Error)
	}

	// Step 1 — fast-forward the deploy branch to origin's latest. Bare
	// `git pull` follows whatever the clone currently tracks, which breaks
	// after a feature-branch checkout once that remote branch is deleted.
	// --ff-only still refuses to clobber local commits; uncommitted local
	// modifications block checkout/merge and surface as a clear failure.
	if err := u.syncRepo(logFile); err != nil {
		fail("%v", err)
		return
	}

	newRef, err := gitRev(u.repoDir)
	if err != nil {
		newRef = ""
	}
	st.NewRef = newRef
	fmt.Fprintf(logFile, "now at %s\n", dashIfEmpty(newRef))
	u.writeDeployRef()

	// Step 2 — rebuild changed images and recreate changed services. Compose
	// only touches services whose build inputs or config changed, so an
	// api-only code change leaves postgres, ntfy, and caddy untouched.
	up := exec.Command("docker", "compose", "--project-directory", u.repoDir, "up", "-d", "--build")
	up.Env = append(os.Environ(), "GIT_COMMIT="+newRef)
	up.Stdout, up.Stderr = logFile, logFile
	if err := runWithTimeout(up); err != nil {
		fail("docker compose up failed: %v", err)
		return
	}

	st.Status = jobSuccess
	st.FinishedAt = time.Now().UTC()
	fmt.Fprintf(logFile, "update finished successfully %s\n", st.FinishedAt.Format(time.RFC3339))
	u.saveState(st)
	slog.Info("update finished", "ref", newRef)
}

// handleLog serves the tail of the update log for live progress display.
func (u *updater) handleLog(w http.ResponseWriter, r *http.Request) {
	if !u.authorized(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	f, err := os.Open(u.logPath())
	switch {
	case errors.Is(err, os.ErrNotExist):
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = w.Write([]byte("no update has run yet"))
		return
	case err != nil:
		http.Error(w, "cannot read log", http.StatusInternalServerError)
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		http.Error(w, "cannot read log", http.StatusInternalServerError)
		return
	}
	offset := st.Size() - logTailBytes
	if offset < 0 {
		offset = 0
	}
	if _, err := f.Seek(offset, io.SeekStart); err != nil {
		http.Error(w, "cannot read log", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = io.Copy(w, f)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// syncRepo fetches origin, checks out the deploy branch, and fast-forwards it.
func (u *updater) syncRepo(w io.Writer) error {
	fetch := exec.Command("git", "-C", u.repoDir, "fetch", "origin")
	fetch.Stdout, fetch.Stderr = w, w
	if err := runWithTimeout(fetch); err != nil {
		return fmt.Errorf("git fetch failed: %w", err)
	}

	branch := u.deployBranch()
	fmt.Fprintf(w, "updating branch %s\n", branch)
	if err := u.checkoutBranch(w, branch); err != nil {
		return err
	}

	merge := exec.Command("git", "-C", u.repoDir, "merge", "--ff-only", "origin/"+branch)
	merge.Stdout, merge.Stderr = w, w
	if err := runWithTimeout(merge); err != nil {
		return fmt.Errorf("git merge --ff-only origin/%s failed: %w", branch, err)
	}
	return nil
}

// deployBranch is the branch the admin Update button fast-forwards: UPDATE_BRANCH
// if set, otherwise the remote default (origin/HEAD), otherwise main.
func (u *updater) deployBranch() string {
	if u.branch != "" {
		return u.branch
	}
	out, err := exec.Command("git", "-C", u.repoDir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD").Output()
	if err == nil {
		ref := strings.TrimSpace(string(out))
		if branch, ok := strings.CutPrefix(ref, "origin/"); ok && branch != "" {
			return branch
		}
	}
	return "main"
}

func (u *updater) checkoutBranch(w io.Writer, branch string) error {
	current, err := exec.Command("git", "-C", u.repoDir, "rev-parse", "--abbrev-ref", "HEAD").Output()
	if err == nil && strings.TrimSpace(string(current)) == branch {
		return nil
	}

	cmd := exec.Command("git", "-C", u.repoDir, "checkout", branch)
	cmd.Stdout, cmd.Stderr = w, w
	if err := runWithTimeout(cmd); err == nil {
		return nil
	}

	// Local branch missing: create it tracking origin. If checkout failed for
	// another reason (dirty tree), this will fail too and git's message is in w.
	cmd = exec.Command("git", "-C", u.repoDir, "checkout", "--track", "origin/"+branch)
	cmd.Stdout, cmd.Stderr = w, w
	if err := runWithTimeout(cmd); err != nil {
		return fmt.Errorf("git checkout %s failed: %w", branch, err)
	}
	return nil
}

func gitRev(dir string) (string, error) {
	out, err := exec.Command("git", "-C", dir, "rev-parse", "--short", "HEAD").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func dashIfEmpty(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

// runWithTimeout runs cmd, killing it after commandTimeout.
func runWithTimeout(cmd *exec.Cmd) error {
	timer := time.AfterFunc(commandTimeout, func() {
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
	})
	defer timer.Stop()
	return cmd.Run()
}
