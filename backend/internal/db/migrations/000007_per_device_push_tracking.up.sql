-- 000007_per_device_push_tracking.up.sql
-- Per-device push delivery tracking and event creation time.

-- created_at: when the event row was inserted (distinct from ts, the
-- transition time). Used to avoid re-dispatching a just-created event whose
-- initial dispatch is still in flight.
ALTER TABLE geofence_events ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Per-device delivery tracking: replaces the event-level push_sent/push_attempts
-- so a single failing device does not cause duplicate pushes to healthy members.
CREATE TABLE geofence_event_devices (
    event_id      UUID NOT NULL REFERENCES geofence_events(id) ON DELETE CASCADE,
    device_id     UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    push_sent     BOOLEAN NOT NULL DEFAULT FALSE,
    push_attempts INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (event_id, device_id)
);

CREATE INDEX idx_geofence_event_devices_unsent ON geofence_event_devices (push_sent, push_attempts);

-- Event-level push tracking is superseded by per-device tracking.
ALTER TABLE geofence_events DROP COLUMN push_sent;
ALTER TABLE geofence_events DROP COLUMN push_attempts;
