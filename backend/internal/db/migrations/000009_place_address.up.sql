-- 000009_place_address.up.sql
-- Add an address (human-readable label) column to places so the Flutter app
-- can sync the address captured by the place picker, not just the lat/lon.

ALTER TABLE places ADD COLUMN address text NOT NULL DEFAULT '';