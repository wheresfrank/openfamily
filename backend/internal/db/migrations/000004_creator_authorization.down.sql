-- 000004_creator_authorization.down.sql
-- Reverse of 000004_creator_authorization.up.sql.

ALTER TABLE geofences DROP COLUMN created_by;
ALTER TABLE places DROP COLUMN created_by;
