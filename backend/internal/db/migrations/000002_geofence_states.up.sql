-- 000002_geofence_states.up.sql
-- Geofence enter/exit state tracking and event history.

-- Current inside/outside state per (geofence, tracked user). A row is
-- upserted on every evaluated point so transitions can be detected as a
-- CHANGE in `inside` rather than firing on every point.
CREATE TABLE geofence_states (
    geofence_id        UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
    user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    inside             BOOLEAN NOT NULL,
    last_transition_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (geofence_id, user_id)
);

-- One row per detected enter/exit transition.
CREATE TABLE geofence_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    geofence_id UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    place_id    UUID REFERENCES places(id) ON DELETE SET NULL,
    event_type  TEXT NOT NULL CHECK (event_type IN ('enter', 'exit')),
    ts          TIMESTAMPTZ NOT NULL DEFAULT now(),
    location    GEOMETRY(Point, 4326)
);

CREATE INDEX idx_geofence_events_geofence ON geofence_events (geofence_id, ts DESC);
CREATE INDEX idx_geofence_events_user ON geofence_events (user_id, ts DESC);
