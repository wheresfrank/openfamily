package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/wheresfrank/openfamily/backend/internal/middleware"
)

// SupportedLanguages are the languages the apps and the admin panel ship.
var SupportedLanguages = []string{"en", "es"}

const (
	languageSourceSettings = "settings"
	languageSourceEnv      = "environment"
)

// NormalizeLanguage returns lang when it is a supported language code or the
// empty string (follow each device), and false otherwise.
func NormalizeLanguage(lang string) (string, bool) {
	if lang == "" {
		return "", true
	}
	for _, supported := range SupportedLanguages {
		if lang == supported {
			return lang, true
		}
	}
	return "", false
}

type languageSettingsResponse struct {
	DefaultLanguage string   `json:"default_language"`
	Source          string   `json:"source"`
	Supported       []string `json:"supported"`
}

// DefaultLanguage is the effective server-wide default language ("" follows
// each device).
func (s *Server) DefaultLanguage() string {
	s.langMu.RLock()
	defer s.langMu.RUnlock()
	return s.defaultLanguage
}

// LoadLanguageSettings applies the saved admin value, or the environment
// default when none was saved. Called at startup and after changes.
func (s *Server) LoadLanguageSettings(ctx context.Context) error {
	stored, present, err := s.readLanguageSetting(ctx)
	if err != nil {
		return err
	}
	effective := s.DefaultLanguageEnv
	if present {
		effective = stored
	}
	s.langMu.Lock()
	s.defaultLanguage = effective
	s.langMu.Unlock()
	return nil
}

func (s *Server) readLanguageSetting(ctx context.Context) (string, bool, error) {
	var lang string
	err := s.Pool.QueryRow(ctx,
		`SELECT default_language FROM server_settings WHERE id = 1`).Scan(&lang)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return lang, true, nil
}

func (s *Server) languageSettingsJSON(present bool) languageSettingsResponse {
	source := languageSourceEnv
	if present {
		source = languageSourceSettings
	}
	return languageSettingsResponse{
		DefaultLanguage: s.DefaultLanguage(),
		Source:          source,
		Supported:       SupportedLanguages,
	}
}

// AdminGetLanguageSettings returns the server default language. Requires
// platform admin.
func (s *Server) AdminGetLanguageSettings(w http.ResponseWriter, r *http.Request) {
	if middleware.ClaimsFromContext(r.Context()) == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	_, present, err := s.readLanguageSetting(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load language settings")
		return
	}
	writeJSON(w, http.StatusOK, s.languageSettingsJSON(present))
}

// AdminPutLanguageSettings saves the server default language and applies it
// immediately. An empty value means "follow each device".
func (s *Server) AdminPutLanguageSettings(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	var req struct {
		DefaultLanguage string `json:"default_language"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	lang, ok := NormalizeLanguage(req.DefaultLanguage)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported language")
		return
	}
	_, err := s.Pool.Exec(r.Context(), `
		INSERT INTO server_settings (id, default_language, updated_at)
		VALUES (1, $1, now())
		ON CONFLICT (id) DO UPDATE SET
			default_language = EXCLUDED.default_language,
			updated_at = now()`, lang)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save language settings")
		return
	}
	if err := s.LoadLanguageSettings(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to apply language settings")
		return
	}
	s.logAudit(r.Context(), claims.UserID, "", "settings.language_updated",
		"set the server default language to \""+lang+"\"", clientIP(r))
	writeJSON(w, http.StatusOK, s.languageSettingsJSON(true))
}
