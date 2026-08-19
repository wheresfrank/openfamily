-- 000008_last_seen_ts.up.sql
-- Track the timestamp of the last location point applied to each geofence
-- state, so a stale point re-evaluated by the reconcile worker (after a
-- concurrent ingest advanced the state with a newer point) is skipped instead
-- of producing a spurious transition.

ALTER TABLE geofence_states ADD COLUMN last_seen_ts TIMESTAMPTZ;
