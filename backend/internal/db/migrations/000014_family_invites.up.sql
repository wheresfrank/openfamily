-- 000014_family_invites.up.sql
-- Short-lived, server-issued invite codes for joining a family.
CREATE TABLE family_invites (
    code       TEXT PRIMARY KEY,
    family_id  UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_family_invites_family ON family_invites (family_id);
CREATE INDEX idx_family_invites_expiry ON family_invites (expires_at);
