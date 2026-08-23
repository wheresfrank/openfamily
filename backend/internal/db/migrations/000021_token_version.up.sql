-- Session invalidation: bump token_version to reject outstanding JWTs after
-- logout, password change, or an admin password reset.
ALTER TABLE users
    ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0;
