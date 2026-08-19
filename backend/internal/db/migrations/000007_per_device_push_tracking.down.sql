-- 000007_per_device_push_tracking.down.sql
-- Reverse of 000007_per_device_push_tracking.up.sql.

ALTER TABLE geofence_events ADD COLUMN push_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE geofence_events ADD COLUMN push_sent BOOLEAN NOT NULL DEFAULT FALSE;

DROP TABLE geofence_event_devices;

ALTER TABLE geofence_events DROP COLUMN created_at;
