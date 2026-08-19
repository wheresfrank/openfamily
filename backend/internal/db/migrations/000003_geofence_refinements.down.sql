-- 000003_geofence_refinements.down.sql
-- Reverse of 000003_geofence_refinements.up.sql.

DROP INDEX IF EXISTS idx_geofences_place_family;
DROP INDEX IF EXISTS idx_geofences_place_user;

UPDATE geofence_states SET last_transition_at = now() WHERE last_transition_at IS NULL;
ALTER TABLE geofence_states ALTER COLUMN last_transition_at SET DEFAULT now();
ALTER TABLE geofence_states ALTER COLUMN last_transition_at SET NOT NULL;
