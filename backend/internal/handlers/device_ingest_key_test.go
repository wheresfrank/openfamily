package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestRotateDeviceIngestKeyUnauthenticated verifies the rotation endpoint
// requires an authenticated caller (checked before any database access, so
// this needs no Postgres).
func TestRotateDeviceIngestKeyUnauthenticated(t *testing.T) {
	s := &Server{}
	req := httptest.NewRequest(http.MethodPost, "/devices/x/ingest-key", nil)
	rec := httptest.NewRecorder()
	s.RotateDeviceIngestKey(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d, want %d", rec.Code, http.StatusUnauthorized)
	}
}
