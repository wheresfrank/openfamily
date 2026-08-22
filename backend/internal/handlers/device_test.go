package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func TestValidateDevicePushFields(t *testing.T) {
	cases := []struct {
		platform, token, endpoint string
		wantErr                   bool
	}{
		{"ios", "abc", "", false},
		{"ios", "", "", false},
		{"ios", "abc", "https://ntfy.example/topic", true},
		{"android", "", "", false},
		{"android", "abc", "", true},
		{"android", "", "http://localhost/topic", true},
		{"web", "", "", false},
	}
	for _, tc := range cases {
		got := validateDevicePushFields(tc.platform, tc.token, tc.endpoint)
		if tc.wantErr && got == "" {
			t.Errorf("%s token=%q endpoint=%q: expected error", tc.platform, tc.token, tc.endpoint)
		}
		if !tc.wantErr && got != "" {
			t.Errorf("%s token=%q endpoint=%q: unexpected %q", tc.platform, tc.token, tc.endpoint, got)
		}
	}
}

func TestGetConfig(t *testing.T) {
	srv := &Server{NtfyBaseURL: "https://push.example.com", APNsConfigured: true}
	r := chi.NewRouter()
	r.Get("/config", srv.GetConfig)
	req := httptest.NewRequest(http.MethodGet, "/config", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	body := w.Body.String()
	if !strings.Contains(body, `"ntfy_base_url":"https://push.example.com"`) {
		t.Errorf("missing ntfy_base_url: %s", body)
	}
	if !strings.Contains(body, `"apns_configured":true`) {
		t.Errorf("missing apns_configured: %s", body)
	}
}

func TestUpdateDeviceUnauthenticated(t *testing.T) {
	srv := &Server{}
	r := chi.NewRouter()
	r.Patch("/devices/{id}", srv.UpdateDevice)
	req := httptest.NewRequest(http.MethodPatch, "/devices/abc", strings.NewReader(`{"push_token":""}`))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
