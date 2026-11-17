package handlers

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/wheresfrank/openfamily/backend/internal/middleware"
)

const (
	// maxExportRange bounds one export; the 90-day retention window still
	// applies to "from".
	maxExportRange = 31 * 24 * time.Hour

	// A gap this long between consecutive fixes starts a new track segment
	// instead of drawing a straight line across the missing time.
	exportSegmentGap = 15 * time.Minute
)

// ExportMemberHistory downloads a family member's track as GPX (default) or
// GeoJSON. Access rules match GetMemberHistory.
func (s *Server) ExportMemberHistory(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	memberID := chi.URLParam(r, "id")
	callerFamily, err := s.familyIDForUser(r.Context(), claims.UserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load family")
		return
	}
	targetFamily, found, err := s.userFamilyID(r.Context(), memberID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load member")
		return
	}
	status, msg, allowed := familyHistoryAccess(callerFamily, targetFamily, found)
	if !allowed {
		writeError(w, status, msg)
		return
	}
	s.exportHistory(w, r, claims.UserID, memberID, targetFamily)
}

// AdminExportMemberHistory is the platform-admin variant of
// ExportMemberHistory. RequireAuth + RequirePlatformAdmin are enforced by the
// route group.
func (s *Server) AdminExportMemberHistory(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	memberID := chi.URLParam(r, "id")
	targetFamily, found, err := s.userFamilyID(r.Context(), memberID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load member")
		return
	}
	if !found {
		writeError(w, http.StatusNotFound, "member not found")
		return
	}
	s.exportHistory(w, r, claims.UserID, memberID, targetFamily)
}

func (s *Server) exportHistory(w http.ResponseWriter, r *http.Request, callerID, memberID, familyID string) {
	if memberID == "" {
		writeError(w, http.StatusBadRequest, "member id is required")
		return
	}
	format := r.URL.Query().Get("format")
	if format == "" {
		format = "gpx"
	}
	if format != "gpx" && format != "geojson" {
		writeError(w, http.StatusBadRequest, "format must be gpx or geojson")
		return
	}
	from, to, errMsg, ok := parseHistoryRangeMax(r, time.Now(), maxExportRange, "range must be at most 31 days")
	if !ok {
		writeError(w, http.StatusBadRequest, errMsg)
		return
	}
	out, err := s.buildMemberHistoryCapped(r.Context(), memberID, familyID, from, to, 0)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load history")
		return
	}
	name := s.memberDisplayName(r.Context(), memberID)
	s.logAudit(r.Context(), callerID, familyID, "history.export",
		"exported "+format+" history of member "+memberID, clientIP(r))

	filename := fmt.Sprintf("openfamily-track-%s.%s", from.UTC().Format("2006-01-02"), format)
	var body []byte
	var contentType string
	if format == "gpx" {
		body, err = renderGPX(out, name)
		contentType = "application/gpx+xml"
	} else {
		body, err = renderGeoJSON(out, name)
		contentType = "application/geo+json"
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to render export")
		return
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Disposition", `attachment; filename="`+filename+`"`)
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(body)
}

func (s *Server) memberDisplayName(ctx context.Context, userID string) string {
	var name string
	if err := s.Pool.QueryRow(ctx, `SELECT name FROM users WHERE id = $1`, userID).Scan(&name); err != nil {
		return ""
	}
	return name
}

// splitSegments breaks the trail wherever consecutive fixes are further apart
// than exportSegmentGap.
func splitSegments(points []trailPoint) [][]trailPoint {
	var segments [][]trailPoint
	var cur []trailPoint
	for _, p := range points {
		if len(cur) > 0 && p.TS.Sub(cur[len(cur)-1].TS) > exportSegmentGap {
			segments = append(segments, cur)
			cur = nil
		}
		cur = append(cur, p)
	}
	if len(cur) > 0 {
		segments = append(segments, cur)
	}
	return segments
}

func exportTitle(name string, from time.Time) string {
	if name == "" {
		name = "OpenFamily"
	}
	return fmt.Sprintf("%s %s", name, from.UTC().Format("2006-01-02"))
}

