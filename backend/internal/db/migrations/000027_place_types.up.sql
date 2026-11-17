-- More place types so a family can pick a fitting icon for each saved place.
ALTER TABLE places DROP CONSTRAINT IF EXISTS places_type_check;
ALTER TABLE places ADD CONSTRAINT places_type_check
    CHECK (type IN ('home', 'school', 'work', 'gym', 'family', 'friend',
                    'store', 'health', 'park', 'food', 'worship', 'custom'));
