package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/whereabouts/whereabouts/backend/internal/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/push"
)

// RegisterDevice registers a new device for the authenticated user.
func (s *Server) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	var req struct {
		Platform            string `json:"platform"`
		Name                string `json:"name"`
		PushToken           string `json:"push_token,omitempty"`
		UnifiedPushEndpoint string `json:"unifiedpush_endpoint,omitempty"`
		AppVersion          string `json:"app_version,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Platform != "ios" && req.Platform != "android" && req.Platform != "web" {
		writeError(w, http.StatusBadRequest, "platform must be ios, android, or web")
		return
	}
	// Reject platform/credential mismatches so a misconfigured device fails
	// loudly instead of silently never receiving pushes.
	if req.Platform == "ios" && req.UnifiedPushEndpoint != "" {
		writeError(w, http.StatusBadRequest, "ios devices must use push_token, not unifiedpush_endpoint")
		return
	}
	if req.Platform == "android" && req.PushToken != "" {
		writeError(w, http.StatusBadRequest, "android devices must use unifiedpush_endpoint, not push_token")
		return
	}
	// Reject unsafe UnifiedPush endpoints (SSRF protection).
	if req.UnifiedPushEndpoint != "" {
		if err := push.ValidateUnifiedPushEndpoint(req.UnifiedPushEndpoint); err != nil {
			writeError(w, http.StatusBadRequest, "invalid unifiedpush_endpoint")
			return
		}
	}

	var device struct {
		ID         string `json:"id"`
		UserID     string `json:"user_id"`
		Platform   string `json:"platform"`
		Name       string `json:"name"`
		AppVersion string `json:"app_version"`
	}
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO devices (user_id, platform, name, push_token, unifiedpush_endpoint, app_version)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, user_id, platform, name, app_version`,
		claims.UserID, req.Platform, req.Name, req.PushToken, req.UnifiedPushEndpoint, req.AppVersion,
	).Scan(&device.ID, &device.UserID, &device.Platform, &device.Name, &device.AppVersion)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to register device")
		return
	}
	writeJSON(w, http.StatusCreated, device)
}

// ListDevices returns the authenticated user's devices.
func (s *Server) ListDevices(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	rows, err := s.Pool.Query(r.Context(), `
		SELECT id, user_id, platform, name, last_seen, app_version, created_at
		FROM devices WHERE user_id = $1 ORDER BY created_at`, claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list devices")
		return
	}
	defer rows.Close()

	type deviceOut struct {
		ID         string     `json:"id"`
		UserID     string     `json:"user_id"`
		Platform   string     `json:"platform"`
		Name       string     `json:"name"`
		LastSeen   *time.Time `json:"last_seen,omitempty"`
		AppVersion string     `json:"app_version"`
		CreatedAt  time.Time  `json:"created_at"`
	}
	devices := []deviceOut{}
	for rows.Next() {
		var d deviceOut
		if err := rows.Scan(&d.ID, &d.UserID, &d.Platform, &d.Name, &d.LastSeen, &d.AppVersion, &d.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to scan device")
			return
		}
		devices = append(devices, d)
	}
	writeJSON(w, http.StatusOK, devices)
}
