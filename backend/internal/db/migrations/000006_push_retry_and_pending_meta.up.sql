-- 000006_push_retry_and_pending_meta.up.sql
-- Track push redispatch attempts (dead-letter after N) and store the pending
-- transition's timestamp/location so a debounced transition fired later keeps
-- its original time and location.

-- push_attempts: how many times the reconcile worker has re-dispatched this
-- event's push. Once it reaches the cap the event is dead-lettered (no longer
-- re-dispatched), so a permanently-failing token does not retry forever.
ALTER TABLE geofence_events ADD COLUMN push_attempts INTEGER NOT NULL DEFAULT 0;

-- pending_ts/pending_lon/pending_lat: the timestamp and location of a
-- debounce-suppressed (pending) transition, used when the reconcile worker
-- fires it so the event keeps its original time and location.
ALTER TABLE geofence_states ADD COLUMN pending_ts TIMESTAMPTZ;
ALTER TABLE geofence_states ADD COLUMN pending_lon DOUBLE PRECISION;
ALTER TABLE geofence_states ADD COLUMN pending_lat DOUBLE PRECISION;
