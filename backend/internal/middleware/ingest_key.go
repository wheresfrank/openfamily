package middleware

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/wheresfrank/openfamily/backend/internal/auth"
)

// DeviceKeyHeader carries the per-device ingest credential as
// "<device_id>.<ingest_key>". The ingest key is a write-only, device-scoped
// secret: it authorizes POST /locations and POST /devices/heartbeat only.
//
// It exists because the app's background reporter runs in a headless Flutter
// isolate where the Keystore-backed secure store (which holds the refresh
// token) is not reliably reachable, so a JWT-only design silently stops
// reporting as soon as the 15-minute access token expires. The key carries no
// expiry; it dies with the device row (logout clears it client-side) and can
// be rotated via POST /devices/{id}/ingest-key. Server-side only its SHA-256
// hash is persisted, so a database read does not leak usable credentials.
const DeviceKeyHeader = "X-Device-Key"

// GenerateDeviceIngestKey returns a new random ingest key (32 bytes,
// base64url-encoded unpadded, no '.' so header parsing by the first dot is
// unambiguous).
func GenerateDeviceIngestKey() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// HashDeviceIngestKey returns the SHA-256 of an ingest key — the only form
// stored server-side.
func HashDeviceIngestKey(key string) []byte {
	sum := sha256.Sum256([]byte(key))
	return sum[:]
}

// EncodeIngestKeyHash renders a hash for the TEXT ingest_key_hash column.
func EncodeIngestKeyHash(hash []byte) string {
	return hex.EncodeToString(hash)
}

// ParseDeviceKeyHeader splits "<device_id>.<ingest_key>". Reports false for
// missing parts, extra segments, or whitespace-padded garbage.
func ParseDeviceKeyHeader(header string) (deviceID, key string, ok bool) {
	header = strings.TrimSpace(header)
	dot := strings.IndexByte(header, '.')
	if dot <= 0 || dot == len(header)-1 {
		return "", "", false
	}
	deviceID, key = header[:dot], header[dot+1:]
	if strings.ContainsAny(deviceID, " \t") || strings.ContainsAny(key, " \t") {
		return "", "", false
	}
	return deviceID, key, true
}

// ingestKeysEqual constant-time-compares a presented key against the stored
// hex-encoded hash.
func ingestKeysEqual(storedHashHex, presentedKey string) bool {
	candidate := EncodeIngestKeyHash(HashDeviceIngestKey(presentedKey))
	return subtle.ConstantTimeCompare([]byte(storedHashHex), []byte(candidate)) == 1
}

// RequireAuthOrDeviceIngestKey guards the ingest endpoints (POST /locations
// and POST /devices/heartbeat). It accepts either:
//
//   - a valid Bearer access token (equivalent to RequireAuth +
//     RequireTokenVersion: the version is re-checked here because these routes
//     are deliberately outside the JWT route group), or
//   - DeviceKeyHeader with a valid per-device ingest key.
//
// Both branches inject claims (at minimum the user id) so the handlers share
// one code path regardless of credential type.
func RequireAuthOrDeviceIngestKey(tm *auth.TokenManager, pool *pgxpool.Pool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if strings.HasPrefix(header, "Bearer ") {
				claims, err := tm.Parse(strings.TrimPrefix(header, "Bearer "), auth.AccessToken)
				if err != nil {
					http.Error(w, `{"error":"invalid or expired token"}`, http.StatusUnauthorized)
					return
				}
				var version int
				if err := pool.QueryRow(r.Context(),
					`SELECT token_version FROM users WHERE id = $1`, claims.UserID,
				).Scan(&version); err != nil || version != claims.TokenVersion {
					http.Error(w, `{"error":"invalid or expired token"}`, http.StatusUnauthorized)
					return
				}
				next.ServeHTTP(w, r.WithContext(ContextWithClaims(r.Context(), claims)))
				return
			}

			deviceKeyHeader := r.Header.Get(DeviceKeyHeader)
			if deviceKeyHeader == "" {
				http.Error(w, `{"error":"missing credentials"}`, http.StatusUnauthorized)
				return
			}
			deviceID, key, ok := ParseDeviceKeyHeader(deviceKeyHeader)
			if !ok {
				http.Error(w, `{"error":"malformed device key"}`, http.StatusUnauthorized)
				return
			}
			var ownerID *string
			var storedHash *string
			if err := pool.QueryRow(r.Context(),
				`SELECT user_id, ingest_key_hash FROM devices WHERE id = $1`, deviceID,
			).Scan(&ownerID, &storedHash); err != nil || ownerID == nil || storedHash == nil {
				http.Error(w, `{"error":"invalid device key"}`, http.StatusUnauthorized)
				return
			}
			if !ingestKeysEqual(*storedHash, key) {
				http.Error(w, `{"error":"invalid device key"}`, http.StatusUnauthorized)
				return
			}
			next.ServeHTTP(w, r.WithContext(ContextWithClaims(r.Context(),
				&auth.Claims{UserID: *ownerID, TokenType: auth.AccessToken})))
		})
	}
}
