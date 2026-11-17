-- Admin-editable server-wide settings. A single row (id = 1). default_language
-- is the language apps and the admin panel use when a user has not picked one:
-- 'en', 'es', or '' to follow each device. It overrides DEFAULT_LANGUAGE.
CREATE TABLE server_settings (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    default_language TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
