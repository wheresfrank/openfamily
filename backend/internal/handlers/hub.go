package handlers

import (
	"context"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// clientSendBuffer is the number of outbound frames buffered per connection
// before the client is considered too slow and dropped.
const clientSendBuffer = 64

// wsClient is a single connected WebSocket client. Outbound frames are queued
// on send and written by a dedicated goroutine so a slow consumer cannot block
// location ingest.
type wsClient struct {
	conn *websocket.Conn
	send chan []byte
	done chan struct{}
	once sync.Once
}

// close signals the writer goroutine to stop and closes the connection. It is
// idempotent so both the read loop and a slow-client drop can call it.
func (c *wsClient) close() {
	c.once.Do(func() {
		close(c.done)
		_ = c.conn.CloseNow()
	})
}

// writeLoop drains the send channel and writes frames to the connection. It
// exits when the client is closed or a write fails.
//
// It also runs the heartbeat: a periodic ping detects a half-open connection
// (phone killed / signal lost with no FIN), which would otherwise leave the
// read loop blocked forever and hold a hub slot + send buffer indefinitely. A
// dead peer never answers the ping, so Ping times out and we close the
// connection, which unblocks the read loop and triggers the deferred
// unregister. Ping is a write, so it lives here alongside Write to respect
// coder/websocket's single-writer rule.
func (c *wsClient) writeLoop(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case msg := <-c.send:
			if err := c.conn.Write(ctx, websocket.MessageText, msg); err != nil {
				c.close()
				return
			}
		case <-ticker.C:
			pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
			err := c.conn.Ping(pingCtx)
			cancel()
			if err != nil {
				c.close()
				return
			}
		case <-c.done:
			return
		}
	}
}

// hub tracks connected WebSocket clients per family.
type hub struct {
	mu       sync.Mutex
	families map[string]map[*wsClient]struct{}
}

func newHub() *hub {
	return &hub{families: make(map[string]map[*wsClient]struct{})}
}

// register adds a client to a family.
func (h *hub) register(familyID string, c *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	m := h.families[familyID]
	if m == nil {
		m = make(map[*wsClient]struct{})
		h.families[familyID] = m
	}
	m[c] = struct{}{}
}

// unregister removes a client from a family.
func (h *hub) unregister(familyID string, c *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	m := h.families[familyID]
	if m == nil {
		return
	}
	delete(m, c)
	if len(m) == 0 {
		delete(h.families, familyID)
	}
}

// hasAny reports whether any client is connected to any family. It lets
// callers skip a database lookup when there is nobody to notify.
func (h *hub) hasAny() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.families) > 0
}

// broadcast enqueues msg to every client in the family without blocking. A
// client whose send buffer is full is dropped and unregistered so a slow
// consumer cannot stall location ingest.
func (h *hub) broadcast(familyID string, msg []byte) {
	h.mu.Lock()
	m := h.families[familyID]
	clients := make([]*wsClient, 0, len(m))
	for c := range m {
		clients = append(clients, c)
	}
	h.mu.Unlock()

	for _, c := range clients {
		select {
		case c.send <- msg:
		default:
			h.unregister(familyID, c)
			c.close()
		}
	}
}
