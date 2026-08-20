package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/whereabouts/whereabouts/backend/internal/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/models"
)

func normalizeProfileName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", errors.New("name is required")
	}
	if len([]rune(name)) > maxAdminNameLength {
		return "", fmt.Errorf("name must be %d characters or fewer", maxAdminNameLength)
	}
	return name, nil
}

func (s *Server) GetMe(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	user, err := s.userProfileByID(r, claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load profile")
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) UpdateMe(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	name, err := normalizeProfileName(req.Name)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	user, err := s.userProfileByID(r, claims.UserID, name)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update profile")
		return
	}
	s.logAudit(r.Context(), claims.UserID, "", "profile.update", "updated profile name", clientIP(r))
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) userProfileByID(r *http.Request, userID string, updateName ...string) (models.User, error) {
	ctx := r.Context()
	var user models.User
	if len(updateName) > 0 {
		err := s.Pool.QueryRow(ctx, `
			UPDATE users SET name = $1, updated_at = now() WHERE id = $2
			RETURNING id, family_id, email, name, role, totp_enabled, created_at, updated_at`,
			updateName[0], userID).Scan(&user.ID, &user.FamilyID, &user.Email, &user.Name, &user.Role,
			&user.TOTPEnabled, &user.CreatedAt, &user.UpdatedAt)
		return user, err
	}
	err := s.Pool.QueryRow(ctx, `
		SELECT id, family_id, email, name, role, totp_enabled, created_at, updated_at
		FROM users WHERE id = $1`, userID).
		Scan(&user.ID, &user.FamilyID, &user.Email, &user.Name, &user.Role,
			&user.TOTPEnabled, &user.CreatedAt, &user.UpdatedAt)
	return user, err
}
