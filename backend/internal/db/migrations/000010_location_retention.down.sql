-- 000010_location_retention.down.sql
SELECT remove_retention_policy('locations');
