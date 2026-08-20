-- 000014_invite_codes.up.sql
-- Invite codes gate registration: a new user must present a valid, unexpired,
-- unused code to register. Each code is bound to a family and assigns the
-- joining user that family and role. The first platform admin is exempt — it is
-- auto-created at startup from PLATFORM_ADMIN_EMAIL/PLATFORM_ADMIN_PASSWORD.
CREATE TABLE invite_codes (
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

CREATE INDEX idx_invite_codes_family ON invite_codes (family_id);
