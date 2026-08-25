package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestLocationRequestGateQueuesCoalescesAndCoolsDown(t *testing.T) {
	gate := newLocationRequestGate()
	start := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)

	first := gate.reserve("member-1", "request-1", start)
	if first.status != "queued" || first.state.id != "request-1" {
		t.Fatalf("first decision = %#v, want queued request-1", first)
	}

	coalesced := gate.reserve("member-1", "request-2", start.Add(10*time.Second))
	if coalesced.status != "coalesced" || coalesced.state.id != "request-1" {
		t.Fatalf("second decision = %#v, want coalesced request-1", coalesced)
	}

	cooldown := gate.reserve("member-1", "request-3", start.Add(time.Minute))
	if cooldown.status != "cooldown" || cooldown.state.id != "request-1" {
		t.Fatalf("cooldown decision = %#v, want cooldown request-1", cooldown)
	}
	if cooldown.retryAfter != time.Minute {
		t.Fatalf("retryAfter = %s, want 1m", cooldown.retryAfter)
	}

	next := gate.reserve("member-1", "request-4", start.Add(2*time.Minute))
	if next.status != "queued" || next.state.id != "request-4" {
		t.Fatalf("post-cooldown decision = %#v, want queued request-4", next)
	}
}

func TestLocationRequestGateReleaseOnlyMatchingRequest(t *testing.T) {
	gate := newLocationRequestGate()
	now := time.Now()
	gate.reserve("member-1", "request-1", now)
	gate.release("member-1", "different")

	stillCoalesced := gate.reserve("member-1", "request-2", now)
	if stillCoalesced.status != "coalesced" {
		t.Fatalf("status = %q, want coalesced", stillCoalesced.status)
	}

	gate.release("member-1", "request-1")
	queued := gate.reserve("member-1", "request-3", now)
	if queued.status != "queued" || queued.state.id != "request-3" {
		t.Fatalf("decision after release = %#v, want queued request-3", queued)
	}
}

func TestRequestMemberLocationRequiresAuthentication(t *testing.T) {
	srv := &Server{}
	req := httptest.NewRequest(http.MethodPost, "/family/members/u1/location-request", nil)
	rec := httptest.NewRecorder()

	srv.RequestMemberLocation(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnauthorized)
	}
}

func TestLocationRequestCommandJSONContainsOnlyCommandMetadata(t *testing.T) {
	now := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)
	body, command, err := encodeLocationRequestCommand("abc123", now)
	if err != nil {
		t.Fatal(err)
	}
	if command.Type != "location_request" || command.ExpiresAt.Sub(command.RequestedAt) != 30*time.Second {
		t.Fatalf("unexpected command: %#v", command)
	}
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload) != 4 {
		t.Fatalf("payload keys = %#v, want command metadata only", payload)
	}
	if payload["type"] != "location_request" || payload["request_id"] != "abc123" {
		t.Fatalf("unexpected payload: %#v", payload)
	}
}
