package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/wheresfrank/openfamily/backend/internal/middleware"
	"github.com/wheresfrank/openfamily/backend/internal/push"
)

const (
	locationRequestCommandTTL = 30 * time.Second
	locationRequestCooldown   = 2 * time.Minute
)

type locationRequestState struct {
	id        string
	createdAt time.Time
}

type locationRequestDecision struct {
	state      locationRequestState
	status     string
	retryAfter time.Duration
}

// locationRequestGate is deliberately in-memory: the cooldown is a battery
// protection, not authorization state. A server restart may permit one extra
// request, while normal operation coalesces concurrent viewers and rapid taps.
type locationRequestGate struct {
	mu       sync.Mutex
	byUser   map[string]locationRequestState
	cooldown time.Duration
	ttl      time.Duration
}

func newLocationRequestGate() *locationRequestGate {
	return &locationRequestGate{
		byUser:   make(map[string]locationRequestState),
		cooldown: locationRequestCooldown,
		ttl:      locationRequestCommandTTL,
	}
}

func (g *locationRequestGate) reserve(targetID, requestID string, now time.Time) locationRequestDecision {
	g.mu.Lock()
	defer g.mu.Unlock()

	if previous, ok := g.byUser[targetID]; ok {
		age := now.Sub(previous.createdAt)
		if age >= 0 && age < g.cooldown {
			status := "cooldown"
			if age < g.ttl {
				status = "coalesced"
			}
			return locationRequestDecision{
				state:      previous,
				status:     status,
				retryAfter: g.cooldown - age,
			}
		}
	}

	state := locationRequestState{id: requestID, createdAt: now}
	g.byUser[targetID] = state
	return locationRequestDecision{state: state, status: "queued"}
}

func (g *locationRequestGate) release(targetID, requestID string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if current, ok := g.byUser[targetID]; ok && current.id == requestID {
		delete(g.byUser, targetID)
	}
}

type locationRequestCommand struct {
	Type        string    `json:"type"`
	RequestID   string    `json:"request_id"`
	RequestedAt time.Time `json:"requested_at"`
	ExpiresAt   time.Time `json:"expires_at"`
}

// RequestMemberLocation asks a family member's Android app for one fresh fix.
// The command contains no location or requester information and expires after
// 30 seconds. The app still enforces its own sharing and permission settings.
func (s *Server) RequestMemberLocation(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	targetID := strings.TrimSpace(chi.URLParam(r, "id"))
	if targetID == "" {
		writeError(w, http.StatusBadRequest, "member id required")
		return
	}

	var isFamilyMember bool
	err := s.Pool.QueryRow(r.Context(), `
		SELECT EXISTS (
			SELECT 1
			FROM users requester
			JOIN users target ON target.id = $2
			WHERE requester.id = $1
			  AND requester.family_id IS NOT NULL
			  AND target.family_id = requester.family_id
		)`, claims.UserID, targetID).Scan(&isFamilyMember)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to verify family member")
		return
	}
	if !isFamilyMember {
		writeError(w, http.StatusNotFound, "family member not found")
		return
	}

	rows, err := s.Pool.Query(r.Context(), `
		SELECT unifiedpush_endpoint
		FROM devices
		WHERE user_id = $1
		  AND platform = 'android'
		  AND unifiedpush_endpoint IS NOT NULL
		  AND unifiedpush_endpoint <> ''
		ORDER BY last_seen DESC NULLS LAST, created_at DESC
		LIMIT 1`, targetID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load member devices")
		return
	}
	defer rows.Close()
	var endpoints []string
	for rows.Next() {
		var endpoint string
		if err := rows.Scan(&endpoint); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to scan member device")
			return
		}
		endpoints = append(endpoints, endpoint)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load member devices")
		return
	}
	if len(endpoints) == 0 || s.Push == nil {
		writeError(w, http.StatusConflict, "member has no reachable Android device")
		return
	}

	now := time.Now().UTC()
	requestID, err := newLocationRequestID()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create location request")
		return
	}
	gate := s.locationRequests
	if gate == nil {
		gate = newLocationRequestGate()
		s.locationRequests = gate
	}
	decision := gate.reserve(targetID, requestID, now)
	if decision.status != "queued" {
		writeJSON(w, http.StatusAccepted, map[string]any{
			"status":              decision.status,
			"request_id":          decision.state.id,
			"retry_after_seconds": max(1, int(decision.retryAfter.Round(time.Second)/time.Second)),
		})
		return
	}

	body, command, err := encodeLocationRequestCommand(requestID, now)
	if err != nil {
		gate.release(targetID, requestID)
		writeError(w, http.StatusInternalServerError, "failed to encode location request")
		return
	}

	delivered := 0
	for _, endpoint := range endpoints {
		dispatchCtx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		err := s.Push.Dispatch(dispatchCtx, push.Notification{
			Title:               "OpenFamily location refresh",
			Body:                string(body),
			Platform:            "android",
			UnifiedPushEndpoint: endpoint,
		})
		cancel()
		if err == nil {
			delivered++
		}
	}
	if delivered == 0 {
		gate.release(targetID, requestID)
		writeError(w, http.StatusBadGateway, "could not reach member device")
		return
	}

	writeJSON(w, http.StatusAccepted, map[string]any{
		"status":     "queued",
		"request_id": requestID,
		"expires_at": command.ExpiresAt,
	})
}

func newLocationRequestID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(b[:]), nil
}

func encodeLocationRequestCommand(requestID string, now time.Time) ([]byte, locationRequestCommand, error) {
	command := locationRequestCommand{
		Type:        "location_request",
		RequestID:   requestID,
		RequestedAt: now,
		ExpiresAt:   now.Add(locationRequestCommandTTL),
	}
	body, err := json.Marshal(command)
	return body, command, err
}
