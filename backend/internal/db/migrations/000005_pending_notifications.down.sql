-- 000005_pending_notifications.down.sql
-- Reverse of 000005_pending_notifications.up.sql.

ALTER TABLE geofence_events DROP COLUMN push_sent;

ALTER TABLE geofence_states ADD COLUMN last_transition_at TIMESTAMPTZ;
ALTER TABLE geofence_states DROP COLUMN last_notified_at;
ALTER TABLE geofence_states DROP COLUMN notified_inside;
