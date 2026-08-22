package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/whereabouts/whereabouts/backend/internal/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/sms"
)

const (
	maxEmergencyContacts     = 10
	maxContactNameLength     = 120
	maxContactRelationLength = 40
)

type emergencyContactOut struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Phone     string    `json:"phone"`
	Relation  string    `json:"relation"`
	CreatedAt time.Time `json:"created_at"`
}

func validateEmergencyContact(name, phone, relation string) (string, string, string, string) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", "", "", "name is required"
	}
	if utf8.RuneCountInString(name) > maxContactNameLength {
		return "", "", "", "name is too long"
	}
	normalized, err := sms.NormalizeE164(phone)
	if err != nil || normalized == "" {
		return "", "", "", sms.ErrInvalidPhone.Error()
	}
	relation = strings.TrimSpace(relation)
	if utf8.RuneCountInString(relation) > maxContactRelationLength {
		return "", "", "", "relation is too long"
	}
	return name, normalized, relation, ""
}

// ListEmergencyContacts returns the caller's SOS contacts.
func (s *Server) ListEmergencyContacts(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `
		SELECT id, name, phone, relation, created_at
		FROM emergency_contacts WHERE user_id = $1
		ORDER BY created_at`, claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list contacts")
		return
	}
	defer rows.Close()
	contacts := []emergencyContactOut{}
	for rows.Next() {
		var c emergencyContactOut
		if err := rows.Scan(&c.ID, &c.Name, &c.Phone, &c.Relation, &c.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to scan contact")
			return
		}
		contacts = append(contacts, c)
	}
	writeJSON(w, http.StatusOK, contacts)
}

// CreateEmergencyContact adds an SOS SMS recipient for the caller.
func (s *Server) CreateEmergencyContact(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	if !s.requireManager(w, r) {
		return
	}
	var req struct {
		Name     string `json:"name"`
		Phone    string `json:"phone"`
		Relation string `json:"relation"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	name, phone, relation, msg := validateEmergencyContact(req.Name, req.Phone, req.Relation)
	if msg != "" {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	var n int
	if err := s.Pool.QueryRow(r.Context(),
		`SELECT COUNT(*) FROM emergency_contacts WHERE user_id = $1`, claims.UserID,
	).Scan(&n); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to count contacts")
		return
	}
	if n >= maxEmergencyContacts {
		writeError(w, http.StatusConflict, "contact limit reached")
		return
	}
	var c emergencyContactOut
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO emergency_contacts (user_id, name, phone, relation)
		VALUES ($1, $2, $3, $4)
		RETURNING id, name, phone, relation, created_at`,
		claims.UserID, name, phone, relation,
	).Scan(&c.ID, &c.Name, &c.Phone, &c.Relation, &c.CreatedAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create contact")
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

// DeleteEmergencyContact removes one of the caller's SOS contacts.
func (s *Server) DeleteEmergencyContact(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	if !s.requireManager(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "contact id required")
		return
	}
	tag, err := s.Pool.Exec(r.Context(),
		`DELETE FROM emergency_contacts WHERE id = $1 AND user_id = $2`, id, claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to delete contact")
		return
	}
	if tag.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "contact not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
