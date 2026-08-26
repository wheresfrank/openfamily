-- Per-device ingest keys: a write-only credential that lets a device's
-- background reporter (headless isolate, no access to Keystore-backed secure
-- storage) keep POSTing /locations and /devices/heartbeat after the
-- short-lived access JWT expires. The plaintext key is returned once at
-- registration (or via POST /devices/{id}/ingest-key rotation) and only its
-- SHA-256 hash is stored server-side.
ALTER TABLE devices
    ADD COLUMN ingest_key_hash TEXT;
