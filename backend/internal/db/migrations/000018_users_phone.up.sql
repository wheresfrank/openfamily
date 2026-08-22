-- 000018_users_phone.up.sql
-- Optional E.164 phone used for family SMS alerts. Unique when set so two
-- accounts cannot claim the same number.
ALTER TABLE users ADD COLUMN phone TEXT;
CREATE UNIQUE INDEX idx_users_phone ON users (phone)
    WHERE phone IS NOT NULL AND phone <> '';
