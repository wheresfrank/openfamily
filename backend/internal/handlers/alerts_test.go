package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
)

func TestFirstName(t *testing.T) {
	if got := firstName("Frank Johnette"); got != "Frank" {
		t.Fatalf("got %q", got)
	}
	if got := firstName(""); got != "A family member" {
		t.Fatalf("got %q", got)
	}
}

func TestShareExpired(t *testing.T) {
	created := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	if shareExpired(created, created.Add(23*time.Hour)) {
		t.Fatal("23h should not expire")
	}
	if !shareExpired(created, created.Add(25*time.Hour)) {
		t.Fatal("25h should expire")
	}
}

func TestAlertSMSBody(t *testing.T) {
	got := alertSMSBody("Frank", alertCheckIn, "https://example.com/alerts/share/abc")
	if got != "Frank checked in. https://example.com/alerts/share/abc" {
		t.Fatalf("got %q", got)
	}
	sos := alertSMSBody("Frank", alertSOS, "https://example.com/x")
	if sos != "Frank sent SOS. https://example.com/x" {
		t.Fatalf("sos %q", sos)
	}
	lat, lon := 37.7, -122.4
	loc := alertLocationText("", &lat, &lon)
	if loc == "" {
		t.Fatal("expected lat/lon fallback")
	}
}

func TestPostCheckInUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Post("/alerts/check-in", srv.PostCheckIn)
	req := httptest.NewRequest(http.MethodPost, "/alerts/check-in", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestPostHelpUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Post("/alerts/help", srv.PostHelp)
	req := httptest.NewRequest(http.MethodPost, "/alerts/help", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestPostSOSUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Post("/alerts/sos", srv.PostSOS)
	req := httptest.NewRequest(http.MethodPost, "/alerts/sos", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestGetAlertUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Get("/alerts/{id}", srv.GetAlert)
	req := httptest.NewRequest(http.MethodGet, "/alerts/abc", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestResolveAlertUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Post("/alerts/{id}/resolve", srv.ResolveAlert)
	req := httptest.NewRequest(http.MethodPost, "/alerts/abc/resolve", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestShareURLRequiresHTTPS(t *testing.T) {
	srv := &Server{PublicBaseURL: "http://localhost"}
	if srv.shareURL("abc") != "" {
		t.Fatal("http origin must not produce a share URL")
	}
	srv.PublicBaseURL = "https://openfamily.example.com"
	if srv.shareURL("abc") != "https://openfamily.example.com/alerts/share/abc" {
		t.Fatalf("got %q", srv.shareURL("abc"))
	}
}
