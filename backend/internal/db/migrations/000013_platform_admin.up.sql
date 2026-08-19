-- 000013_platform_admin.up.sql
-- Platform admin: a privilege boundary distinct from a family admin. A
-- platform admin can see ALL families ("groups") and their members on one map
-- and manage APK builds, via the /admin/* API and the admin web panel. This is
-- orthogonal to the family-scoped role column (admin/member/child): a platform
-- admin may or may not also be a family admin.
--
-- The flag defaults to FALSE. The first platform admin is bootstrapped at
-- startup by the PLATFORM_ADMIN_EMAIL env var (see main.go): if that email
-- matches an existing user, that user is promoted to platform_admin = TRUE.
-- No credentials are hardcoded; promotion requires an already-registered user
-- and the env var to be set by an operator.
ALTER TABLE users ADD COLUMN platform_admin BOOLEAN NOT NULL DEFAULT FALSE;

-- A partial index keeps the (very small) set of platform admins cheap to look
-- up on every authenticated admin request via RequirePlatformAdmin.
CREATE INDEX idx_users_platform_admin ON users (platform_admin) WHERE platform_admin;