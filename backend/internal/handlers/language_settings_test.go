package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestNormalizeLanguage(t *testing.T) {
	for _, ok := range []string{"", "en", "es"} {
		if got, valid := NormalizeLanguage(ok); !valid || got != ok {
			t.Errorf("NormalizeLanguage(%q) = %q, %v", ok, got, valid)
		}
	}
	for _, bad := range []string{"fr", "ES", "es-VE", " es", "english"} {
		if _, valid := NormalizeLanguage(bad); valid {
			t.Errorf("NormalizeLanguage(%q) should be rejected", bad)
		}
	}
}

func TestGetConfigAdvertisesDefaultLanguage(t *testing.T) {
	srv := &Server{defaultLanguage: "es"}
	w := httptest.NewRecorder()
	srv.GetConfig(w, httptest.NewRequest(http.MethodGet, "/config", nil))
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["default_language"] != "es" {
		t.Fatalf("default_language=%v", body["default_language"])
	}
}

func TestLanguageSettingsJSONSource(t *testing.T) {
	srv := &Server{defaultLanguage: "es"}
	if got := srv.languageSettingsJSON(false); got.Source != languageSourceEnv || got.DefaultLanguage != "es" {
		t.Fatalf("unexpected env response: %+v", got)
	}
	if got := srv.languageSettingsJSON(true); got.Source != languageSourceSettings {
		t.Fatalf("unexpected settings response: %+v", got)
	}
}
