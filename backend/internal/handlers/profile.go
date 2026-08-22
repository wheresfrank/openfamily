package handlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg" // Register the JPEG decoder for image.DecodeConfig.
	_ "image/png"  // Register the PNG decoder for image.DecodeConfig.
	"io"
	"mime"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/whereabouts/whereabouts/backend/internal/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/models"
)

const (
	maxProfileNameLength = 120
	avatarMaxBytes       = 5 * 1024 * 1024
	avatarMaxDimension   = 4096
	// Use decimal megapixels here: 12 MP means 12,000,000 pixels, not 12 MiB
	// pixels. Both the width/height and total-pixel limits prevent image-bomb
	// dimensions before any full image decode is attempted.
	avatarMaxPixels int64 = 12_000_000
)

var (
	errAvatarTooLarge               = errors.New("avatar image must not exceed 5 MiB")
	errAvatarUnsupportedContentType = errors.New("avatar content type must be image/jpeg or image/png")
	errAvatarContentTypeMismatch    = errors.New("avatar content does not match Content-Type")
	errAvatarInvalidImage           = errors.New("avatar must be a valid PNG or JPEG image")
	errAvatarInvalidDimensions      = errors.New("avatar image dimensions exceed the allowed limit")
)

func normalizeProfileName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", errors.New("name is required")
	}
	if len([]rune(name)) > maxProfileNameLength {
		return "", fmt.Errorf("name must be %d characters or fewer", maxProfileNameLength)
	}
	return name, nil
}

// GetMe returns the authenticated user's editable account profile.
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

// UpdateMe changes the authenticated user's display name.
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

// profileOut is deliberately limited to the authenticated account's own
// profile fields. In particular, it contains no URL to the private avatar.
type profileOut struct {
	ID              string      `json:"id"`
	Name            string      `json:"name"`
	Email           string      `json:"email"`
	Role            models.Role `json:"role"`
	HasAvatar       bool        `json:"has_avatar"`
	AvatarVersion   int64       `json:"avatar_version"`
	AvatarUpdatedAt *time.Time  `json:"avatar_updated_at"`
}

