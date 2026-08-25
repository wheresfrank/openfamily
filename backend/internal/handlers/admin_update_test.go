package handlers

import "testing"

func TestRefsDifferTreatsDevelopmentBuildAsActionable(t *testing.T) {
	if !refsDiffer("dev", "1d3c45d") {
		t.Fatal("a development build must not be reported as up to date with a released commit")
	}
	if refsDiffer("1d3c45d", "1d3c45d") {
		t.Fatal("matching refs should be up to date")
	}
	if refsDiffer("dev", "") {
		t.Fatal("a missing latest ref is not an available update")
	}
}
