-- 000010_location_retention.up.sql
-- Add a 90-day retention policy to the locations hypertable.
-- TimescaleDB will automatically drop chunks older than 90 days.
SELECT add_retention_policy('locations', INTERVAL '90 days');
