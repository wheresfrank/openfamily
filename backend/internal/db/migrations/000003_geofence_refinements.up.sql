-- 000003_geofence_refinements.up.sql
-- Refinements for geofence state tracking and uniqueness.

-- last_transition_at becomes nullable with no default: NULL means "no
-- transition fired yet" (first observation), so the debounce window is not
-- polluted by a first observation that never fired a transition, and future
-- inserts do not get a spurious now() timestamp.
ALTER TABLE geofence_states ALTER COLUMN last_transition_at DROP NOT NULL;
ALTER TABLE geofence_states ALTER COLUMN last_transition_at DROP DEFAULT;

-- The same place+user (or the same place as a family-wide geofence) cannot be
-- linked twice.
CREATE UNIQUE INDEX idx_geofences_place_user ON geofences (place_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX idx_geofences_place_family ON geofences (place_id) WHERE user_id IS NULL;
