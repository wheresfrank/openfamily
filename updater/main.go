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
// UPDATE_BRANCH), fast-forwards it with --ff-only, rebuilds the images, and
// recreates every service EXCEPT this updater (which cannot survive the
// recreation of its own container); the updater replaces itself last through
// a detached one-shot bootstrap container. The job state is persisted to a
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
	defaultAddr          = ":8081"
	stateFileName        = "update-state.json"
	logFileName          = "update.log"
	logTailBytes         = 64 * 1024 // /log returns at most the last 64KB
	commandTimeout       = 30 * time.Minute
	updaterService       = "updater"
	selfInstallContainer = "openfamily-updater-selfinstall"
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

	// Step 2 — rebuild the images. Building touches no containers, so this
	// can never take the stack down.
	build := exec.Command("docker", "compose", "--project-directory", u.repoDir, "build")
	build.Env = append(os.Environ(), "GIT_COMMIT="+st.NewRef)
	build.Stdout, build.Stderr = logFile, logFile
	if err := runWithTimeout(build); err != nil {
		fail("docker compose build failed: %v", err)
		return
	}

	// Step 3 — recreate every service EXCEPT this updater. Recreating the
	// updater from inside the updater kills this very process mid-command
	// (it is the client driving compose through the mounted docker.sock),
	// which left freshly created containers never started and the whole
	// stack down (production incident 2026-08-26: any api image change
	// cascaded through compose's depends_on into an updater recreation).
	if err := u.upOtherServices(logFile, newRef); err != nil {
		fail("docker compose up failed: %v", err)
		return
	}

	// Step 4 — replace this updater last, if its image changed. The stack is
	// already fully up at this point, so a failed self-swap degrades to "the
	// updater still runs its previous image" rather than an outage.
	swapped, err := u.selfInstallIfChanged(logFile, st)
	if err != nil {
		fmt.Fprintf(logFile, "\nWARNING: updater self-install failed (%v); the stack is up, but the updater still runs its previous image. Run the update again to retry.\n", err)
	}
	if swapped {
		// The bootstrap container is replacing this process right now; the
		// success state was written before the swap was scheduled.
		return
	}

	st.Status = jobSuccess
	st.FinishedAt = time.Now().UTC()
	fmt.Fprintf(logFile, "update finished successfully %s\n", st.FinishedAt.Format(time.RFC3339))
	u.saveState(st)
	slog.Info("update finished", "ref", newRef)
}

// upOtherServices recreates every compose service except the updater itself,
// so this process is never the victim of its own deployment. The explicit
// service list also sidesteps compose's depends_on cascade, which otherwise
// recreates the updater whenever a dependency (api) is recreated.
func (u *updater) upOtherServices(w io.Writer, gitRef string) error {
	services, err := u.otherServices()
	if err != nil {
		return fmt.Errorf("docker compose config --services failed: %w", err)
	}
	if len(services) == 0 {
		return fmt.Errorf("compose defines no services other than %q", updaterService)
	}
	args := append([]string{
		"compose", "--project-directory", u.repoDir, "up", "-d", "--build", "--no-deps",
	}, services...)
	up := exec.Command("docker", args...)
	up.Env = append(os.Environ(), "GIT_COMMIT="+gitRef)
	up.Stdout, up.Stderr = w, w
	if err := runWithTimeout(up); err != nil {
		return fmt.Errorf("docker compose up %s failed: %w", strings.Join(services, " "), err)
	}
	return nil
}

// otherServices lists the compose services of this project, excluding the
// updater itself. The output of `docker compose config --services` is one
// service name per line.
func (u *updater) otherServices() ([]string, error) {
	out, err := exec.Command("docker", "compose", "--project-directory", u.repoDir, "config", "--services").Output()
	if err != nil {
		return nil, err
	}
	return filterServices(string(out), updaterService), nil
}

// filterServices splits `docker compose config --services` output and drops
// the updater's own service.
func filterServices(servicesOutput, exclude string) []string {
	var services []string
	for _, line := range strings.Split(servicesOutput, "\n") {
		svc := strings.TrimSpace(line)
		if svc != "" && svc != exclude {
			services = append(services, svc)
		}
	}
	return services
}

// needsSelfInstall reports whether the freshly built updater image differs
// from the image this container is running on.
func needsSelfInstall(runningImage, latestImage string) bool {
	return runningImage != latestImage
}

