-- 000005_pending_notifications.up.sql
-- Pending-notification model: separate current reality (`inside`) from the
-- last-notified state (`notified_inside`), so a debounce-suppressed transition
-- is left PENDING and eventually fired by the reconcile worker instead of being
-- permanently dropped. Also track whether an event's push was sent so the
-- reconcile worker can re-dispatch failed pushes.

-- notified_inside: the last state that was actually notified (NULL = never).
-- last_notified_at: when the last notification fired (NULL = never).
ALTER TABLE geofence_states ADD COLUMN notified_inside BOOLEAN;
ALTER TABLE geofence_states ADD COLUMN last_notified_at TIMESTAMPTZ;

-- last_transition_at is superseded by last_notified_at.
ALTER TABLE geofence_states DROP COLUMN last_transition_at;

-- push_sent: whether the event's push notification was successfully delivered.
ALTER TABLE geofence_events ADD COLUMN push_sent BOOLEAN NOT NULL DEFAULT FALSE;
