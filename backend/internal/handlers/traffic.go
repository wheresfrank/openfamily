package handlers

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/wheresfrank/openfamily/backend/internal/middleware"
)

const (
	// trafficTileURL is the upstream traffic flow raster tile endpoint
	// (TomTom Traffic Flow API v4). Kept in one place so it can be pointed at
	// a newer API without touching the handler.
	trafficTileURL = "https://api.tomtom.com/traffic/map/4/tile/flow/relative"

	trafficMaxZoom     = 22
	trafficMaxTileSize = 512 << 10
	trafficTimeout     = 10 * time.Second

	// A busy map view asks for a few dozen tiles at once, so the per-user
	// allowance is generous but still stops a runaway client from burning
	// through the operator's upstream quota.
	trafficTilesPerMinute = 600
)

// TrafficEnabled reports whether the operator configured a traffic provider
// key (TOMTOM_API_KEY). The key itself never leaves the server.
func (s *Server) TrafficEnabled() bool {
	return s.TomTomAPIKey != ""
}

// validTileCoords reports whether z/x/y address a real tile of a web-mercator
// pyramid.
func validTileCoords(z, x, y int) bool {
	if z < 0 || z > trafficMaxZoom || x < 0 || y < 0 {
		return false
	}
	limit := 1 << uint(z)
	return x < limit && y < limit
}

// parseTileSize accepts the tile edge in pixels a client wants: 256 (default)
// or 512, which needs a quarter of the requests for the same area.
func parseTileSize(raw string) (int, bool) {
	switch raw {
	case "", "256":
		return 256, true
	case "512":
		return 512, true
	}
	return 0, false
}

// trafficTileRequestURL builds the upstream URL. Only validated integers are
// interpolated, so a caller cannot steer the request anywhere else.
func trafficTileRequestURL(base string, z, x, y, size int, key string) string {
	return base + "/" + strconv.Itoa(z) + "/" + strconv.Itoa(x) + "/" + strconv.Itoa(y) +
		".png?tileSize=" + strconv.Itoa(size) + "&key=" + key
}

// GetTrafficTile proxies one live-traffic raster tile. Apps and the admin
// panel request tiles from here instead of the provider, so the API key stays
// on the server and the provider only ever sees the server, not each phone or
// the area a family is looking at. Tiles are streamed through and never stored.
func (s *Server) GetTrafficTile(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	if !s.TrafficEnabled() {
		writeError(w, http.StatusNotFound, "traffic is not configured")
		return
	}
	z, errZ := strconv.Atoi(chi.URLParam(r, "z"))
	x, errX := strconv.Atoi(chi.URLParam(r, "x"))
	y, errY := strconv.Atoi(chi.URLParam(r, "y"))
	if errZ != nil || errX != nil || errY != nil || !validTileCoords(z, x, y) {
		writeError(w, http.StatusBadRequest, "invalid tile")
		return
	}
	size, ok := parseTileSize(r.URL.Query().Get("size"))
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid tile size")
		return
	}
	if s.AuthLimit != nil &&
		!s.AuthLimit.Allow("traffic:"+claims.UserID, trafficTilesPerMinute, time.Minute) {
		writeError(w, http.StatusTooManyRequests, "too many traffic tile requests")
		return
	}

	body, contentType, status := s.fetchTrafficTile(r.Context(), z, x, y, size)
	if status != http.StatusOK {
		// A provider problem (bad key, quota, outage) is the operator's to fix;
		// the client just sees a gateway error and shows no traffic.
		writeError(w, http.StatusBadGateway, "traffic provider unavailable")
		return
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", "private, no-store")
	_, _ = w.Write(body)
}

// fetchTrafficTile downloads one tile from the provider. The returned status
// is the upstream status, or 0 when the request itself failed. The API key is
// part of the upstream URL, so errors from the HTTP client (which embed the
// URL) are never logged verbatim.
func (s *Server) fetchTrafficTile(ctx context.Context, z, x, y, size int) ([]byte, string, int) {
	base := s.trafficBase
	if base == "" {
		base = trafficTileURL
	}
	ctx, cancel := context.WithTimeout(ctx, trafficTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		trafficTileRequestURL(base, z, x, y, size, s.TomTomAPIKey), nil)
	if err != nil {
		return nil, "", 0
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		slog.Warn("traffic: provider request failed")
		return nil, "", 0
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		slog.Warn("traffic: provider returned an error", "status", resp.StatusCode)
		return nil, "", resp.StatusCode
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, trafficMaxTileSize))
	if err != nil {
		return nil, "", 0
	}
	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "image/png"
	}
	return data, contentType, http.StatusOK
}
