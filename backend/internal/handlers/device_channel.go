package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
	mid "github.com/wheresfrank/openfamily/backend/internal/middleware"
	"github.com/wheresfrank/openfamily/backend/internal/push"
)

const (
	// deviceNotificationTTL is how long an undelivered notification waits for
	// its device to reconnect before it is dropped.
	deviceNotificationTTL = 24 * time.Hour

	// maxReplayPerConnect bounds the backlog sent when a device reconnects.
	maxReplayPerConnect = 50
)

// statusReplaced is the WebSocket close code sent to a device connection that
// was superseded by a newer connection from the same device.
const statusReplaced websocket.StatusCode = 4001

var errNoRoute = errors.New("device has no WebSocket connection or push target")

// deviceHub tracks the single live WebSocket of each device, so the server can
// deliver notifications and commands to a phone without an external push
// service. A device that reconnects replaces its previous connection. All
// methods are safe on a nil hub.
type deviceHub struct {
	mu    sync.Mutex
	conns map[string]*wsClient
}

func newDeviceHub() *deviceHub {
	return &deviceHub{conns: make(map[string]*wsClient)}
}

// register stores c as the device's connection and returns the connection it
// replaced, if any.
func (h *deviceHub) register(deviceID string, c *wsClient) *wsClient {
	if h == nil {
		return nil
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	old := h.conns[deviceID]
	h.conns[deviceID] = c
	return old
}

// unregister removes c, but only if it is still the device's current
// connection (a newer connection may already have replaced it).
func (h *deviceHub) unregister(deviceID string, c *wsClient) {
	if h == nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[deviceID] == c {
		delete(h.conns, deviceID)
	}
}

func (h *deviceHub) connected(deviceID string) bool {
	if h == nil {
		return false
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	_, ok := h.conns[deviceID]
	return ok
}

// send queues a frame for the device without blocking. It reports false when
// the device is not connected or its buffer is full.
func (h *deviceHub) send(deviceID string, frame []byte) bool {
	if h == nil {
		return false
	}
	h.mu.Lock()
	c := h.conns[deviceID]
	h.mu.Unlock()
	if c == nil {
		return false
	}
	select {
	case c.send <- frame:
		return true
	default:
		return false
	}
}

// devicePushFrame is what a device receives. Id is set for stored
// notifications, which the device acknowledges; ephemeral ones carry none.
type devicePushFrame struct {
	Type      string    `json:"type"`
	ID        int64     `json:"id,omitempty"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Silent    bool      `json:"silent,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

func encodePushFrame(id int64, n push.Notification, createdAt time.Time) []byte {
	frame, err := json.Marshal(devicePushFrame{
		Type:      "push",
		ID:        id,
		Title:     n.Title,
		Body:      n.Body,
		Silent:    n.Silent,
		CreatedAt: createdAt,
	})
	if err != nil {
		return nil
	}
	return frame
}

// deliver sends a notification by the best available route: the device's open
// WebSocket first, then its push token or endpoint, and finally (for a device
// that normally uses the WebSocket but is offline right now) storage until it
// reconnects. A notification without a DeviceID goes straight to push.
func (s *Server) deliver(ctx context.Context, n push.Notification) error {
	if n.DeviceID != "" && s.deviceHub.connected(n.DeviceID) {
		var id int64
		if !n.Ephemeral {
			stored, err := s.storeDeviceNotification(ctx, n)
			if err != nil {
				// Still try the live connection; it just will not be replayed.
				slog.Warn("device channel: store notification", "err", err)
			}
			id = stored
		}
		if frame := encodePushFrame(id, n, time.Now().UTC()); frame != nil &&
			s.deviceHub.send(n.DeviceID, frame) {
			return nil
		}
	}
	if n.HasPushTarget() && s.Push != nil {
		return s.Push.Dispatch(ctx, n)
	}
	if n.DeviceID != "" && !n.Ephemeral {
		capable, err := s.deviceUsesChannel(ctx, n.DeviceID)
		if err != nil {
			return err
		}
		if capable {
			_, err := s.storeDeviceNotification(ctx, n)
			return err
		}
	}
	return &push.PermanentError{Err: errNoRoute}
}

func (s *Server) storeDeviceNotification(ctx context.Context, n push.Notification) (int64, error) {
	var id int64
	err := s.Pool.QueryRow(ctx, `
		INSERT INTO device_notifications (device_id, title, body, expires_at)
		VALUES ($1, $2, $3, $4)
		RETURNING id`,
		n.DeviceID, n.Title, n.Body, time.Now().Add(deviceNotificationTTL)).Scan(&id)
	return id, err
}

// deviceUsesChannel reports whether the device has ever connected over the
// WebSocket, i.e. whether the app version supports it.
func (s *Server) deviceUsesChannel(ctx context.Context, deviceID string) (bool, error) {
	var capable bool
	err := s.Pool.QueryRow(ctx,
		`SELECT last_ws_at IS NOT NULL FROM devices WHERE id = $1`, deviceID).Scan(&capable)
	return capable, err
}

// connectedDeviceIDs returns the user's devices that currently hold an open
// WebSocket.
func (s *Server) connectedDeviceIDs(ctx context.Context, userID string) ([]string, error) {
	rows, err := s.Pool.Query(ctx, `SELECT id FROM devices WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		if s.deviceHub.connected(id) {
			ids = append(ids, id)
		}
	}
	return ids, rows.Err()
}

type pendingNotification struct {
	id        int64
	title     string
	body      string
	createdAt time.Time
}

// pendingDeviceNotifications returns undelivered, unexpired notifications for
// a device, oldest first.
func (s *Server) pendingDeviceNotifications(ctx context.Context, deviceID string) ([]pendingNotification, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT id, title, body, created_at
		FROM device_notifications
		WHERE device_id = $1 AND delivered_at IS NULL AND expires_at > now()
		ORDER BY id
		LIMIT $2`, deviceID, maxReplayPerConnect)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []pendingNotification
	for rows.Next() {
		var p pendingNotification
		if err := rows.Scan(&p.id, &p.title, &p.body, &p.createdAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// DeviceStream serves GET /ws/device: one authenticated WebSocket per device
// that carries notifications and commands to the phone, replacing an external
// push service. The device authenticates with its ingest key (X-Device-Key),
// which does not expire, so the connection can be re-established from the
// background service at any time.
func (s *Server) DeviceStream(w http.ResponseWriter, r *http.Request) {
	deviceID, ownerID, err := mid.AuthenticateDeviceKey(r.Context(), s.Pool, r.Header.Get(mid.DeviceKeyHeader))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		OriginPatterns: s.wsOriginPatterns(),
	})
	if err != nil {
		slog.Warn("device websocket accept failed", "err", err)
		return
	}

	ctx := r.Context()
	conn.SetReadLimit(4096)
	c := &wsClient{
		conn:   conn,
		send:   make(chan []byte, clientSendBuffer),
		done:   make(chan struct{}),
		userID: ownerID,
	}
	if old := s.deviceHub.register(deviceID, c); old != nil {
		// Tell the replaced connection why, so it backs off instead of
		// immediately reconnecting and evicting this one in turn.
		old.closeWith(statusReplaced, "replaced by a newer connection")
	}
	defer func() {
		s.deviceHub.unregister(deviceID, c)
		c.close()
	}()

	if _, err := s.Pool.Exec(ctx,
		`UPDATE devices SET last_ws_at = now(), last_seen = now() WHERE id = $1`, deviceID); err != nil {
		slog.Warn("device channel: mark connected", "err", err)
	}
	// Opportunistic cleanup of old rows for this device.
	if _, err := s.Pool.Exec(ctx, `
		DELETE FROM device_notifications
		WHERE device_id = $1 AND (
			(delivered_at IS NOT NULL AND delivered_at < now() - interval '1 day')
			OR expires_at < now() - interval '1 day')`, deviceID); err != nil {
		slog.Warn("device channel: cleanup", "err", err)
	}

	hello, err := json.Marshal(map[string]any{"type": "hello", "device_id": deviceID, "ts": time.Now().UTC()})
	if err != nil {
		return
	}
	if err := conn.Write(ctx, websocket.MessageText, hello); err != nil {
		return
	}

	// Replay what was raised while the device was offline. Written directly
	// (before writeLoop starts) so there is a single writer at any time.
	pending, err := s.pendingDeviceNotifications(ctx, deviceID)
	if err != nil {
		slog.Warn("device channel: load pending", "err", err)
	}
	for _, p := range pending {
		frame := encodePushFrame(p.id, push.Notification{Title: p.title, Body: p.body}, p.createdAt)
		if frame == nil {
			continue
		}
		if err := conn.Write(ctx, websocket.MessageText, frame); err != nil {
			return
		}
	}

	go c.writeLoop(ctx)

	for {
		msgType, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		if msgType != websocket.MessageText {
			continue
		}
		var frame struct {
			Type string `json:"type"`
			ID   int64  `json:"id"`
		}
		if err := json.Unmarshal(data, &frame); err != nil {
			continue
		}
		switch frame.Type {
		case "ping":
			if pong, err := json.Marshal(map[string]string{"type": "pong"}); err == nil {
				select {
				case c.send <- pong:
				default:
				}
			}
		case "ack":
			if frame.ID > 0 {
				if _, err := s.Pool.Exec(ctx, `
					UPDATE device_notifications SET delivered_at = now()
					WHERE id = $1 AND device_id = $2 AND delivered_at IS NULL`,
					frame.ID, deviceID); err != nil {
					slog.Warn("device channel: ack", "err", err)
				}
			}
		}
	}
}
