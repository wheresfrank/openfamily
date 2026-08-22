package sms

import "testing"

func TestNormalizeE164(t *testing.T) {
	got, err := NormalizeE164(" +1 (555) 123-4567 ")
	if err != nil {
		t.Fatalf("err=%v", err)
	}
	if got != "+15551234567" {
		t.Fatalf("got %q", got)
	}

	cleared, err := NormalizeE164("   ")
	if err != nil || cleared != "" {
		t.Fatalf("empty: got %q err=%v", cleared, err)
	}

	if _, err := NormalizeE164("5551234567"); err == nil {
		t.Fatal("expected error for missing +")
	}
	if _, err := NormalizeE164("not-a-phone"); err == nil {
		t.Fatal("expected error for junk")
	}
}
