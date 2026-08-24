package sms

import "testing"

func TestMergeUsesEnvWhenNoRow(t *testing.T) {
	env := Settings{AccountSID: "ACenv", AuthToken: "envtok", From: "+15550001111", PublicBaseURL: "https://env.example"}
	got := Merge(env, Settings{AccountSID: "ACdb"}, false)
	if got != env {
		t.Fatalf("got %+v, want env", got)
	}
}

func TestMergePrefersNonEmptyStoredFields(t *testing.T) {
	env := Settings{AccountSID: "ACenv", AuthToken: "envtok", From: "+15550001111", PublicBaseURL: "https://env.example"}
	stored := Settings{AccountSID: "ACdb", From: "+15550002222"}
	got := Merge(env, stored, true)
	if got.AccountSID != "ACdb" || got.From != "+15550002222" {
		t.Fatalf("stored fields not applied: %+v", got)
	}
	if got.AuthToken != "envtok" || got.PublicBaseURL != "https://env.example" {
		t.Fatalf("empty stored fields should keep env: %+v", got)
	}
}

func TestSettingsEnabled(t *testing.T) {
	if (Settings{}).Enabled() {
		t.Fatal("empty settings should be disabled")
	}
	if !(Settings{AccountSID: "AC", AuthToken: "tok", From: "+1"}).Enabled() {
		t.Fatal("complete settings should be enabled")
	}
}

func TestNormalizePublicBaseURL(t *testing.T) {
	got, err := NormalizePublicBaseURL(" https://openfamily.example.com/ ")
	if err != nil || got != "https://openfamily.example.com" {
		t.Fatalf("got %q err=%v", got, err)
	}
	if _, err := NormalizePublicBaseURL("http://insecure.example"); err == nil {
		t.Fatal("expected error for http")
	}
	got, err = NormalizePublicBaseURL("  ")
	if err != nil || got != "" {
		t.Fatalf("empty should clear: %q %v", got, err)
	}
}
