package serverupdate

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestLatestCommit(t *testing.T) {
	var calls int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		switch {
		case r.URL.Path == "/repos/octo/repo":
			_, _ = w.Write([]byte(`{"default_branch":"trunk"}`))
		case r.URL.Path == "/repos/octo/repo/commits":
			if got := r.URL.Query().Get("sha"); got != "trunk" {
				t.Errorf("commits sha = %q, want trunk", got)
			}
			if r.Header.Get("Authorization") != "Bearer tok" {
				t.Errorf("missing bearer token")
			}
			_, _ = w.Write([]byte(`[{"sha":"abcdef1234567890"}]`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	c := &Checker{Repo: "octo/repo", Token: "tok", API: srv.URL}
	got, err := c.LatestCommit(context.Background())
	if err != nil {
		t.Fatalf("LatestCommit: %v", err)
	}
	if got != "abcdef1" {
		t.Errorf("short sha = %q, want abcdef1", got)
	}

	// Second call must hit the 10-minute cache, not GitHub.
	if _, err := c.LatestCommit(context.Background()); err != nil {
		t.Fatalf("cached LatestCommit: %v", err)
	}
	if calls != 2 { // one repo lookup + one commits lookup
		t.Errorf("github calls = %d, want 2", calls)
	}
}

func TestLatestCommitUnconfigured(t *testing.T) {
	var c *Checker
	if _, err := c.LatestCommit(context.Background()); err == nil {
		t.Fatal("expected error for unconfigured checker")
	}
}
