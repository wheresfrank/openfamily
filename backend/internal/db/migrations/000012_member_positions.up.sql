-- 000012_member_positions.up.sql
-- Stores the last-known position per user, separate from the locations
-- hypertable (which has a 90-day retention policy). This ensures a member's
-- last position survives even after their history chunks are purged, so they
-- remain visible on the family map.
CREATE TABLE member_positions (
    user_id         uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    lat             double precision NOT NULL,
    lon             double precision NOT NULL,
    ts              timestamptz NOT NULL,
    battery_pct     double precision,
    speed_mps       double precision,
    motion_state    text,
    accuracy_meters double precision,
    device_id       uuid REFERENCES devices(id) ON DELETE SET NULL,
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Backfill from the latest location row per user so existing members keep
-- their last-known position immediately after migration (rather than showing
-- as "no position" until their next report).
INSERT INTO member_positions (user_id, lat, lon, ts, battery_pct, speed_mps, motion_state, accuracy_meters, device_id, updated_at)
SELECT DISTINCT ON (d.user_id)
    d.user_id,
    ST_Y(l.geom),
    ST_X(l.geom),
    l.ts,
    l.battery_pct,
    l.speed_mps,
    l.motion_state,
    l.accuracy_meters,
    l.device_id,
    l.ts
FROM locations l
JOIN devices d ON d.id = l.device_id
ORDER BY d.user_id, l.ts DESC
ON CONFLICT (user_id) DO NOTHING;