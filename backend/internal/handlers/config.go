package handlers

import (
	"net/http"

	"github.com/whereabouts/whereabouts/backend/internal/config"
)

// GetConfig returns public runtime settings the generic APK needs without a
// dart-define (ntfy origin and map tile templates). Auth is optional.
func (s *Server) GetConfig(w http.ResponseWriter, r *http.Request) {
	tileURL := s.TileURL
	if tileURL == "" {
		tileURL = config.DefaultTileURL
	}
	satelliteURL := s.SatelliteTileURL
	if satelliteURL == "" {
		satelliteURL = config.DefaultSatelliteTileURL
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ntfy_base_url":      s.NtfyBaseURL,
		"apns_configured":    s.APNsConfigured,
		"tile_url":           tileURL,
		"satellite_tile_url": satelliteURL,
	})
}
