-- 000020_alerts.up.sql
CREATE TABLE alerts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id    UUID REFERENCES families(id) ON DELETE SET NULL,
    type         TEXT NOT NULL CHECK (type IN ('check_in', 'help', 'sos')),
    status       TEXT NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active', 'resolved')),
    lat          DOUBLE PRECISION,
    lon          DOUBLE PRECISION,
    note         TEXT,
    share_token  TEXT NOT NULL UNIQUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at  TIMESTAMPTZ
);

CREATE INDEX idx_alerts_family_created ON alerts (family_id, created_at DESC);
CREATE INDEX idx_alerts_share_token ON alerts (share_token);
