package handlers

import (
	"net/http"
	"time"
)

const (
	loginPerIP     = 20
	loginPerEmail  = 8
	loginWindow    = 15 * time.Minute
	registerPerIP  = 5
	registerWindow = time.Hour
	refreshPerIP   = 60
	refreshWindow  = 15 * time.Minute
	joinPerIP      = 10
	joinWindow     = 15 * time.Minute
)

// allowAuth records a hit against AuthLimit. When the limiter is nil (tests),
// the request is allowed. A 429 is written when the window is exhausted.
func (s *Server) allowAuth(w http.ResponseWriter, key string, max int, window time.Duration) bool {
	if s.AuthLimit == nil {
		return true
	}
	if s.AuthLimit.Allow(key, max, window) {
		return true
	}
	writeError(w, http.StatusTooManyRequests, "too many requests")
	return false
}

func authIPKey(kind, ip string) string {
	return kind + ":ip:" + ip
}

func authEmailKey(email string) string {
	return "login:email:" + email
}
