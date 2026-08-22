package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
)

// TestAdminRouteSmoke ensures the admin API (under /api/admin/*) and the admin
// SPA static serving (under /admin/*) coexist without a chi registration panic,
// and that the two namespaces never collide. This mirrors main.go's routing:
// the API lives under /api/admin/* and the SPA is served at /admin/* with an
// index.html fallback, so the SPA catch-all cannot shadow any API route.
func TestAdminRouteSmoke(t *testing.T) {
	r := chi.NewRouter()

	apiHit := false
	staticHit := false

	// Admin API group (explicit routes under /api/admin/*).
	r.Group(func(r chi.Router) {
		r.Get("/api/admin/families", func(w http.ResponseWriter, r *http.Request) { apiHit = true })
		r.Get("/api/admin/families/{id}/members", func(w http.ResponseWriter, r *http.Request) { apiHit = true })
		r.Get("/api/admin/members", func(w http.ResponseWriter, r *http.Request) { apiHit = true })
		r.Get("/api/admin/users", func(w http.ResponseWriter, r *http.Request) { apiHit = true })
		r.Get("/api/admin/apk", func(w http.ResponseWriter, r *http.Request) { apiHit = true })
		r.Post("/api/admin/apk/build", func(w http.ResponseWriter, r *http.Request) { apiHit = true })
		r.Get("/api/admin/apk/status", func(w http.ResponseWriter, r *http.Request) { apiHit = true })
	})

	// Admin SPA static catch-all (public), with index.html fallback.
	r.Get("/admin", func(w http.ResponseWriter, r *http.Request) { staticHit = true })
	r.Get("/admin/", func(w http.ResponseWriter, r *http.Request) { staticHit = true })
	r.Get("/admin/*", func(w http.ResponseWriter, r *http.Request) { staticHit = true })

	cases := []struct {
		path   string
		method string
		api    bool
	}{
		// API routes hit the API handlers.
		{"/api/admin/families", "GET", true},
		{"/api/admin/families/abc/members", "GET", true},
		{"/api/admin/members", "GET", true},
		{"/api/admin/users", "GET", true},
		{"/api/admin/apk", "GET", true},
		{"/api/admin/apk/build", "POST", true},
		{"/api/admin/apk/status", "GET", true},
		// SPA routes hit the static handler (including fallback paths).
		{"/admin", "GET", false},
		{"/admin/", "GET", false},
		{"/admin/app.js", "GET", false},       // static asset
		{"/admin/unknownroute", "GET", false}, // SPA fallback
		// An API-like path under /admin/ must NOT hit the API; it falls to the SPA.
		{"/admin/families", "GET", false},
		{"/admin/users", "GET", false},
		{"/admin/apk/build", "GET", false},
	}
	for _, c := range cases {
		apiHit, staticHit = false, false
		req := httptest.NewRequest(c.method, c.path, nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if c.api && !apiHit {
			t.Errorf("expected API route for %s %s, got static=%v status=%d", c.method, c.path, staticHit, w.Code)
		}
		if !c.api && !staticHit {
			t.Errorf("expected static/SPA route for %s %s, got api=%v status=%d", c.method, c.path, apiHit, w.Code)
		}
	}
}
