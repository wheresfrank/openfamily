-- 000018_emergency_contacts.up.sql
-- Per-user emergency contacts who receive SOS even without the app. Phone
-- digits are stored separately so "+1 415 555 0132" and "415-555-0132" can
-- still be unique per user without requiring a full address-book permission.
CREATE TABLE emergency_contacts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    phone        TEXT NOT NULL,
    phone_digits TEXT NOT NULL,
    relation     TEXT NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT emergency_contacts_name_len CHECK (char_length(name) BETWEEN 1 AND 80),
    CONSTRAINT emergency_contacts_phone_len CHECK (char_length(phone) BETWEEN 1 AND 32),
    CONSTRAINT emergency_contacts_digits CHECK (phone_digits ~ '^[0-9]{7,15}$'),
    CONSTRAINT emergency_contacts_relation_len CHECK (char_length(relation) <= 40)
);

CREATE UNIQUE INDEX emergency_contacts_user_digits
    ON emergency_contacts (user_id, phone_digits);

CREATE INDEX emergency_contacts_user_id
    ON emergency_contacts (user_id, created_at);