// GetProfile returns the authenticated user's profile and avatar metadata.
// The current role is read from the database instead of a JWT claim so it
// cannot become stale.
func (s *Server) GetProfile(w http.ResponseWriter, r *http.Request) {
	setPrivateProfileHeaders(w)
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	var profile profileOut
	err := s.Pool.QueryRow(r.Context(), `
		SELECT id, name, email, role, avatar_data IS NOT NULL, avatar_version, avatar_updated_at
		FROM users
		WHERE id = $1`, claims.UserID,
	).Scan(
		&profile.ID,
		&profile.Name,
		&profile.Email,
		&profile.Role,
		&profile.HasAvatar,
		&profile.AvatarVersion,
		&profile.AvatarUpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "profile not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load profile")
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

// GetProfileAvatar returns the caller's own avatar bytes. Avatars are never
// available via a public URL and may only be retrieved with an access token.
func (s *Server) GetProfileAvatar(w http.ResponseWriter, r *http.Request) {
	setPrivateProfileHeaders(w)
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	var avatar []byte
	var contentType string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT avatar_data, avatar_content_type
		FROM users
		WHERE id = $1 AND avatar_data IS NOT NULL`, claims.UserID,
	).Scan(&avatar, &contentType)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "profile avatar not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load profile avatar")
		return
	}
	writePrivateAvatar(w, avatar, contentType)
}

// PutProfileAvatar stores a PNG or JPEG avatar for the authenticated user.
// The request body is the raw image bytes, not multipart form data.
func (s *Server) PutProfileAvatar(w http.ResponseWriter, r *http.Request) {
	setPrivateProfileHeaders(w)
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	declaredContentType, err := avatarContentType(r.Header.Get("Content-Type"))
	if err != nil {
		writeError(w, http.StatusUnsupportedMediaType, err.Error())
		return
	}
	if r.ContentLength > avatarMaxBytes {
		writeError(w, http.StatusRequestEntityTooLarge, errAvatarTooLarge.Error())
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, avatarMaxBytes)
	avatar, err := io.ReadAll(r.Body)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			writeError(w, http.StatusRequestEntityTooLarge, errAvatarTooLarge.Error())
			return
		}
		writeError(w, http.StatusBadRequest, "failed to read avatar image")
		return
	}

	contentType, err := validateAvatarUpload(avatar, declaredContentType)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	var (
		familyID        *string
		avatarVersion   int64
		avatarUpdatedAt time.Time
	)
	err = s.Pool.QueryRow(r.Context(), `
		UPDATE users
		SET avatar_data = $1,
		    avatar_content_type = $2,
		    avatar_updated_at = now(),
		    avatar_version = avatar_version + 1,
		    updated_at = now()
		WHERE id = $3
		RETURNING family_id, avatar_version, avatar_updated_at`, avatar, contentType, claims.UserID,
	).Scan(&familyID, &avatarVersion, &avatarUpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "profile not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save profile avatar")
		return
	}

	s.logAudit(r.Context(), claims.UserID, stringValue(familyID), "profile.avatar_uploaded", "uploaded profile avatar", clientIP(r))
	s.broadcastAvatarUpdate(familyID, claims.UserID, true, avatarVersion, &avatarUpdatedAt)
	w.WriteHeader(http.StatusNoContent)
}

// DeleteProfileAvatar removes the authenticated user's avatar. It is
// intentionally idempotent: deleting an already-empty avatar also succeeds.
func (s *Server) DeleteProfileAvatar(w http.ResponseWriter, r *http.Request) {
	setPrivateProfileHeaders(w)
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	var (
		familyID      *string
		avatarVersion int64
	)
	err := s.Pool.QueryRow(r.Context(), `
		UPDATE users
		SET avatar_data = NULL,
		    avatar_content_type = NULL,
		    avatar_updated_at = NULL,
		    avatar_version = avatar_version + 1,
		    updated_at = now()
		WHERE id = $1
		RETURNING family_id, avatar_version`, claims.UserID,
	).Scan(&familyID, &avatarVersion)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "profile not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to delete profile avatar")
		return
	}

	s.logAudit(r.Context(), claims.UserID, stringValue(familyID), "profile.avatar_deleted", "deleted profile avatar", clientIP(r))
	s.broadcastAvatarUpdate(familyID, claims.UserID, false, avatarVersion, nil)
	w.WriteHeader(http.StatusNoContent)
}

// avatarContentType parses and limits the request Content-Type. It accepts
// parameters (for example, a browser-provided charset) but stores only the
// canonical media type.
func avatarContentType(header string) (string, error) {
	mediaType, _, err := mime.ParseMediaType(header)
	if err != nil {
		return "", errAvatarUnsupportedContentType
	}
	mediaType = strings.ToLower(mediaType)
	if mediaType != "image/jpeg" && mediaType != "image/png" {
		return "", errAvatarUnsupportedContentType
	}
	return mediaType, nil
}

// validateAvatarUpload validates a buffered avatar. DecodeConfig first proves
// the format and bounds the dimensions before a full decode allocates pixels;
// the full decode then rejects truncated or corrupt image data.
func validateAvatarUpload(avatar []byte, declaredContentType string) (string, error) {
	if len(avatar) == 0 {
		return "", errAvatarInvalidImage
	}
	if len(avatar) > avatarMaxBytes {
		return "", errAvatarTooLarge
	}

	if sniffedContentType := http.DetectContentType(avatar); sniffedContentType != declaredContentType {
		return "", errAvatarContentTypeMismatch
	}

	config, format, err := image.DecodeConfig(bytes.NewReader(avatar))
	if err != nil {
		return "", errAvatarInvalidImage
	}
	decodedContentType := ""
	switch format {
	case "jpeg":
		decodedContentType = "image/jpeg"
	case "png":
		decodedContentType = "image/png"
	default:
		return "", errAvatarInvalidImage
	}
	if decodedContentType != declaredContentType {
		return "", errAvatarContentTypeMismatch
	}

	if config.Width <= 0 || config.Height <= 0 ||
		config.Width > avatarMaxDimension || config.Height > avatarMaxDimension ||
		int64(config.Width)*int64(config.Height) > avatarMaxPixels {
		return "", errAvatarInvalidDimensions
	}

	// DecodeConfig accepts a complete header even when a later image-data chunk
	// (or JPEG scan) is truncated. Only decode after the bounded dimensions are
	// known, then discard the decoded image: storage needs the original bytes,
	// not a re-encoded image.
	_, decodedFormat, err := image.Decode(bytes.NewReader(avatar))
	if err != nil || decodedFormat != format {
		return "", errAvatarInvalidImage
	}
	return decodedContentType, nil
}

// setPrivateProfileHeaders is applied to every profile/avatar response,
// including errors, because profile data and image bytes must not be stored by
// shared caches or rendered as a different content type.
func setPrivateProfileHeaders(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
}

// writePrivateAvatar writes image data returned from any authenticated avatar
// endpoint. The database constraint is not treated as the only defense: an
// out-of-band data change cannot make this endpoint send arbitrary content with
// a browser-interpretable MIME type.
func writePrivateAvatar(w http.ResponseWriter, avatar []byte, contentType string) {
	if contentType != "image/jpeg" && contentType != "image/png" {
		writeError(w, http.StatusInternalServerError, "stored profile avatar has an invalid content type")
		return
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(avatar)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(avatar)
}

func stringValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
