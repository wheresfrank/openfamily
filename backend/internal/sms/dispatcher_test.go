package sms

import (
	"context"
	"testing"
)

func TestNewNoopWhenUnset(t *testing.T) {
	d := New(Config{})
	if d.Enabled() {
		t.Fatal("expected SMS disabled")
	}
	if err := d.Send(context.Background(), "+15551234567", "hi"); err != nil {
		t.Fatalf("noop send: %v", err)
	}
}

func TestNewEnabledWhenConfigured(t *testing.T) {
	d := New(Config{AccountSID: "ACxxx", AuthToken: "tok", From: "+15550001111"})
	if !d.Enabled() {
		t.Fatal("expected SMS enabled")
	}
}
