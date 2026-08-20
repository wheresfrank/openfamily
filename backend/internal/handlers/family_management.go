package handlers

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/whereabouts/whereabouts/backend/internal/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/models"
)

const inviteLifetime = 7 * 24 * time.Hour

func normalizeInviteCode(code string) (string, error) {
	code = strings.TrimSpace(code)
	if len(code) != 6 {
		return "", errors.New("invite code must be 6 digits")
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			return "", errors.New("invite code must be 6 digits")
		}
	}
	return code, nil
}

func newInviteCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()+100000), nil
}

type familyInvite struct {
	Code      string    `json:"code"`
	FamilyID  string    `json:"family_id"`
	ExpiresAt time.Time `json:"expires_at"`
}

type joinFamilyRequest struct {
	Code string `json:"code"`
}

// CreateInvite creates a short-lived invite code for the caller's family.
func (s *Server) CreateInvite(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	familyID, err := s.familyIDForUser(r.Context(), claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load family")
		return
	}
	if familyID == "" {
		writeError(w, http.StatusNotFound, "no family")
		return
	}
	isAdmin, err := s.userIsAdmin(r.Context(), claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load role")
		return
	}
	if !isAdmin {
		writeError(w, http.StatusForbidden, "family admin only")
		return
	}

	expiresAt := time.Now().UTC().Add(inviteLifetime)
	for attempt := 0; attempt < 5; attempt++ {
		code, err := newInviteCode()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to generate invite code")
			return
		}
		var invite familyInvite
		err = s.Pool.QueryRow(r.Context(), `
			INSERT INTO family_invites (code, family_id, created_by, expires_at)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (code) DO NOTHING
			RETURNING code, family_id, expires_at`, code, familyID, claims.UserID, expiresAt).
			Scan(&invite.Code, &invite.FamilyID, &invite.ExpiresAt)
		if errors.Is(err, pgx.ErrNoRows) {
			continue
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to create invite")
			return
		}
		writeJSON(w, http.StatusCreated, invite)
		return
	}
	writeError(w, http.StatusInternalServerError, "failed to create unique invite code")
}

// JoinFamily consumes an invite code and assigns the caller to its family.
func (s *Server) JoinFamily(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	var req joinFamilyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	code, err := normalizeInviteCode(req.Code)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to begin transaction")
		return
	}
	defer tx.Rollback(r.Context())

	var existingFamily *string
	if err := tx.QueryRow(r.Context(), `SELECT family_id FROM users WHERE id = $1 FOR UPDATE`, claims.UserID).Scan(&existingFamily); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load user")
		return
	}
	if existingFamily != nil {
		writeError(w, http.StatusConflict, "user already belongs to a family")
		return
	}

	var family models.Family
	err = tx.QueryRow(r.Context(), `
		SELECT f.id, f.name, f.settings, f.created_at
		FROM family_invites i
		JOIN families f ON f.id = i.family_id
		WHERE i.code = $1 AND i.expires_at > now()
		FOR UPDATE OF i, f`, code).
		Scan(&family.ID, &family.Name, &family.Settings, &family.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "invite code is invalid or expired")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load invite")
		return
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE users SET family_id = $1, role = 'member', updated_at = now() WHERE id = $2`, family.ID, claims.UserID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to join family")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to commit")
		return
	}
	s.logAudit(r.Context(), claims.UserID, family.ID, "family.join", "joined family via invite", clientIP(r))
	writeJSON(w, http.StatusOK, familyOut{Family: family, Role: models.RoleMember, UserID: claims.UserID})
}

// RenameFamily lets a family admin update the family's display name.
func (s *Server) RenameFamily(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	familyID, err := s.familyIDForUser(r.Context(), claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load family")
		return
	}
	if familyID == "" {
		writeError(w, http.StatusNotFound, "no family")
		return
	}
	isAdmin, err := s.userIsAdmin(r.Context(), claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load role")
		return
	}
	if !isAdmin {
		writeError(w, http.StatusForbidden, "family admin only")
		return
	}
	var req adminFamilyNameRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	name, err := normalizeAdminFamilyName(req.Name)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	var family models.Family
	err = s.Pool.QueryRow(r.Context(), `
		UPDATE families SET name = $1 WHERE id = $2
		RETURNING id, name, settings, created_at`, name, familyID).
		Scan(&family.ID, &family.Name, &family.Settings, &family.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "family not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to rename family")
		return
	}
	writeJSON(w, http.StatusOK, family)
}

// RemoveFamilyMember removes a member from the caller's family without
// deleting their account. The last family admin cannot be removed.
func (s *Server) RemoveFamilyMember(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	familyID, err := s.familyIDForUser(r.Context(), claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load family")
		return
	}
	if familyID == "" {
		writeError(w, http.StatusNotFound, "no family")
		return
	}
	isAdmin, err := s.userIsAdmin(r.Context(), claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load role")
		return
	}
	if !isAdmin {
		writeError(w, http.StatusForbidden, "family admin only")
		return
	}

	memberID := chi.URLParam(r, "id")
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to begin transaction")
		return
	}
	defer tx.Rollback(r.Context())
	if err := tx.QueryRow(r.Context(), `SELECT id FROM families WHERE id = $1 FOR UPDATE`, familyID).Scan(new(string)); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to lock family")
		return
	}
	var role models.Role
	err = tx.QueryRow(r.Context(), `SELECT role FROM users WHERE id = $1 AND family_id = $2 FOR UPDATE`, memberID, familyID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "member not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load member")
		return
	}
	if role == models.RoleAdmin {
		var adminCount int
		if err := tx.QueryRow(r.Context(), `SELECT COUNT(*) FROM users WHERE family_id = $1 AND role = 'admin'`, familyID).Scan(&adminCount); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to count family admins")
			return
		}
		if adminCount <= 1 {
			writeError(w, http.StatusBadRequest, "cannot remove the last family admin")
			return
		}
	}
	if _, err := tx.Exec(r.Context(), `UPDATE users SET family_id = NULL, role = 'member', updated_at = now() WHERE id = $1`, memberID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to remove member")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to commit")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}
