package handlers

import (
	"strings"
	"testing"
)

func TestNormalizeProfileName(t *testing.T) {
	got, err := normalizeProfileName("  Frank  ")
	if err != nil {
		t.Fatalf("normalizeProfileName returned error: %v", err)
	}
	if got != "Frank" {
		t.Fatalf("got %q, want %q", got, "Frank")
	}

	for _, input := range []string{"", "   ", strings.Repeat("x", 121)} {
		if _, err := normalizeProfileName(input); err == nil {
			t.Errorf("normalizeProfileName(%q) accepted invalid input", input)
		}
	}
}
