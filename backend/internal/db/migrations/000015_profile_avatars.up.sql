-- 000015_profile_avatars.up.sql
-- Profile avatars are private account data. Keep the bytes in PostgreSQL so
-- they participate in the deployment's normal backup, access-control, and
-- encryption-at-rest posture; the API never exposes a public avatar URL.
ALTER TABLE users
    ADD COLUMN avatar_data BYTEA,
    ADD COLUMN avatar_content_type TEXT,
    ADD COLUMN avatar_updated_at TIMESTAMPTZ,
    ADD CONSTRAINT users_avatar_content_type_check
        CHECK (avatar_content_type IS NULL OR avatar_content_type IN ('image/jpeg', 'image/png')),
    ADD CONSTRAINT users_avatar_data_size_check
        CHECK (avatar_data IS NULL OR octet_length(avatar_data) <= 5242880),
    ADD CONSTRAINT users_avatar_metadata_check
        CHECK (
            (avatar_data IS NULL AND avatar_content_type IS NULL AND avatar_updated_at IS NULL)
            OR
            (avatar_data IS NOT NULL AND avatar_content_type IS NOT NULL AND avatar_updated_at IS NOT NULL)
        );
