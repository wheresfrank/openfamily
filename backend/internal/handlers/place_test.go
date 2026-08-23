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
