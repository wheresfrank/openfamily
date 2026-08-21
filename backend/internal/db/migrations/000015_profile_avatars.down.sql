-- 000015_profile_avatars.down.sql
ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_avatar_metadata_check,
    DROP CONSTRAINT IF EXISTS users_avatar_data_size_check,
    DROP CONSTRAINT IF EXISTS users_avatar_content_type_check,
    DROP COLUMN IF EXISTS avatar_updated_at,
    DROP COLUMN IF EXISTS avatar_content_type,
    DROP COLUMN IF EXISTS avatar_data;
