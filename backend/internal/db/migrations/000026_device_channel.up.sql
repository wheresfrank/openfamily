-- Notifications delivered to a device over its authenticated WebSocket
-- (GET /ws/device) instead of an external push service. A row stays pending
-- until the device acknowledges it, so alerts raised while the device is
-- offline are replayed when it reconnects and are never shown twice.
ALTER TABLE devices ADD COLUMN last_ws_at TIMESTAMPTZ;

CREATE TABLE device_notifications (
    id           BIGSERIAL PRIMARY KEY,
    device_id    UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    title        TEXT NOT NULL DEFAULT '',
    body         TEXT NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ NOT NULL,
    delivered_at TIMESTAMPTZ
);

CREATE INDEX idx_device_notifications_pending
    ON device_notifications (device_id, id)
    WHERE delivered_at IS NULL;
