package apkrelease

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
)

func TestSyncDownloadsAndCaches(t *testing.T) {
	dir := t.TempDir()
	var assetHits atomic.Int32

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer test-token" {
			t.Errorf("missing bearer token: %q", got)
		}
		switch {
		case r.URL.Path == "/repos/acme/whereabouts/releases/latest":
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(release{
				TagName: "apk-7",
				Assets: []asset{{
					ID:   42,
					Name: "whereabouts-release.apk",
					URL:  "http://" + r.Host + "/assets/42",
					Size: 4,
				}},
			})
		case r.URL.Path == "/assets/42":
			assetHits.Add(1)
			w.Header().Set("Content-Type", "application/vnd.android.package-archive")
			_, _ = io.WriteString(w, "apk!")
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	opts := Options{
		Repo:    "acme/whereabouts",
		Token:   "test-token",
		DestDir: dir,
		API:     srv.URL,
		Client:  srv.Client(),
	}

	path, err := Sync(context.Background(), opts)
	if err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "apk!" {
		t.Fatalf("cached APK = %q", got)
	}

	path2, err := Sync(context.Background(), opts)
	if err != nil {
		t.Fatal(err)
	}
	if path2 != path {
		t.Fatalf("second sync path %s != %s", path2, path)
	}
	if assetHits.Load() != 1 {
		t.Fatalf("expected one asset download, got %d", assetHits.Load())
	}
}

func TestSyncRedownloadsWhenAssetChanges(t *testing.T) {
	dir := t.TempDir()
	var currentID atomic.Int64
	currentID.Store(1)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := currentID.Load()
		switch {
		case strings.HasSuffix(r.URL.Path, "/releases/latest"):
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(release{
				TagName: "apk-n",
				Assets: []asset{{
					ID:   id,
					Name: "whereabouts-release.apk",
					URL:  "http://" + r.Host + "/assets/" + strconv.FormatInt(id, 10),
				}},
			})
		case strings.HasPrefix(r.URL.Path, "/assets/"):
			w.Header().Set("Content-Type", "application/octet-stream")
			_, _ = io.WriteString(w, "apk-"+strconv.FormatInt(id, 10))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	opts := Options{Repo: "acme/app", Token: "t", DestDir: dir, API: srv.URL, Client: srv.Client()}
	if _, err := Sync(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	currentID.Store(2)
	path, err := Sync(context.Background(), opts)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(path)
	if string(got) != "apk-2" {
		t.Fatalf("expected refreshed APK, got %q", got)
	}
}

func TestSyncPrivateRepoWithoutToken(t *testing.T) {
	dir := t.TempDir()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "not found", http.StatusNotFound)
	}))
	defer srv.Close()

	_, err := Sync(context.Background(), Options{Repo: "acme/app", DestDir: dir, API: srv.URL, Client: srv.Client()})
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "APK_GITHUB_TOKEN") {
		t.Fatalf("error should mention the token: %v", err)
	}
}

func TestPickAPKAsset(t *testing.T) {
	got, err := pickAPKAsset([]asset{
		{Name: "notes.txt", ID: 1},
		{Name: "whereabouts-release.apk", ID: 2},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.ID != 2 {
		t.Fatalf("picked %+v", got)
	}
	if _, err := pickAPKAsset([]asset{{Name: "notes.txt"}}); err == nil {
		t.Fatal("expected ErrNotFound")
	}
}

func TestParseRepo(t *testing.T) {
	owner, name, err := parseRepo("  wheresfrank/whereabouts ")
	if err != nil || owner != "wheresfrank" || name != "whereabouts" {
		t.Fatalf("parseRepo = %s/%s (%v)", owner, name, err)
	}
	if _, _, err := parseRepo("nopath"); err == nil {
		t.Fatal("expected error")
	}
}

func TestCacheFresh(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, cachedName)
	if cacheFresh(dir, dest, 1) {
		t.Fatal("missing file should not be fresh")
	}
	if err := os.WriteFile(dest, []byte("apk"), 0o644); err != nil {
		t.Fatal(err)
	}
	if cacheFresh(dir, dest, 1) {
		t.Fatal("missing meta should not be fresh")
	}
	if err := writeMeta(dir, cacheMeta{AssetID: 1}); err != nil {
		t.Fatal(err)
	}
	if !cacheFresh(dir, dest, 1) {
		t.Fatal("matching asset should be fresh")
	}
	if cacheFresh(dir, dest, 2) {
		t.Fatal("different asset should not be fresh")
	}
}