// selfInstallIfChanged replaces this updater container when its freshly built
// image differs from the one it is currently running.
//
// The replacement must not run from this process: recreating the updater
// container kills it. Instead, a detached one-shot "bootstrap" container
// (the freshly built updater image itself, which bundles the docker CLI and
// compose plugin) is started with access to the docker socket, and it runs
// the final `docker compose up updater` after this process is gone. The job
// is recorded as successful BEFORE the swap is scheduled, so the replacement
// updater boots into a finished state instead of recovering a phantom
// "running" job as interrupted.
func (u *updater) selfInstallIfChanged(w io.Writer, st jobState) (bool, error) {
	selfID, err := os.Hostname() // docker sets the container hostname to its short id
	if err != nil {
		return false, fmt.Errorf("cannot determine own container: %w", err)
	}
	runningImage, imageTag, err := u.selfImage(selfID)
	if err != nil {
		return false, err
	}
	latestImage, err := u.imageID(imageTag)
	if err != nil {
		return false, fmt.Errorf("cannot resolve freshly built image %s: %w", imageTag, err)
	}
	if !needsSelfInstall(runningImage, latestImage) {
		fmt.Fprintln(w, "updater image unchanged; skipping self-install")
		return false, nil
	}
	hostRepo, err := u.hostRepoDir(selfID)
	if err != nil {
		return false, err
	}

	// The update is fully applied at this point; only this container's own
	// replacement remains. Record success first — this process dies during
	// the swap.
	st.Status = jobSuccess
	st.FinishedAt = time.Now().UTC()
	fmt.Fprintf(w, "update finished successfully %s\n", st.FinishedAt.Format(time.RFC3339))
	fmt.Fprintln(w, "updater image changed; scheduling self-install via detached bootstrap container")
	u.saveState(st)
	slog.Info("update finished; scheduling updater self-install", "ref", st.NewRef)

	// Drop any stale bootstrap from a previous failed attempt.
	_ = exec.Command("docker", "rm", "-f", selfInstallContainer).Run()

	run := exec.Command("docker", "run", "-d", "--rm",
		"--name", selfInstallContainer,
		"--entrypoint", "/bin/sh",
		"-v", "/var/run/docker.sock:/var/run/docker.sock",
		"-v", hostRepo+":/repo",
		imageTag,
		"-c", "docker compose --project-directory /repo up -d "+updaterService,
	)
	run.Stdout, run.Stderr = w, w
	if err := runWithTimeout(run); err != nil {
		return false, fmt.Errorf("starting bootstrap container failed: %w", err)
	}
	fmt.Fprintln(w, "self-install scheduled via bootstrap container")
	return true, nil
}

// selfImage returns the image ID the given container runs and the image tag
// it references.
func (u *updater) selfImage(containerID string) (imageID, imageTag string, err error) {
	out, err := exec.Command("docker", "inspect", containerID, "--format",
		`{{.Image}} {{.Config.Image}}`).Output()
	if err != nil {
		return "", "", fmt.Errorf("docker inspect %s failed: %w", containerID, err)
	}
	parts := strings.Fields(string(out))
	if len(parts) != 2 {
		return "", "", fmt.Errorf("unexpected docker inspect output: %q", strings.TrimSpace(string(out)))
	}
	return parts[0], parts[1], nil
}

// imageID resolves an image tag to its image ID.
func (u *updater) imageID(tag string) (string, error) {
	out, err := exec.Command("docker", "images", tag, "--format", "{{.ID}}").Output()
	if err != nil {
		return "", err
	}
	id := strings.TrimSpace(string(out))
	if id == "" {
		return "", fmt.Errorf("image %s not found", tag)
	}
	return id, nil
}

// hostRepoDir resolves the HOST path backing the repo mount of the given
// container, so a sibling container can bind-mount the same clone.
func (u *updater) hostRepoDir(containerID string) (string, error) {
	out, err := exec.Command("docker", "inspect", containerID, "--format", "{{json .Mounts}}").Output()
	if err != nil {
		return "", fmt.Errorf("docker inspect mounts failed: %w", err)
	}
	var mounts []struct {
		Source      string `json:"Source"`
		Destination string `json:"Destination"`
	}
	if err := json.Unmarshal(out, &mounts); err != nil {
		return "", fmt.Errorf("cannot parse container mounts: %w", err)
	}
	for _, m := range mounts {
		if m.Destination == u.repoDir && m.Source != "" {
			return m.Source, nil
		}
	}
	return "", fmt.Errorf("cannot find the host path for the %s mount", u.repoDir)
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
