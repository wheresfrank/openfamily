// Package handlers implements the HTTP and WebSocket API endpoints.
package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/whereabouts/whereabouts/backend/internal/auth"
	"github.com/whereabouts/whereabouts/backend/internal/push"
)

// Server holds shared dependencies for all handlers.
type Server struct {
	Pool *pgxpool.Pool
	TM   *auth.TokenManager
	Push push.Dispatcher

	// VerbosePush controls whether push notifications include the tracked
	// user's name. When false (default), pushes name the place but omit the
	// user ("A family member arrived at School"); when true, they also include
	// the user's name ("Mom arrived at School").
	VerbosePush bool

	// AllowedOrigin is the single cross-origin origin allowed for the WebSocket
	// stream (empty = same-origin only). It mirrors config.AllowedOrigin.
	AllowedOrigin string

	// hub fans out live location updates to connected WebSocket clients.
	hub *hub
}

// New builds a Server.
func New(pool *pgxpool.Pool, tm *auth.TokenManager, push push.Dispatcher) *Server {
	return &Server{Pool: pool, TM: tm, Push: push, hub: newHub()}
}

// familyIDForUser resolves a user's current family ID from the database. It
// returns "" when the user has no family. This is preferred over the JWT
// family claim, which can go stale when a user joins or creates a family.
func (s *Server) familyIDForUser(ctx context.Context, userID string) (string, error) {
	var fid *string
	err := s.Pool.QueryRow(ctx, `SELECT family_id FROM users WHERE id = $1`, userID).Scan(&fid)
	if err != nil {
		return "", err
	}
	if fid == nil {
		return "", nil
	}
	return *fid, nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
