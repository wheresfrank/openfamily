package handlers

import (
	"encoding/json"
	"encoding/xml"
	"strings"
	"testing"
	"time"
)

func sampleHistory() historyOut {
	t0 := time.Date(2026, 11, 1, 8, 0, 0, 0, time.UTC)
	return historyOut{
		From: t0,
		To:   t0.Add(3 * time.Hour),
		Trail: []trailPoint{
			{Lat: 10.5, Lon: -66.9, TS: t0},
			{Lat: 10.51, Lon: -66.91, TS: t0.Add(time.Minute)},
			{Lat: 10.6, Lon: -66.95, TS: t0.Add(2 * time.Hour)},
		},
		Visits: []historyVisit{
			{ArrivedAt: t0, DepartedAt: t0.Add(time.Hour), Lat: 10.5, Lon: -66.9, PlaceName: "Home <&>", Kind: "place"},
			{ArrivedAt: t0.Add(time.Hour), DepartedAt: t0.Add(2 * time.Hour), Lat: 10.55, Lon: -66.92, PlaceName: "Driving", Kind: "transit"},
		},
	}
}

func TestSplitSegmentsOnGap(t *testing.T) {
	segs := splitSegments(sampleHistory().Trail)
	if len(segs) != 2 || len(segs[0]) != 2 || len(segs[1]) != 1 {
		t.Fatalf("unexpected segments: %v", segs)
	}
}

func TestRenderGPX(t *testing.T) {
	body, err := renderGPX(sampleHistory(), "Ana")
	if err != nil {
		t.Fatal(err)
	}
	var doc gpxDoc
	if err := xml.Unmarshal(body, &doc); err != nil {
		t.Fatalf("invalid xml: %v\n%s", err, body)
	}
	if len(doc.Track.Segments) != 2 || len(doc.Waypoints) != 1 {
		t.Fatalf("segments=%d waypoints=%d", len(doc.Track.Segments), len(doc.Waypoints))
	}
	if doc.Waypoints[0].Name != "Home <&>" {
		t.Fatalf("waypoint name not escaped/round-tripped: %q", doc.Waypoints[0].Name)
	}
	if !strings.Contains(string(body), `lat="10.500000"`) {
		t.Fatalf("expected fixed-point coordinates:\n%s", body)
	}
}

func TestRenderGeoJSON(t *testing.T) {
	body, err := renderGeoJSON(sampleHistory(), "Ana")
	if err != nil {
		t.Fatal(err)
	}
	var fc struct {
		Type     string `json:"type"`
		Features []struct {
			Geometry struct {
				Type string `json:"type"`
			} `json:"geometry"`
		} `json:"features"`
	}
	if err := json.Unmarshal(body, &fc); err != nil {
		t.Fatal(err)
	}
	if fc.Type != "FeatureCollection" || len(fc.Features) != 2 ||
		fc.Features[0].Geometry.Type != "MultiLineString" || fc.Features[1].Geometry.Type != "Point" {
		t.Fatalf("unexpected geojson: %s", body)
	}
}
