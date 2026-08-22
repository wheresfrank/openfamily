-- Recreate the original CHECK. Rows typed "gym" would violate it, so they
-- fall back to custom before the constraint is restored.
UPDATE places SET type = 'custom' WHERE type = 'gym';
ALTER TABLE places DROP CONSTRAINT IF EXISTS places_type_check;
ALTER TABLE places ADD CONSTRAINT places_type_check
    CHECK (type IN ('home', 'school', 'work', 'custom'));
