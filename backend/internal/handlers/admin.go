package handlers

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/whereabouts/whereabouts/backend/internal/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/models"
)

// adminFamily is the platform-admin view of a family: identity fields plus a
// member count for the admin list.
type adminFamily struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	CreatedAt   time.Time `json:"created_at"`
	MemberCount int       `json:"member_count"`
}

// AdminListFamilies returns every family on the platform with its member count.
// Unlike the family-scoped GetFamily, this is not limited to the caller's
// family. Requires RequireAuth + RequirePlatformAdmin.
func (s *Server) AdminListFamilies(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `
		SELECT f.id, f.name, f.created_at, COUNT(u.id)::int AS member_count
		FROM families f
		LEFT JOIN users u ON u.family_id = f.id
		GROUP BY f.id, f.name, f.created_at
		ORDER BY f.created_at DESC`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list families")
		return
	}
	defer rows.Close()

	families := []adminFamily{}
	for rows.Next() {
		var f adminFamily
		if err := rows.Scan(&f.ID, &f.Name, &f.CreatedAt, &f.MemberCount); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to scan family")
			return
		}
		families = append(families, f)
	}
	if rows.Err() != nil {
		writeError(w, http.StatusInternalServerError, "failed to read families")
		return
	}
	writeJSON(w, http.StatusOK, families)
}

// AdminListFamilyMembers returns the members of one family (by id) joined to
// their last-known position. It reuses the same MemberWithLocation shape and
// the same users -> member_positions JOIN as the family-scoped ListMembers, but
// is not family-scoped to the caller and does not redact emails (platform admin
// sees everything). Requires RequireAuth + RequirePlatformAdmin.
func (s *Server) AdminListFamilyMembers(w http.ResponseWriter, r *http.Request) {
	if middleware.ClaimsFromContext(r.Context()) == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	familyID := chi.URLParam(r, "id")
	if familyID == "" {
		writeError(w, http.StatusBadRequest, "family id is required")
		return
	}

	rows, err := s.Pool.Query(r.Context(), `
		SELECT u.id, u.email, u.name, u.role, u.totp_enabled, u.created_at, u.updated_at,
		       mp.lat, mp.lon, mp.ts, mp.battery_pct, mp.speed_mps, mp.motion_state, mp.accuracy_meters
		FROM users u
		LEFT JOIN member_positions mp ON mp.user_id = u.id
		WHERE u.family_id = $1
		ORDER BY u.name`, familyID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list members")
		return
	}
	defer rows.Close()

	members := []models.MemberWithLocation{}
	for rows.Next() {
		var m models.MemberWithLocation
		if err := rows.Scan(&m.ID, &m.Email, &m.Name, &m.Role, &m.TOTPEnabled, &m.CreatedAt, &m.UpdatedAt,
			&m.Lat, &m.Lon, &m.TS, &m.BatteryPct, &m.SpeedMPS, &m.MotionState, &m.AccuracyMeters); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to scan member")
			return
		}
		members = append(members, m)
	}
	if rows.Err() != nil {
		writeError(w, http.StatusInternalServerError, "failed to read members")
		return
	}
	// Distinguish "family has no members" (empty array) from "family not found".
	if len(members) == 0 {
		var exists bool
		err := s.Pool.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM families WHERE id = $1)`, familyID).Scan(&exists)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to verify family")
			return
		}
		if !exists {
			writeError(w, http.StatusNotFound, "family not found")
			return
		}
	}
	writeJSON(w, http.StatusOK, members)
}

// adminMember is a member tagged with their family id and family name, for the
// platform-wide single-map render. MemberWithLocation already carries the
// member's family_id (via the embedded User.FamilyID); this adds family_name.
type adminMember struct {
	models.MemberWithLocation
	FamilyName *string `json:"family_name"`
}

// AdminListMembers returns every member across every family, each tagged with
// family_id and family_name, for a single platform-wide map render. Members
// with no family (orphaned accounts) have null family_id/family_name and are
// still included. Requires RequireAuth + RequirePlatformAdmin.
func (s *Server) AdminListMembers(w http.ResponseWriter, r *http.Request) {
	if middleware.ClaimsFromContext(r.Context()) == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `
		SELECT u.id, u.email, u.name, u.role, u.totp_enabled, u.created_at, u.updated_at,
		       mp.lat, mp.lon, mp.ts, mp.battery_pct, mp.speed_mps, mp.motion_state, mp.accuracy_meters,
		       u.family_id, f.name
		FROM users u
		LEFT JOIN member_positions mp ON mp.user_id = u.id
		LEFT JOIN families f ON f.id = u.family_id
		ORDER BY f.name NULLS LAST, u.name`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list members")
		return
	}
	defer rows.Close()

	members := []adminMember{}
	for rows.Next() {
		var m adminMember
		var familyName *string
		if err := rows.Scan(&m.ID, &m.Email, &m.Name, &m.Role, &m.TOTPEnabled, &m.CreatedAt, &m.UpdatedAt,
			&m.Lat, &m.Lon, &m.TS, &m.BatteryPct, &m.SpeedMPS, &m.MotionState, &m.AccuracyMeters,
			&m.FamilyID, &familyName); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to scan member")
			return
		}
		m.FamilyName = familyName
		members = append(members, m)
	}
	if rows.Err() != nil {
		writeError(w, http.StatusInternalServerError, "failed to read members")
		return
	}
	writeJSON(w, http.StatusOK, members)
}

// BootstrapPlatformAdmin promotes the existing user with the given email to
// platform_admin = TRUE. It is the secure, credential-free way to create the
// first platform admin: an operator sets PLATFORM_ADMIN_EMAIL to an already-
// registered user's email, and the server grants the flag on startup. The
// email is lowercased to match the stored (lowercased) email column.
//
// This is idempotent and safe to call every startup. It logs the outcome and
// never returns a fatal error so the server still starts if the configured
// email does not (yet) exist — an operator can register the user and restart.
func (s *Server) BootstrapPlatformAdmin(ctx context.Context, email string) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return
	}
	tag, err := s.Pool.Exec(ctx,
		`UPDATE users SET platform_admin = TRUE, updated_at = now() WHERE lower(email) = $1`,
		email)
	if err != nil {
		slog.Error("platform admin bootstrap failed", "email", email, "err", err)
		return
	}
	switch tag.RowsAffected() {
	case 0:
		slog.Warn("platform admin bootstrap: no user matched PLATFORM_ADMIN_EMAIL (register the user and restart)",
			"email", email)
	case 1:
		slog.Info("platform admin promoted", "email", email)
		s.logAudit(ctx, "", "", "admin.platform_admin_bootstrap",
			"promoted "+email+" to platform admin via PLATFORM_ADMIN_EMAIL", "")
	default:
		// Should not happen (email is unique), but be explicit if it ever does.
		slog.Warn("platform admin bootstrap matched multiple users", "email", email, "count", tag.RowsAffected())
	}
}
