-- Admin-editable SMS credentials. A single row (id = 1) overrides empty
-- TWILIO_* / PUBLIC_BASE_URL environment values so operators can enable
-- emergency-contact SMS from the web settings page without a restart.
CREATE TABLE sms_settings (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    account_sid TEXT NOT NULL DEFAULT '',
    auth_token TEXT NOT NULL DEFAULT '',
    from_number TEXT NOT NULL DEFAULT '',
    public_base_url TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
