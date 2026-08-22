package sms

import (
	"testing"
	"time"
)

func TestLimiterAllow(t *testing.T) {
	l := NewLimiter()
	if !l.Allow("u1", 1, time.Minute) {
		t.Fatal("first hit should allow")
	}
	if l.Allow("u1", 1, time.Minute) {
		t.Fatal("second hit in window should deny")
	}
	if !l.Allow("u2", 1, time.Minute) {
		t.Fatal("other key should allow")
	}
}

func TestLimiterWindowExpiry(t *testing.T) {
	l := NewLimiter()
	if !l.Allow("u1", 1, 20*time.Millisecond) {
		t.Fatal("first hit should allow")
	}
	time.Sleep(30 * time.Millisecond)
	if !l.Allow("u1", 1, 20*time.Millisecond) {
		t.Fatal("hit after window should allow")
	}
}
