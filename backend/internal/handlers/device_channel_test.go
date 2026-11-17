package handlers

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/wheresfrank/openfamily/backend/internal/push"
)

type recordingDispatcher struct {
	got []push.Notification
	err error
}

func (d *recordingDispatcher) Dispatch(_ context.Context, n push.Notification) error {
	d.got = append(d.got, n)
	return d.err
}

func testClient() *wsClient {
	return &wsClient{send: make(chan []byte, 4), done: make(chan struct{})}
}

func TestDeviceHubReplacesAndUnregisters(t *testing.T) {
	h := newDeviceHub()
	first, second := testClient(), testClient()
	if old := h.register("d1", first); old != nil {
		t.Fatalf("unexpected previous connection %v", old)
	}
	if old := h.register("d1", second); old != first {
		t.Fatal("registering again must return the replaced connection")
	}
	// A late cleanup from the replaced connection must not drop the new one.
	h.unregister("d1", first)
	if !h.connected("d1") {
		t.Fatal("the newer connection was dropped")
	}
	h.unregister("d1", second)
	if h.connected("d1") {
		t.Fatal("device should be disconnected")
	}
}

func TestDeviceHubSendNonBlocking(t *testing.T) {
	h := newDeviceHub()
	c := &wsClient{send: make(chan []byte, 1), done: make(chan struct{})}
	h.register("d1", c)
	if !h.send("d1", []byte("a")) {
		t.Fatal("first frame should be queued")
	}
	if h.send("d1", []byte("b")) {
		t.Fatal("a full buffer must report failure instead of blocking")
	}
	if h.send("missing", []byte("x")) {
		t.Fatal("unknown device must report failure")
	}
}

func TestNilDeviceHubIsSafe(t *testing.T) {
	var h *deviceHub
	if h.connected("d1") || h.send("d1", nil) || h.register("d1", testClient()) != nil {
		t.Fatal("nil hub must behave as empty")
	}
	h.unregister("d1", testClient())
}

func TestDeliverUsesTheWebSocketWhenConnected(t *testing.T) {
	d := &recordingDispatcher{}
	s := &Server{Push: d, deviceHub: newDeviceHub()}
	c := testClient()
	s.deviceHub.register("dev1", c)

	err := s.deliver(context.Background(), push.Notification{
		Title: "Location", Body: `{"type":"location_request"}`,
		Platform: "android", UnifiedPushEndpoint: "https://ntfy.example/topic",
		DeviceID: "dev1", Ephemeral: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(d.got) != 0 {
		t.Fatalf("push must not be used when the socket is open: %v", d.got)
	}
	select {
	case frame := <-c.send:
		if len(frame) == 0 {
			t.Fatal("empty frame")
		}
	case <-time.After(time.Second):
		t.Fatal("no frame queued")
	}
}

func TestDeliverFallsBackToPush(t *testing.T) {
	d := &recordingDispatcher{}
	s := &Server{Push: d, deviceHub: newDeviceHub()}
	n := push.Notification{
		Title: "SOS", Platform: "android", UnifiedPushEndpoint: "https://ntfy.example/topic",
		DeviceID: "offline", Ephemeral: true,
	}
	if err := s.deliver(context.Background(), n); err != nil {
		t.Fatal(err)
	}
	if len(d.got) != 1 {
		t.Fatalf("expected one push dispatch, got %d", len(d.got))
	}
}

func TestDeliverWithoutRouteIsPermanent(t *testing.T) {
	s := &Server{Push: &recordingDispatcher{}, deviceHub: newDeviceHub()}
	err := s.deliver(context.Background(), push.Notification{
		Title: "x", Platform: "android", DeviceID: "d", Ephemeral: true,
	})
	if err == nil || !push.IsPermanent(err) || !errors.Is(err, errNoRoute) {
		t.Fatalf("expected a permanent no-route error, got %v", err)
	}
}

func TestEncodePushFrame(t *testing.T) {
	created := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	got := string(encodePushFrame(7, push.Notification{Title: "T", Body: "B"}, created))
	want := `{"type":"push","id":7,"title":"T","body":"B","created_at":"2026-11-16T12:00:00Z"}`
	if got != want {
		t.Fatalf("frame mismatch:\n got %s\nwant %s", got, want)
	}
	if ephemeral := string(encodePushFrame(0, push.Notification{}, created)); ephemeral == "" ||
		containsKey(ephemeral, `"id"`) {
		t.Fatalf("ephemeral frames must not carry an id: %s", ephemeral)
	}
}

func containsKey(s, key string) bool {
	for i := 0; i+len(key) <= len(s); i++ {
		if s[i:i+len(key)] == key {
			return true
		}
	}
	return false
}
