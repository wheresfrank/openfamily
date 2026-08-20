package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/mail"
	"sort"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/whereabouts/whereabouts/backend/internal/auth"
	"github.com/whereabouts/whereabouts/backend/internal/models"
)

const (
	maxAdminNameLength  = 120
	maxAdminEmailLength = 320
	minPasswordLength   = 8
)

type validatedAdminUserInput struct {
	Email string
	Name  string
	Role  models.Role
}

func normalizeAdminFamilyName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", errors.New("family name is required")
	}
	if len([]rune(name)) > maxAdminNameLength {
		return "", fmt.Errorf("family name must be %d characters or fewer", maxAdminNameLength)
	}
	return name, nil
}

func validateAdminUserInput(email, password, name string, role models.Role) (validatedAdminUserInput, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	name = strings.TrimSpace(name)
	if email == "" || len(email) > maxAdminEmailLength {
		return validatedAdminUserInput{}, errors.New("a valid email is required")
	}
	parsed, err := mail.ParseAddress(email)
	if err != nil || parsed.Address != email {
		return validatedAdminUserInput{}, errors.New("a valid email is required")
	}
	if len([]rune(name)) == 0 || len([]rune(name)) > maxAdminNameLength {
		return validatedAdminUserInput{}, fmt.Errorf("name is required and must be %d characters or fewer", maxAdminNameLength)
	}
	if len(password) < minPasswordLength {
		return validatedAdminUserInput{}, fmt.Errorf("password must be at least %d characters", minPasswordLength)
	}
	if !role.Valid() {
		return validatedAdminUserInput{}, errors.New("invalid role")
	}
	return validatedAdminUserInput{Email: email, Name: name, Role: role}, nil
}

type adminUser struct {
	ID            string      `json:"id"`
	FamilyID      *string     `json:"family_id"`
	FamilyName    *string     `json:"family_name"`
	Email         string      `json:"email"`
	Name          string      `json:"name"`
	Role          models.Role `json:"role"`
	PlatformAdmin bool        `json:"platform_admin"`
	CreatedAt     time.Time   `json:"created_at"`
	UpdatedAt     time.Time   `json:"updated_at"`
}

type adminCreateFamilyRequest struct {
	Name        string `json:"name"`
	OwnerUserID string `json:"owner_user_id"`
}

type adminCreateUserRequest struct {
	Email    string      `json:"email"`
	Password string      `json:"password"`
	Name     string      `json:"name"`
	Role     models.Role `json:"role"`
	FamilyID string      `json:"family_id"`
}

type adminFamilyNameRequest struct {
	Name string `json:"name"`
}

type adminFamilyAssignmentRequest struct {
	FamilyID *string `json:"family_id"`
}

type adminRoleRequest struct {
	Role models.Role `json:"role"`
}

type adminPasswordRequest struct {
	Password string `json:"password"`
}

// AdminListUsers returns every account, including users without a family.
func (s *Server) AdminListUsers(w http.ResponseWriter, r *http.Request) {
	rows, err := s.Pool.Query(r.Context(), `
		SELECT u.id, u.family_id, f.name, u.email, u.name, u.role, u.platform_admin,
		       u.created_at, u.updated_at
		FROM users u
		LEFT JOIN families f ON f.id = u.family_id
		ORDER BY u.name, u.email`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list users")
		return
	}
	defer rows.Close()

	users := []adminUser{}
	for rows.Next() {
		var user adminUser
		if err := rows.Scan(&user.ID, &user.FamilyID, &user.FamilyName, &user.Email, &user.Name,
			&user.Role, &user.PlatformAdmin, &user.CreatedAt, &user.UpdatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to scan user")
			return
		}
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read users")
		return
	}
	writeJSON(w, http.StatusOK, users)
}