type gpxWpt struct {
	Lat  string `xml:"lat,attr"`
	Lon  string `xml:"lon,attr"`
	Time string `xml:"time"`
	Name string `xml:"name"`
	Desc string `xml:"desc,omitempty"`
}

type gpxTrkpt struct {
	Lat  string `xml:"lat,attr"`
	Lon  string `xml:"lon,attr"`
	Time string `xml:"time"`
}

type gpxTrkseg struct {
	Points []gpxTrkpt `xml:"trkpt"`
}

type gpxDoc struct {
	XMLName xml.Name `xml:"gpx"`
	Version string   `xml:"version,attr"`
	Creator string   `xml:"creator,attr"`
	Xmlns   string   `xml:"xmlns,attr"`
	Meta    struct {
		Name string `xml:"name"`
		Time string `xml:"time"`
	} `xml:"metadata"`
	Waypoints []gpxWpt `xml:"wpt"`
	Track     struct {
		Name     string      `xml:"name"`
		Segments []gpxTrkseg `xml:"trkseg"`
	} `xml:"trk"`
}

func coord(v float64) string { return fmt.Sprintf("%.6f", v) }

func renderGPX(h historyOut, name string) ([]byte, error) {
	var doc gpxDoc
	doc.Version = "1.1"
	doc.Creator = "OpenFamily"
	doc.Xmlns = "http://www.topografix.com/GPX/1/1"
	title := exportTitle(name, h.From)
	doc.Meta.Name = title
	doc.Meta.Time = h.From.UTC().Format(time.RFC3339)
	doc.Track.Name = title
	for _, v := range h.Visits {
		if v.Kind == "transit" {
			continue
		}
		doc.Waypoints = append(doc.Waypoints, gpxWpt{
			Lat:  coord(v.Lat),
			Lon:  coord(v.Lon),
			Time: v.ArrivedAt.UTC().Format(time.RFC3339),
			Name: v.PlaceName,
			Desc: fmt.Sprintf("%s - %s", v.ArrivedAt.UTC().Format(time.RFC3339), v.DepartedAt.UTC().Format(time.RFC3339)),
		})
	}
	for _, seg := range splitSegments(h.Trail) {
		var ts gpxTrkseg
		for _, p := range seg {
			ts.Points = append(ts.Points, gpxTrkpt{
				Lat:  coord(p.Lat),
				Lon:  coord(p.Lon),
				Time: p.TS.UTC().Format(time.RFC3339),
			})
		}
		doc.Track.Segments = append(doc.Track.Segments, ts)
	}
	body, err := xml.MarshalIndent(doc, "", "  ")
	if err != nil {
		return nil, err
	}
	return append([]byte(xml.Header), body...), nil
}

func renderGeoJSON(h historyOut, name string) ([]byte, error) {
	features := []map[string]any{}
	lines := [][][2]float64{}
	for _, seg := range splitSegments(h.Trail) {
		line := make([][2]float64, 0, len(seg))
		for _, p := range seg {
			line = append(line, [2]float64{p.Lon, p.Lat})
		}
		lines = append(lines, line)
	}
	features = append(features, map[string]any{
		"type": "Feature",
		"properties": map[string]any{
			"name": exportTitle(name, h.From),
			"from": h.From.UTC().Format(time.RFC3339),
			"to":   h.To.UTC().Format(time.RFC3339),
		},
		"geometry": map[string]any{"type": "MultiLineString", "coordinates": lines},
	})
	for _, v := range h.Visits {
		if v.Kind == "transit" {
			continue
		}
		features = append(features, map[string]any{
			"type": "Feature",
			"properties": map[string]any{
				"name":        v.PlaceName,
				"kind":        v.Kind,
				"arrived_at":  v.ArrivedAt.UTC().Format(time.RFC3339),
				"departed_at": v.DepartedAt.UTC().Format(time.RFC3339),
			},
			"geometry": map[string]any{"type": "Point", "coordinates": [2]float64{v.Lon, v.Lat}},
		})
	}
	return json.Marshal(map[string]any{"type": "FeatureCollection", "features": features})
}
