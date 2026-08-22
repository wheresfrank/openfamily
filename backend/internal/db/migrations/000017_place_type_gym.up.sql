-- 000017_place_type_gym.up.sql
-- The Go API already accepts place type "gym"; the original CHECK did not.
ALTER TABLE places DROP CONSTRAINT IF EXISTS places_type_check;
ALTER TABLE places ADD CONSTRAINT places_type_check
    CHECK (type IN ('home', 'school', 'work', 'gym', 'custom'));