// AdminCreateFamily creates a family. owner_user_id is optional; when supplied,
// the existing user is assigned as the family's first admin atomically.
func (s *Server) AdminCreateFamily(w http.ResponseWriter, r *http.Request) {
	var req adminCreateFamilyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	name, err := normalizeAdminFamilyName(req.Name)
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

	var family models.Family
	if err := tx.QueryRow(r.Context(), `
		INSERT INTO families (name) VALUES ($1)
		RETURNING id, name, settings, created_at`, name).
		Scan(&family.ID, &family.Name, &family.Settings, &family.CreatedAt); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create family")
		return
	}

	if ownerID := strings.TrimSpace(req.OwnerUserID); ownerID != "" {
		var existingFamily *string
		err := tx.QueryRow(r.Context(), `
			SELECT family_id FROM users WHERE id = $1 FOR UPDATE`, ownerID).Scan(&existingFamily)
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "owner user not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to load owner user")
			return
		}
		if existingFamily != nil {
			writeError(w, http.StatusConflict, "owner user already belongs to a family")
			return
		}
		if _, err := tx.Exec(r.Context(), `
			UPDATE users SET family_id = $1, role = 'admin', updated_at = now() WHERE id = $2`, family.ID, ownerID); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to assign owner")
			return
		}
	}

	if err := tx.Commit(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to commit")
		return
	}
	s.writeAdminAudit(r.Context(), "admin.family_create", family.ID, "created family "+family.ID, clientIP(r))
	writeJSON(w, http.StatusCreated, family)
}

// AdminRenameFamily changes a family's display name.
func (s *Server) AdminRenameFamily(w http.ResponseWriter, r *http.Request) {
	familyID := chi.URLParam(r, "id")
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

// AdminCreateUser creates an account and optionally assigns it to a family.
func (s *Server) AdminCreateUser(w http.ResponseWriter, r *http.Request) {
	var req adminCreateUserRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Role == "" {
		req.Role = models.RoleMember
	}
	input, err := validateAdminUserInput(req.Email, req.Password, req.Name, req.Role)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	familyID := strings.TrimSpace(req.FamilyID)
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to hash password")
		return
	}

	if familyID != "" {
		var exists bool
		if err := s.Pool.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM families WHERE id = $1)`, familyID).Scan(&exists); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to verify family")
			return
		}
		if !exists {
			writeError(w, http.StatusNotFound, "family not found")
			return
		}
	}

	var userID string
	err = s.Pool.QueryRow(r.Context(), `
		INSERT INTO users (family_id, email, name, role, password_hash)
		VALUES (NULLIF($1, '')::uuid, $2, $3, $4, $5)
		RETURNING id`, familyID, input.Email, input.Name, input.Role, hash).Scan(&userID)
	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "email already registered")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to create user")
		return
	}
	user, err := s.adminUserByID(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load created user")
		return
	}
	writeJSON(w, http.StatusCreated, user)
}

// AdminAssignUser moves a user into a family or removes them from their family
// when family_id is null. The last family admin cannot be removed or moved.
func (s *Server) AdminAssignUser(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	var req adminFamilyAssignmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	user, err := s.adminMoveUser(r.Context(), userID, req.FamilyID)
	if err != nil {
		writeError(w, err.status, err.message)
		return
	}
	writeJSON(w, http.StatusOK, user)
}

// AdminUpdateUserRole changes a user's family role while preserving the
// invariant that every non-empty family has an admin.
func (s *Server) AdminUpdateUserRole(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	var req adminRoleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if !req.Role.Valid() {
		writeError(w, http.StatusBadRequest, "invalid role")
		return
	}
	if err := s.adminSetUserRole(r.Context(), userID, req.Role); err != nil {
		writeError(w, err.status, err.message)
		return
	}
	user, err := s.adminUserByID(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load updated user")
		return
	}
	writeJSON(w, http.StatusOK, user)
}

// AdminResetUserPassword resets an account password without exposing the hash.
func (s *Server) AdminResetUserPassword(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	var req adminPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if len(req.Password) < minPasswordLength {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("password must be at least %d characters", minPasswordLength))
		return
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to hash password")
		return
	}
	command, err := s.Pool.Exec(r.Context(), `UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2`, hash, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to reset password")
		return
	}
	if command.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type adminOperationError struct {
	status  int
	message string
}

func (s *Server) adminMoveUser(ctx context.Context, userID string, destination *string) (adminUser, *adminOperationError) {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to begin transaction"}
	}
	defer tx.Rollback(ctx)

	var currentFamily *string
	var currentRole models.Role
	if err := tx.QueryRow(ctx, `SELECT family_id, role FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&currentFamily, &currentRole); errors.Is(err, pgx.ErrNoRows) {
		return adminUser{}, &adminOperationError{http.StatusNotFound, "user not found"}
	} else if err != nil {
		return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to load user"}
	}

	var destinationID *string
	if destination != nil {
		trimmed := strings.TrimSpace(*destination)
		if trimmed != "" {
			var exists bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM families WHERE id = $1)`, trimmed).Scan(&exists); err != nil {
				return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to verify family"}
			}
			if !exists {
				return adminUser{}, &adminOperationError{http.StatusNotFound, "family not found"}
			}
			destinationID = &trimmed
		}
	}
	if stringPtrEqual(currentFamily, destinationID) {
		if err := tx.Commit(ctx); err != nil {
			return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to commit"}
		}
		user, loadErr := s.adminUserByID(ctx, userID)
		if loadErr != nil {
			return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to load user"}
		}
		return user, nil
	}

	// Lock affected family rows in a stable order so concurrent moves cannot
	// race the last-admin check or deadlock when swapping two families.
	familyLocks := make([]string, 0, 2)
	if currentFamily != nil {
		familyLocks = append(familyLocks, *currentFamily)
	}
	if destinationID != nil {
		familyLocks = append(familyLocks, *destinationID)
	}
	sort.Strings(familyLocks)
	for i, familyID := range familyLocks {
		if i > 0 && familyID == familyLocks[i-1] {
			continue
		}
		if err := tx.QueryRow(ctx, `SELECT id FROM families WHERE id = $1 FOR UPDATE`, familyID).Scan(new(string)); err != nil {
			return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to lock family"}
		}
	}

	if currentFamily != nil && currentRole == models.RoleAdmin {
		var adminCount int
		if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE family_id = $1 AND role = 'admin'`, *currentFamily).Scan(&adminCount); err != nil {
			return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to count family admins"}
		}
		if adminCount <= 1 {
			return adminUser{}, &adminOperationError{http.StatusBadRequest, "cannot remove the last family admin"}
		}
	}

	if _, err := tx.Exec(ctx, `UPDATE users SET family_id = $1, updated_at = now() WHERE id = $2`, destinationID, userID); err != nil {
		return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to assign family"}
	}
	if err := tx.Commit(ctx); err != nil {
		return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to commit"}
	}
	user, err := s.adminUserByID(ctx, userID)
	if err != nil {
		return adminUser{}, &adminOperationError{http.StatusInternalServerError, "failed to load updated user"}
	}
	return user, nil
}

