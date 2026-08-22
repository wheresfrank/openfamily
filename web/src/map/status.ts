// Status + movement derivation — a TypeScript port of the Flutter app's
// app/lib/services/member_mapper.dart.
//
// The rules are identical so the web panel agrees with the app:
//   - stale after 10 minutes (kStaleAfter)
//   - low battery warning below 15% (kLowBatteryThreshold)
//   - GPS accuracy issue at/above 100m (kGpsIssueAccuracyMeters)
//   - movement from `motion_state`: driving→car, cycling→bike, else none
//   - speed_mps (m/s) → mph (× 2.23694)
// A `location` frame is applied on top of an existing member, falling back to
// the prior value when a field is omitted, so a position-only frame does not
// spuriously flip a low-battery / driving member back to normal / still.

import type {
  LatLng,
  LocationFields,
  Member,
  MemberStatus,
  MovementType,
  RawMember,
} from "./types";

/** A member is "stale" when their last report is older than this. */
export const STALE_AFTER_MS = 10 * 60 * 1000;

/** Battery percentage below which a member is flagged as a warning. */
export const LOW_BATTERY_THRESHOLD = 15;

/** Accuracy (meters) at/above which a member is flagged as a GPS issue. */
export const GPS_ISSUE_ACCURACY_METERS = 100;

/** Speed (mph) at/above which a driving member is shown as "speeding". */
export const SPEEDING_MPH = 70;

const MPS_TO_MPH = 2.23694;

/**
 * Parses the backend `ts` field, which may be an ISO-8601 string or a Unix
 * timestamp (seconds or milliseconds). Returns epoch milliseconds (UTC), or
 * null when absent/unparseable.
 */
