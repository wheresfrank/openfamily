package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func TestNormalizeEmergencyContact(t *testing.T) {
	name, phone, digits, relation, err := normalizeEmergencyContact(
		"  Mom  ", "(415) 555-0132", " Family ",
	)
	if err != nil {
		t.Fatalf("valid contact rejected: %v", err)
	}
	if name != "Mom" || phone != "(415) 555-0132" || digits != "4155550132" || relation != "Family" {
		t.Fatalf("got name=%q phone=%q digits=%q relation=%q", name, phone, digits, relation)
	}

	cases := []struct {
		name, phone, relation string
	}{
		{"", "4155550132", ""},
		{"Mom", "", ""},
		{"Mom", "123", ""},
		{"Mom", "1234567890123456", ""},
		{strings.Repeat("x", 81), "4155550132", ""},
		{"Mom", "4155550132", strings.Repeat("x", 41)},
	}
	for _, c := range cases {
		if _, _, _, _, err := normalizeEmergencyContact(c.name, c.phone, c.relation); err == nil {
			t.Errorf("accepted invalid contact name=%q phone=%q relation=%q", c.name, c.phone, c.relation)
		}
	}
}

func TestPhoneDigitsStripsPunctuation(t *testing.T) {
	got := phoneDigits("+1 (415) 555-0132")
	if got != "14155550132" {
		t.Fatalf("got %q", got)
	}
}

func TestListContactsUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Get("/me/contacts", srv.ListContacts)
	req := httptest.NewRequest(http.MethodGet, "/me/contacts", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestCreateContactUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Post("/me/contacts", srv.CreateContact)
	req := httptest.NewRequest(http.MethodPost, "/me/contacts", strings.NewReader(`{"name":"Mom","phone":"4155550132"}`))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestDeleteContactUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Delete("/me/contacts/{id}", srv.DeleteContact)
	req := httptest.NewRequest(http.MethodDelete, "/me/contacts/abc", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