func (s *Server) adminSetUserRole(ctx context.Context, userID string, role models.Role) *adminOperationError {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return &adminOperationError{http.StatusInternalServerError, "failed to begin transaction"}
	}
	defer tx.Rollback(ctx)

	var familyID *string
	var oldRole models.Role
	if err := tx.QueryRow(ctx, `SELECT family_id, role FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&familyID, &oldRole); errors.Is(err, pgx.ErrNoRows) {
		return &adminOperationError{http.StatusNotFound, "user not found"}
	} else if err != nil {
		return &adminOperationError{http.StatusInternalServerError, "failed to load user"}
	}
	if familyID != nil {
		if err := tx.QueryRow(ctx, `SELECT id FROM families WHERE id = $1 FOR UPDATE`, *familyID).Scan(new(string)); err != nil {
			return &adminOperationError{http.StatusInternalServerError, "failed to lock family"}
		}
	}
	if familyID != nil && oldRole == models.RoleAdmin && role != models.RoleAdmin {
		var adminCount int
		if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE family_id = $1 AND role = 'admin'`, *familyID).Scan(&adminCount); err != nil {
			return &adminOperationError{http.StatusInternalServerError, "failed to count family admins"}
		}
		if adminCount <= 1 {
			return &adminOperationError{http.StatusBadRequest, "cannot demote the last family admin"}
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE users SET role = $1, updated_at = now() WHERE id = $2`, role, userID); err != nil {
		return &adminOperationError{http.StatusInternalServerError, "failed to update role"}
	}
	if err := tx.Commit(ctx); err != nil {
		return &adminOperationError{http.StatusInternalServerError, "failed to commit"}
	}
	return nil
}

func (s *Server) adminUserByID(ctx context.Context, userID string) (adminUser, error) {
	var user adminUser
	err := s.Pool.QueryRow(ctx, `
		SELECT u.id, u.family_id, f.name, u.email, u.name, u.role, u.platform_admin,
		       u.created_at, u.updated_at
		FROM users u
		LEFT JOIN families f ON f.id = u.family_id
		WHERE u.id = $1`, userID).Scan(&user.ID, &user.FamilyID, &user.FamilyName, &user.Email, &user.Name,
		&user.Role, &user.PlatformAdmin, &user.CreatedAt, &user.UpdatedAt)
	return user, err
}

func (s *Server) writeAdminAudit(ctx context.Context, action, familyID, detail, ip string) {
	s.logAudit(ctx, "", familyID, action, detail, ip)
}

func stringPtrEqual(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}
