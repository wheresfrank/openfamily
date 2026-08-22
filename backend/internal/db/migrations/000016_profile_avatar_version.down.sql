-- 000016_profile_avatar_version.down.sql
ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_avatar_version_nonnegative_check,
    DROP COLUMN IF EXISTS avatar_version;