export function parseTs(ts: LocationFields["ts"]): number | null {
  if (ts == null) return null;
  if (typeof ts === "number") {
    const ms = ts < 1e12 ? ts * 1000 : ts;
    return Math.round(ms);
  }
  if (typeof ts === "string") {
    const parsed = Date.parse(ts);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

/**
 * Parses the durable avatar revision. Invalid or legacy snapshot values map
 * to zero; live avatar frames with version zero are ignored by their caller
 * because they cannot supersede any known revision.
 */
export function avatarVersionFrom(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
    ? value
    : 0;
}

/**
 * Maps the backend's free-form `motion_state` string to a MovementType.
 * Ports `_movementFrom` exactly: only driving and cycling map to a movement;
 * still / walking / running / on_foot / unknown / null all collapse to none.
 */
export function movementFrom(motion: string | null | undefined): MovementType {
  switch (motion) {
    case "driving":
      return "car";
    case "cycling":
      return "bike";
    case "walking":
    case "on_foot":
      return "walking";
    case "running":
      return "running";
    case "still":
    case "stationary":
    case "unknown":
    case null:
      return "none";
    default:
      return "none";
  }
}

/** Whether a driving member is fast enough to flag as "speeding". */
export function isSpeeding(movement: MovementType, speedMph: number | null): boolean {
  return movement === "car" && speedMph != null && speedMph >= SPEEDING_MPH;
}

/**
 * Derives the MemberStatus from the raw backend fields. Ports `_statusFrom`:
 *   - no position, or stale/missing timestamp → "stopped"
 *   - low battery (< 15%)                    → "warning"
 *   - poor accuracy (>= 100m)                 → "gpsIssue"
 *   - otherwise                               → "normal"
 *
 * The "error" status is intentionally not derived here, matching the app's
 * mapper (it is set elsewhere). It remains available on the type for parity.
 */
export function statusFrom(
  position: LatLng | null,
  ts: number | null,
  batteryPct: number | null | undefined,
  accuracy: number | null | undefined,
  nowMs: number,
): MemberStatus {
  if (position == null) return "stopped";
  if (ts == null || nowMs - ts > STALE_AFTER_MS) return "stopped";
  if ((batteryPct ?? 100) < LOW_BATTERY_THRESHOLD) return "warning";
  if ((accuracy ?? 0) > GPS_ISSUE_ACCURACY_METERS) return "gpsIssue";
  return "normal";
}

/** Human-readable current label. Ports `_addressFrom`. */
export function addressFrom(
  position: LatLng | null,
  ts: number | null,
  movement: MovementType,
  nowMs: number,
): string {
  if (position == null) return "No location yet";
  if (movement === "car") return "Driving";
  if (movement === "bike") return "Biking";
  if (movement === "walking") return "Walking";
  if (movement === "running") return "Running";
  if (ts == null) return "No location yet";
  const age = nowMs - ts;
  if (age > STALE_AFTER_MS) return `Last seen ${formatAgo(age)} ago`;
  return movement === "none" ? "Stationary" : "Moving";
}

/**
 * Compact "just now" / "Xm" / "Xh" / "Xd" label for an age in milliseconds.
 * Ports `_formatAgo` (which takes a Duration; here we take ms for the web).
 */
export function formatAgo(ageMs: number): string {
  const mins = Math.floor(ageMs / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  return `${days}d`;
}

/** "last seen Xm ago" / "never" label for a member's lastSeen. */
export function lastSeenLabel(member: Member, nowMs: number): string {
  if (member.lastSeen == null) return "never";
  const age = nowMs - member.lastSeen;
  if (age < 0) return "just now";
  if (age > STALE_AFTER_MS) return `Last seen ${formatAgo(age)} ago`;
  return `${formatAgo(age)} ago`;
}

/** The member's initials (first + last initial), used when there is no photo. */
export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter((p) => p.length > 0);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0]![0]!.toUpperCase();
  return (parts[0]![0]! + parts[parts.length - 1]![0]!).toUpperCase();
}

/**
 * Builds a fully-derived Member from a raw backend member, attaching the
 * family context (id, name, accent color). Ports `memberFromJson`.
 */
export function deriveMember(
  raw: RawMember,
  familyId: string,
  familyName: string,
  avatarColor: string,
  memberColor: string,
  nowMs: number,
): Member {
  const position =
    raw.lat != null && raw.lon != null ? { lat: raw.lat, lon: raw.lon } : null;
  const ts = parseTs(raw.ts);
  const movement = movementFrom(raw.motion_state);
  const batteryPct = raw.battery_pct;
  const speedMps = raw.speed_mps;

  return {
    id: raw.id ?? "",
    name: raw.name ?? "Member",
    familyId,
    familyName,
    avatarColor,
    memberColor,
    position,
    status: statusFrom(position, ts, batteryPct, raw.accuracy_meters, nowMs),
    batteryPercent: batteryPct != null ? Math.round(batteryPct) : 0,
    movement,
    speedMph: speedMps != null ? Math.round(speedMps * MPS_TO_MPH) : null,
    lastSeen: ts,
    address: addressFrom(position, ts, movement, nowMs),
    hasAvatar: raw.has_avatar === true,
    avatarUpdatedAt: raw.avatar_updated_at ?? null,
    avatarVersion: avatarVersionFrom(raw.avatar_version),
    avatarUrl: raw.avatar_url ?? undefined,
  };
}

/**
 * Applies a single `/ws/stream` `location` frame to an existing member,
 * returning a new Member with the updated fields. Ports
 * `memberFromLocationUpdate`: a `location` frame always carries a fresh
 * lat/lon, and the other fields fall back to the existing values when omitted
 * (so a position-only frame does not reset battery/movement/status).
 */
export function applyLocationUpdate(
  existing: Member,
  frame: LocationFields,
  nowMs: number,
): Member {
  const position =
    frame.lat != null && frame.lon != null
      ? { lat: frame.lat, lon: frame.lon }
      : existing.position;
  // A frame may omit `ts`; fall back to lastSeen so a missing timestamp does
  // not spuriously flip the member to "stopped".
  const ts = parseTs(frame.ts) ?? existing.lastSeen;
  // A frame may omit `motion_state`; keep the existing movement rather than
  // dropping a driving member back to "none".
  const movement =
    frame.motion_state == null || frame.motion_state === ""
      ? existing.movement
      : movementFrom(frame.motion_state);
  // Fall back to last-known battery so a 10% member does not flip to normal
  // (the default 100) on a position-only frame. A member who has never reported
  // battery (0) stays null so statusFrom defaults to 100.
  const effectiveBattery =
    frame.battery_pct ?? (existing.batteryPercent > 0 ? existing.batteryPercent : null);
  const batteryPct = frame.battery_pct;
  const speedMps = frame.speed_mps;
  const accuracy = frame.accuracy_meters ?? null;

  return {
    ...existing,
    position,
    status: statusFrom(position, ts, effectiveBattery, accuracy, nowMs),
    batteryPercent: batteryPct != null ? Math.round(batteryPct) : existing.batteryPercent,
    address: addressFrom(position, ts, movement, nowMs),
    movement,
    speedMph: speedMps != null ? Math.round(speedMps * MPS_TO_MPH) : existing.speedMph,
    lastSeen: ts,
  };
}

/**
 * Re-evaluates a member's staleness from their `lastSeen`, returning a new
 * Member with the grey "stopped" status (and a "Last seen Xm ago" address)
 * once their last report is older than STALE_AFTER_MS. Returns the member
 * unchanged when they are still fresh or have never reported.
 *
 * Ports `refreshStaleness`. Called on a periodic timer so a member whose
 * updates stop (phone off / no signal) transitions to "stopped" even though no
 * `location` frame arrives. The label still advances ("10m" → "1h" → "1d") on
 * later ticks because it is recomputed each time.
 */
export function refreshStaleness(member: Member, nowMs: number): Member {
  if (member.position == null || member.lastSeen == null) return member;
  const age = nowMs - member.lastSeen;
  if (age <= STALE_AFTER_MS) return member;
  const label = `Last seen ${formatAgo(age)} ago`;
  if (member.status === "stopped" && member.address === label) return member;
  return { ...member, status: "stopped", address: label };
}
