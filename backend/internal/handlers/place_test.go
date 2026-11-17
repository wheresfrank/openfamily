package handlers

import "testing"

func TestNullableUUID(t *testing.T) {
	if got := nullableUUID(""); got != nil {
		t.Fatalf("empty id should bind as NULL, got %#v", got)
	}
	const id = "11111111-1111-1111-1111-111111111111"
	got := nullableUUID(id)
	s, ok := got.(string)
	if !ok || s != id {
		t.Fatalf("got %#v, want %q", got, id)
	}
}

func TestValidPlaceTypeCoversEveryIcon(t *testing.T) {
	for _, ok := range []string{
		"home", "school", "work", "gym", "family", "friend",
		"store", "health", "park", "food", "worship", "custom",
	} {
		if !validPlaceType(ok) {
			t.Errorf("validPlaceType(%q) = false, want true", ok)
		}
	}
	for _, bad := range []string{"", "Home", "airport", "custom ", "drop table"} {
		if validPlaceType(bad) {
			t.Errorf("validPlaceType(%q) = true, want false", bad)
		}
	}
}
