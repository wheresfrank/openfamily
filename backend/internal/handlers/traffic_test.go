package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/wheresfrank/openfamily/backend/internal/auth"
	"github.com/wheresfrank/openfamily/backend/internal/middleware"
)

func TestValidTileCoords(t *testing.T) {
	cases := []struct {
		z, x, y int
		want    bool
	}{
		{0, 0, 0, true},
		{0, 1, 0, false},
		{3, 7, 7, true},
		{3, 8, 0, false},
		{3, 0, 8, false},
		{22, 4194303, 4194303, true},
		{23, 0, 0, false},
		{-1, 0, 0, false},
		{5, -1, 0, false},
	}
	for _, c := range cases {
		if got := validTileCoords(c.z, c.x, c.y); got != c.want {
			t.Errorf("validTileCoords(%d,%d,%d) = %v, want %v", c.z, c.x, c.y, got, c.want)
		}
	}
}

func TestTrafficTileRequestURL(t *testing.T) {
	got := trafficTileRequestURL("https://upstream.example/flow/relative", 12, 2044, 1360, 256, "SECRET")
	want := "https://upstream.example/flow/relative/12/2044/1360.png?tileSize=256&key=SECRET"
	if got != want {
		t.Fatalf("got %s want %s", got, want)
	}
	got = trafficTileRequestURL("https://upstream.example/flow/relative", 11, 1022, 680, 512, "SECRET")
	want = "https://upstream.example/flow/relative/11/1022/680.png?tileSize=512&key=SECRET"
	if got != want {
		t.Fatalf("got %s want %s", got, want)
	}
}

func TestParseTileSize(t *testing.T) {
	for raw, want := range map[string]int{"": 256, "256": 256, "512": 512} {
		if got, ok := parseTileSize(raw); !ok || got != want {
			t.Errorf("parseTileSize(%q) = %d, %v", raw, got, ok)
		}
	}
	for _, bad := range []string{"128", "1024", "abc", "-1", "512&key=x"} {
		if _, ok := parseTileSize(bad); ok {
			t.Errorf("parseTileSize(%q) should be rejected", bad)
		}
	}
}

func trafficRequest(srv *Server, path string) *httptest.ResponseRecorder {
	r := chi.NewRouter()
	r.Get("/traffic/tiles/{z}/{x}/{y}", srv.GetTrafficTile)
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req = req.WithContext(middleware.ContextWithClaims(req.Context(), &auth.Claims{UserID: "u1"}))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestTrafficTileNotConfigured(t *testing.T) {
	w := trafficRequest(&Server{}, "/traffic/tiles/3/1/1")
	if w.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", w.Code)
	}
}

func TestTrafficTileRejectsBadCoordinates(t *testing.T) {
	srv := &Server{TomTomAPIKey: "k"}
	for _, path := range []string{
		"/traffic/tiles/3/9/1", "/traffic/tiles/30/0/0", "/traffic/tiles/a/0/0",
		"/traffic/tiles/3/1/1?size=1024",
	} {
		if w := trafficRequest(srv, path); w.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", path, w.Code)
		}
	}
}

func TestTrafficTileProxiesWithoutLeakingTheKey(t *testing.T) {
	var gotPath, gotKey, gotSize string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotKey = r.URL.Query().Get("key")
		gotSize = r.URL.Query().Get("tileSize")
		w.Header().Set("Content-Type", "image/png")
		_, _ = w.Write([]byte("PNGDATA"))
	}))
	defer upstream.Close()

	srv := &Server{TomTomAPIKey: "SECRET", trafficBase: upstream.URL + "/flow/relative"}
	w := trafficRequest(srv, "/traffic/tiles/3/4/5?size=512")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d", w.Code)
	}
	if gotPath != "/flow/relative/3/4/5.png" || gotKey != "SECRET" || gotSize != "512" {
		t.Fatalf("upstream got path=%q key=%q size=%q", gotPath, gotKey, gotSize)
	}
	if w.Body.String() != "PNGDATA" || w.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("unexpected body or type: %q %q", w.Body.String(), w.Header().Get("Content-Type"))
	}
	if cc := w.Header().Get("Cache-Control"); !strings.Contains(cc, "no-store") {
		t.Fatalf("tiles must not be stored, got Cache-Control %q", cc)
	}
	if strings.Contains(w.Body.String()+w.Header().Get("Location"), "SECRET") {
		t.Fatal("the API key must never be returned to the client")
	}
}

func TestTrafficTileProviderErrorIsAGatewayError(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "forbidden SECRET", http.StatusForbidden)
	}))
	defer upstream.Close()
	srv := &Server{TomTomAPIKey: "SECRET", trafficBase: upstream.URL}
	w := trafficRequest(srv, "/traffic/tiles/1/0/0")
	if w.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", w.Code)
	}
	if strings.Contains(w.Body.String(), "SECRET") {
		t.Fatal("upstream error text must not reach the client")
	}
}

func TestConfigAdvertisesTraffic(t *testing.T) {
	for _, tc := range []struct {
		key  string
		want bool
	}{{"", false}, {"abc", true}} {
		srv := &Server{TomTomAPIKey: tc.key}
		w := httptest.NewRecorder()
		srv.GetConfig(w, httptest.NewRequest(http.MethodGet, "/config", nil))
		var body map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if body["traffic_enabled"] != tc.want {
			t.Errorf("key %q: traffic_enabled = %v, want %v", tc.key, body["traffic_enabled"], tc.want)
		}
		if strings.Contains(w.Body.String(), "abc") {
			t.Error("GET /config must not expose the key")
		}
	}
}
