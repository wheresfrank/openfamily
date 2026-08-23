package config

import (
	"testing"
)

func TestLoadTileDefaults(t *testing.T) {
	t.Setenv("TILE_URL", "")
	t.Setenv("SATELLITE_TILE_URL", "")
	cfg := Load()
	if cfg.TileURL != DefaultTileURL {
		t.Fatalf("tile=%q", cfg.TileURL)
	}
	if cfg.SatelliteTileURL != DefaultSatelliteTileURL {
		t.Fatalf("satellite=%q", cfg.SatelliteTileURL)
	}
}

func TestLoadTileOverride(t *testing.T) {
	t.Setenv("TILE_URL", "https://tiles.example.com/{z}/{x}/{y}.png?api_key=abc")
	t.Setenv("SATELLITE_TILE_URL", "https://sat.example.com/{z}/{y}/{x}")
	cfg := Load()
	if cfg.TileURL != "https://tiles.example.com/{z}/{x}/{y}.png?api_key=abc" {
		t.Fatalf("tile=%q", cfg.TileURL)
	}
	if cfg.SatelliteTileURL != "https://sat.example.com/{z}/{y}/{x}" {
		t.Fatalf("satellite=%q", cfg.SatelliteTileURL)
	}
}
