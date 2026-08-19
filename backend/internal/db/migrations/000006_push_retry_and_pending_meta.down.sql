-- 000006_push_retry_and_pending_meta.down.sql
-- Reverse of 000006_push_retry_and_pending_meta.up.sql.

ALTER TABLE geofence_states DROP COLUMN pending_lat;
ALTER TABLE geofence_states DROP COLUMN pending_lon;
ALTER TABLE geofence_states DROP COLUMN pending_ts;

ALTER TABLE geofence_events DROP COLUMN push_attempts;
