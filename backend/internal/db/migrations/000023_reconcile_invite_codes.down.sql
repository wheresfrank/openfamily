-- 000023_reconcile_invite_codes.down.sql
-- Restore the legacy family_invites table (codes return as single-use member
-- invites; role/max_uses metadata is not representable in the legacy shape).
CREATE TABLE family_invites (
    code       TEXT PRIMARY KEY,
    family_id  UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

INSERT INTO family_invites (code, family_id, created_by, created_at, expires_at)
SELECT code, family_id, created_by, created_at, expires_at
FROM invite_codes;

DROP TABLE invite_codes;
