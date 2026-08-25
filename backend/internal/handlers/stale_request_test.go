package handlers

import (
	"testing"
	"time"
)

// The watchdog must allow one refresh per member per cooldown, then block
// until the cooldown elapses, with entries prunable so the map cannot grow
// without bound on a long-running server.
func TestStaleRequestGateCooldown(t *testing.T) {
	gate := newStaleRequestGate(staleRequestCooldown)
	now := time.Now().UTC()

	if !gate.reserve("member-1", now) {
		t.Fatal("first reserve for a member should pass")
	}
	if gate.reserve("member-1", now.Add(time.Second)) {
		t.Fatal("second reserve within the cooldown should be rejected")
	}
	if !gate.reserve("member-2", now) {
		t.Fatal("a different member should not be affected by member-1's cooldown")
	}

	after := now.Add(staleRequestCooldown + time.Minute)
	if !gate.reserve("member-1", after) {
		t.Fatal("reserve after the cooldown should pass")
	}
	if len(gate.lastSent) != 2 {
		t.Fatalf("expected the expired entry to be replaced in place, got %d live entries", len(gate.lastSent))
	}
}
