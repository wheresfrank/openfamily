package handlers

import "testing"

func TestNormalizeInviteCode(t *testing.T) {
	if got, err := normalizeInviteCode(" 123456 "); err != nil || got != "123456" {
		t.Fatalf("normalizeInviteCode got %q, %v; want 123456, nil", got, err)
	}
	for _, input := range []string{"", "12345", "1234567", "abcdef"} {
		if _, err := normalizeInviteCode(input); err == nil {
			t.Errorf("normalizeInviteCode(%q) accepted invalid code", input)
		}
	}
}
