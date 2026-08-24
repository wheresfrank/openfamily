package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/wheresfrank/openfamily/backend/internal/middleware"
)

// proxy timeouts. Status/log calls are quick; apply returns 202 as soon as
// the updater has accepted the job.
const (
	updaterQuickTimeout = 10 * time.Second
	updaterApplyTimeout = 15 * time.Second
)

// updaterJob mirrors the updater sidecar's persisted job state.
type updaterJob struct {
	Status      string    `json:"status"`
	StartedAt   time.Time `json:"started_at"`
	FinishedAt  time.Time `json:"finished_at,omitempty"`
	PreviousRef string    `json:"previous_ref,omitempty"`
	NewRef      string    `json:"new_ref,omitempty"`
	Error       string    `json:"error,omitempty"`
}

// updateStatusOut is the JSON shape of GET /api/admin/update/status.
type updateStatusOut struct {
	// DeployedRef is the git commit currently running (short SHA). Empty means
	// unknown (e.g. a source run without the updater sidecar).
	DeployedRef string `json:"deployed_ref,omitempty"`
	// LatestRef is the newest commit on the upstream default branch. Empty with
	// CheckError set means the check could not run.
	LatestRef string `json:"latest_ref,omitempty"`
	// UpdateAvailable is true when both refs are known and differ.
	UpdateAvailable bool `json:"update_available"`
	// CanUpdate is true when the updater sidecar is configured and answered.
	CanUpdate  bool `json:"can_update"`
	Busy       bool `json:"busy"`
	Job        *updaterJob
	CheckError string `json:"check_error,omitempty"`
}

var errUpdaterUnavailable = errors.New("updater service unavailable")

// deployedRef returns the running server's git ref. The updater sidecar stamps
// the ref it deployed into DeployRefFile; the build-time ldflags value is the
// fallback for deployments that never used the button.
func (s *Server) deployedRef() string {
	if s.DeployRefFile != "" {
		if b, err := os.ReadFile(s.DeployRefFile); err == nil {
			if ref := strings.TrimSpace(string(b)); ref != "" {
				return ref
			}
		}
	}
	return s.BuildVersion
}

// AdminUpdateStatus reports what is running, what is available, and whether
// the in-panel update button can act.
func (s *Server) AdminUpdateStatus(w http.ResponseWriter, r *http.Request) {
	if middleware.ClaimsFromContext(r.Context()) == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	out := updateStatusOut{DeployedRef: s.deployedRef()}

	if s.UpdateCheck.HasSource() {
		ctx, cancel := context.WithTimeout(r.Context(), updaterQuickTimeout)
		ref, err := s.UpdateCheck.LatestCommit(ctx)
		cancel()
		if err != nil {
			out.CheckError = err.Error()
			slog.Warn("admin update: latest-commit check failed", "err", err)
		} else {
			out.LatestRef = ref
			out.UpdateAvailable = out.DeployedRef != "" && out.DeployedRef != "dev" && ref != out.DeployedRef
		}
	}

	if s.UpdaterURL != "" {
		job, busy, err := s.updaterStatus(r.Context())
		if err != nil {
			slog.Warn("admin update: updater unreachable", "err", err)
		} else {
			out.CanUpdate = true
			out.Busy = busy
			out.Job = job
		}
	}

	writeJSON(w, http.StatusOK, out)
}

// AdminUpdateApply asks the updater sidecar to pull and rebuild. The HTTP
// response only says the job started; poll GET /api/admin/update/status (and
// /log) to follow progress.
func (s *Server) AdminUpdateApply(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	if s.UpdaterURL == "" {
		writeError(w, http.StatusNotImplemented, "server self-update is not configured on this deployment (set UPDATER_TOKEN)")
		return
	}

	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost,
		strings.TrimRight(s.UpdaterURL, "/")+"/apply", nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	req.Header.Set("X-Updater-Token", s.UpdaterToken)

	client := &http.Client{Timeout: updaterApplyTimeout}
	resp, err := client.Do(req)
	if err != nil {
		slog.Warn("admin update: apply call failed", "err", err)
		writeError(w, http.StatusBadGateway, "cannot reach the updater service")
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	switch resp.StatusCode {
	case http.StatusAccepted:
		s.logAudit(r.Context(), claims.UserID, "", "admin.update_apply",
			"triggered server update from admin panel", clientIP(r))
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write(body)
	case http.StatusConflict:
		writeError(w, http.StatusConflict, "an update is already in progress")
	default:
		slog.Warn("admin update: unexpected updater status", "status", resp.StatusCode)
		writeError(w, http.StatusBadGateway, "updater service rejected the request")
	}
}

// AdminUpdateLog proxies the updater's log tail so the panel can show live
// progress while an update runs.
func (s *Server) AdminUpdateLog(w http.ResponseWriter, r *http.Request) {
	if middleware.ClaimsFromContext(r.Context()) == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	if s.UpdaterURL == "" {
		http.Error(w, "server self-update is not configured", http.StatusNotImplemented)
		return
	}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet,
		strings.TrimRight(s.UpdaterURL, "/")+"/log", nil)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	req.Header.Set("X-Updater-Token", s.UpdaterToken)

	client := &http.Client{Timeout: updaterQuickTimeout}
	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, "cannot reach the updater service", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, io.LimitReader(resp.Body, 1<<20))
}

// updaterStatus fetches the updater's status endpoint. A missing token or an
// unreachable service surfaces as an error so the UI can show the button as
// unavailable rather than lying about state.
func (s *Server) updaterStatus(ctx context.Context) (*updaterJob, bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		strings.TrimRight(s.UpdaterURL, "/")+"/status", nil)
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("X-Updater-Token", s.UpdaterToken)

	client := &http.Client{Timeout: updaterQuickTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, false, errUpdaterUnavailable
	}
	var payload struct {
		Busy bool        `json:"busy"`
		Job  *updaterJob `json:"job"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&payload); err != nil {
		return nil, false, err
	}
	return payload.Job, payload.Busy, nil
}
