-- 000016_profile_avatar_version.up.sql
-- A monotonically increasing version gives clients a durable cache key for a
-- member's private avatar. It changes for both replacement and removal, so a
-- same-timestamp update cannot leave a stale image visible.
ALTER TABLE users
    ADD COLUMN avatar_version BIGINT NOT NULL DEFAULT 0,
    ADD CONSTRAINT users_avatar_version_nonnegative_check
        CHECK (avatar_version >= 0);
