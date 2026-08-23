package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/whereabouts/whereabouts/backend/internal/config"
)

func TestGetConfigDefaults(t *testing.T) {
	srv := &Server{}
	req := httptest.NewRequest(http.MethodGet, "/config", nil)
	w := httptest.NewRecorder()
	srv.GetConfig(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d", w.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["tile_url"] != config.DefaultTileURL {
		t.Fatalf("tile_url=%v", body["tile_url"])
	}
	if body["satellite_tile_url"] != config.DefaultSatelliteTileURL {
		t.Fatalf("satellite_tile_url=%v", body["satellite_tile_url"])
	}
}

func TestGetConfigOverride(t *testing.T) {
	srv := &Server{
		TileURL:          "https://tiles.example.com/{z}/{x}/{y}.png?api_key=abc",
		SatelliteTileURL: "https://sat.example.com/{z}/{y}/{x}",
	}
	req := httptest.NewRequest(http.MethodGet, "/config", nil)
	w := httptest.NewRecorder()
	srv.GetConfig(w, req)
	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["tile_url"] != srv.TileURL {
		t.Fatalf("tile_url=%v", body["tile_url"])
	}
	if body["satellite_tile_url"] != srv.SatelliteTileURL {
		t.Fatalf("satellite_tile_url=%v", body["satellite_tile_url"])
	}
}
