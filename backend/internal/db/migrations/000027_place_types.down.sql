-- Rows using the newer types fall back to custom before the previous CHECK is
-- restored.
UPDATE places SET type = 'custom'
    WHERE type IN ('family', 'friend', 'store', 'health', 'park', 'food', 'worship');
ALTER TABLE places DROP CONSTRAINT IF EXISTS places_type_check;
ALTER TABLE places ADD CONSTRAINT places_type_check
    CHECK (type IN ('home', 'school', 'work', 'gym', 'custom'));
