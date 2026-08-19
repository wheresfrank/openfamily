// Package middleware provides HTTP middleware for the API.
package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/whereabouts/whereabouts/backend/internal/auth"
)

type contextKey string

const claimsKey contextKey = "claims"

// ClaimsFromContext returns the authenticated claims, or nil.
func ClaimsFromContext(ctx context.Context) *auth.Claims {
	c, _ := ctx.Value(claimsKey).(*auth.Claims)
	return c
}

// RequireAuth validates the Bearer access token and injects claims into the
// request context. It returns 401 on missing/invalid tokens.
func RequireAuth(tm *auth.TokenManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if !strings.HasPrefix(header, "Bearer ") {
				http.Error(w, `{"error":"missing bearer token"}`, http.StatusUnauthorized)
				return
			}
			token := strings.TrimPrefix(header, "Bearer ")
			claims, err := tm.Parse(token, auth.AccessToken)
			if err != nil {
				http.Error(w, `{"error":"invalid or expired token"}`, http.StatusUnauthorized)
				return
			}
			ctx := context.WithValue(r.Context(), claimsKey, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequirePlatformAdmin enforces the platform-admin privilege boundary. It must
// run after RequireAuth (so claims are present). It re-reads the platform_admin
// flag from the database on every request — never trusting the JWT — so a
// revoked/changed admin flag takes effect immediately without a reissue. A 403
// is returned when the authenticated user is not a platform admin; a 500 when
// the lookup fails.
//
// Platform admin is distinct from family admin: the family-scoped role column
// (admin/member/child) is unchanged and irrelevant here.
func RequirePlatformAdmin(pool *pgxpool.Pool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims := ClaimsFromContext(r.Context())
			if claims == nil {
				http.Error(w, `{"error":"unauthenticated"}`, http.StatusUnauthorized)
				return
			}
			var platformAdmin bool
			err := pool.QueryRow(r.Context(),
				`SELECT platform_admin FROM users WHERE id = $1`, claims.UserID,
			).Scan(&platformAdmin)
			if err != nil {
				http.Error(w, `{"error":"failed to verify platform admin"}`, http.StatusInternalServerError)
				return
			}
			if !platformAdmin {
				http.Error(w, `{"error":"platform admin required"}`, http.StatusForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
