-- 000008_last_seen_ts.down.sql
-- Reverse of 000008_last_seen_ts.up.sql.

ALTER TABLE geofence_states DROP COLUMN last_seen_ts;
