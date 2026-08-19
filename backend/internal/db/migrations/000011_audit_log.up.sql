-- 000011_audit_log.up.sql
-- Audit log for sensitive operations (auth, role changes, place/geofence
-- management). Written best-effort by the API; never blocks the request.
CREATE TABLE audit_log (
    id          bigserial PRIMARY KEY,
    user_id     uuid REFERENCES users(id) ON DELETE SET NULL,
    family_id   uuid REFERENCES families(id) ON DELETE SET NULL,
    action      text NOT NULL,
    detail      text NOT NULL DEFAULT '',
    ip_address  text NOT NULL DEFAULT '',
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_log_user_id ON audit_log(user_id);
CREATE INDEX idx_audit_log_created_at ON audit_log(created_at DESC);
