-- 000001_init.up.sql
-- Core schema for OpenFamily: families, users, devices, places, geofences,
-- and a TimescaleDB hypertable for location history.

-- Extensions (PostGIS for geometry, TimescaleDB for time-series).
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Families group users, devices, places, and geofences.
CREATE TABLE families (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL,
    settings   JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Users are accounts; each belongs to at most one family.
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id     UUID REFERENCES families(id) ON DELETE SET NULL,
    email         TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'member'
                  CHECK (role IN ('admin', 'member', 'child')),
    password_hash TEXT NOT NULL,
    totp_secret   TEXT,
    totp_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_family ON users (family_id);

-- Devices are phones/tablets that report location for a user.
CREATE TABLE devices (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform             TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    name                 TEXT,
    push_token           TEXT,
    unifiedpush_endpoint TEXT,
    last_seen            TIMESTAMPTZ,
    app_version          TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_devices_user ON devices (user_id);

-- Places are named points of interest with an optional radius.
CREATE TABLE places (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id     UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    type          TEXT NOT NULL DEFAULT 'custom'
                  CHECK (type IN ('home', 'school', 'work', 'custom')),
    geom          GEOMETRY(Point, 4326),
    radius_meters DOUBLE PRECISION,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_places_family ON places (family_id);
CREATE INDEX idx_places_geom ON places USING GIST (geom);

-- Geofences link a place to a user with enter/exit notification flags.
CREATE TABLE geofences (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id    UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    place_id     UUID REFERENCES places(id) ON DELETE SET NULL,
    user_id      UUID REFERENCES users(id) ON DELETE CASCADE,
    enter_notify BOOLEAN NOT NULL DEFAULT TRUE,
    exit_notify  BOOLEAN NOT NULL DEFAULT TRUE,
    enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_geofences_family ON geofences (family_id);

-- Location history: a TimescaleDB hypertable partitioned on ts.
CREATE TABLE locations (
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    ts              TIMESTAMPTZ NOT NULL,
    geom            GEOMETRY(Point, 4326) NOT NULL,
    accuracy_meters DOUBLE PRECISION,
    altitude_meters DOUBLE PRECISION,
    speed_mps       DOUBLE PRECISION,
    heading_deg     DOUBLE PRECISION,
    battery_pct     DOUBLE PRECISION,
    motion_state    TEXT,
    source          TEXT
);

SELECT create_hypertable('locations', 'ts', if_not_exists => TRUE);

CREATE INDEX idx_locations_device_ts ON locations (device_id, ts DESC);
CREATE INDEX idx_locations_geom ON locations USING GIST (geom);
