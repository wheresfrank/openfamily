package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/whereabouts/whereabouts/backend/internal/sms"
)

func TestAllowAuthNilLimiter(t *testing.T) {
	srv := &Server{}
	w := httptest.NewRecorder()
	if !srv.allowAuth(w, "login:ip:1.1.1.1", 1, time.Minute) {
		t.Fatal("nil limiter should allow")
	}
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d", w.Code)
	}
}

func TestAllowAuthRejectsBurst(t *testing.T) {
	srv := &Server{AuthLimit: sms.NewLimiter()}
	w1 := httptest.NewRecorder()
	if !srv.allowAuth(w1, "login:ip:1.1.1.1", 1, time.Minute) {
		t.Fatal("first hit should allow")
	}
	w2 := httptest.NewRecorder()
	if srv.allowAuth(w2, "login:ip:1.1.1.1", 1, time.Minute) {
		t.Fatal("second hit should deny")
	}
	if w2.Code != http.StatusTooManyRequests {
		t.Fatalf("status=%d body=%s", w2.Code, w2.Body.String())
	}
}
