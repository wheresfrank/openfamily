package handlers

import "net/http"

// GetConfig returns public runtime settings the generic APK needs without a
// dart-define (notably the operator's ntfy origin). Auth is optional.
func (s *Server) GetConfig(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ntfy_base_url":   s.NtfyBaseURL,
		"apns_configured": s.APNsConfigured,
	})
}
