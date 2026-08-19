-- 000013_platform_admin.down.sql
DROP INDEX IF EXISTS idx_users_platform_admin;
ALTER TABLE users DROP COLUMN IF EXISTS platform_admin;