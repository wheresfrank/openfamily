-- 000023_reconcile_invite_codes.up.sql
-- Reconcile divergent migration-000014 deployments. Early deploys ran a
-- 000014 that created `family_invites`; master's 000014 creates `invite_codes`
-- (id/role/max_uses/uses columns the handler requires). Because both share the
-- version number, databases migrated down either path are marked at >= v14 and
-- never receive the other shape. This migration converges every deployment on
-- `invite_codes`, carrying over any legacy codes.
--
-- Safe on fresh installs: `invite_codes` already exists there and
-- `family_invites` never did, so both branches no-op.

CREATE TABLE IF NOT EXISTS invite_codes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code       TEXT NOT NULL UNIQUE,
    family_id  UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    role       TEXT NOT NULL DEFAULT 'member'
               CHECK (role IN ('admin', 'member', 'child')),
    max_uses   INT NOT NULL DEFAULT 1 CHECK (max_uses >= 1),
    uses       INT NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invite_codes_family ON invite_codes (family_id);

DO $$
BEGIN
    IF to_regclass('public.family_invites') IS NOT NULL THEN
        -- Legacy codes bound a family + expiry only; they join as members with
        -- a single use. Skip rows whose code already exists (shouldn't happen,
        -- but keeps the copy idempotent).
        INSERT INTO invite_codes (code, family_id, created_by, role, max_uses, uses, expires_at, created_at)
        SELECT fi.code, fi.family_id, fi.created_by, 'member', 1, 0, fi.expires_at, fi.created_at
        FROM family_invites fi
        WHERE NOT EXISTS (SELECT 1 FROM invite_codes ic WHERE ic.code = fi.code);
        DROP TABLE family_invites;
    END IF;
END
$$;
