package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func TestValidateEmergencyContact(t *testing.T) {
	name, phone, relation, msg := validateEmergencyContact("  Mom  ", "+1 (555) 123-4567", " Family ")
	if msg != "" {
		t.Fatalf("unexpected %q", msg)
	}
	if name != "Mom" || phone != "+15551234567" || relation != "Family" {
		t.Fatalf("got %q %q %q", name, phone, relation)
	}
	if _, _, _, msg := validateEmergencyContact("", "+15551234567", ""); msg == "" {
		t.Fatal("expected name required")
	}
	if _, _, _, msg := validateEmergencyContact("Mom", "555", ""); msg == "" {
		t.Fatal("expected invalid phone")
	}
}

func TestListEmergencyContactsUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Get("/me/contacts", srv.ListEmergencyContacts)
	req := httptest.NewRequest(http.MethodGet, "/me/contacts", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestCreateEmergencyContactUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Post("/me/contacts", srv.CreateEmergencyContact)
	req := httptest.NewRequest(http.MethodPost, "/me/contacts", strings.NewReader(`{"name":"Mom","phone":"+15551234567"}`))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
