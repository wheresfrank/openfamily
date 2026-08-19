-- 000004_creator_authorization.up.sql
-- Track who created each place/geofence so only the creator (or an admin) can
-- edit or delete it.

ALTER TABLE places ADD COLUMN created_by UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE geofences ADD COLUMN created_by UUID REFERENCES users(id) ON DELETE SET NULL;
