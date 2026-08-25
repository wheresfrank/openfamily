package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRefsDifferRequiresKnownVersions(t *testing.T) {
	if refsDiffer("dev", "1d3c45d") || refsDiffer("", "1d3c45d") {
		t.Fatal("an unknown running version must not be reported as an available update")
	}
	if !refsDiffer("abc1234", "1d3c45d") {
		t.Fatal("different known refs should report an available update")
	}
	if refsDiffer("1d3c45d", "1d3c45d") {
		t.Fatal("matching refs should be up to date")
	}
	if refsDiffer("abc1234", "") {
		t.Fatal("a missing latest ref is not an available update")
	}
}

func TestUpdaterStatusReturnsCurrentRefWhenApplyIsDisabled(t *testing.T) {
	updater := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"busy":false,"can_apply":false,"current_ref":"12e49c6","job":{"status":"idle"}}`))
	}))
	defer updater.Close()

	s := &Server{UpdaterURL: updater.URL}
	_, busy, canApply, currentRef, err := s.updaterStatus(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	if busy || canApply || currentRef != "12e49c6" {
		t.Fatalf("unexpected updater status: busy=%v canApply=%v currentRef=%q", busy, canApply, currentRef)
	}
}
