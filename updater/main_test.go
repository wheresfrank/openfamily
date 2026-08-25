package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestStatusIsReadableWithoutApplyToken(t *testing.T) {
	u := &updater{repoDir: t.TempDir(), dataDir: t.TempDir()}
	req := httptest.NewRequest(http.MethodGet, "/status", nil)
	rec := httptest.NewRecorder()

	u.handleStatus(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status code = %d, want %d", rec.Code, http.StatusOK)
	}
	var payload struct {
		CanApply bool `json:"can_apply"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if payload.CanApply {
		t.Fatal("status must not advertise apply capability without a token")
	}
}
