import 'package:latlong2/latlong.dart';

import '../models/member.dart';

/// Maps backend member JSON (from `GET /family/members` and the `/ws/stream`
/// `members` frame) into a [Member].
///
/// The backend's location fields are all nullable: a member who has never
/// reported a location has null `lat`/`lon`/`ts`. `speed_mps` is meters/second
/// and is converted to mph for display. `motion_state` is a free string.
Member memberFromJson(Map<String, dynamic> json) {
  final num? lat = json['lat'] as num?;
  final num? lon = json['lon'] as num?;
  final dynamic ts = json['ts'];
  final num? batteryPct = json['battery_pct'] as num?;
  final num? speedMps = json['speed_mps'] as num?;
  final String? motion = json['motion_state'] as String?;
  final num? accuracy = json['accuracy_meters'] as num?;

  final LatLng? position =
      (lat != null && lon != null) ? LatLng(lat.toDouble(), lon.toDouble()) : null;
  final DateTime? timestamp = _parseTs(ts);
  final MovementType movement = _movementFrom(motion);

  return Member(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? 'Member',
    position: position,
    status: _statusFrom(
      position: position,
      timestamp: timestamp,
      batteryPct: batteryPct,
      accuracy: accuracy,
    ),
    batteryPercent: (batteryPct ?? 0).round(),
    address: _addressFrom(
      position: position,
      timestamp: timestamp,
      movement: movement,
    ),
    movement: movement,
    speedMph: speedMps != null ? (speedMps * 2.23694).round() : null,
    lastSeen: timestamp,
    accuracyMeters: accuracy,
  );
}

/// Applies a single `/ws/stream` `location` frame to [existing], returning a
/// new [Member] with the updated position/battery/speed/motion/status.
///
/// A `location` frame always carries a fresh `lat`/`lon`, so the position is
/// updated in place; the other fields fall back to the existing values when
/// the frame omits them.
Member memberFromLocationUpdate(Member existing, Map<String, dynamic> json) {
  final num? lat = json['lat'] as num?;
  final num? lon = json['lon'] as num?;
  final dynamic ts = json['ts'];
  final num? batteryPct = json['battery_pct'] as num?;
  final num? speedMps = json['speed_mps'] as num?;
  final String? motion = json['motion_state'] as String?;
  final num? accuracy = json['accuracy_meters'] as num?;

  final LatLng? position =
      (lat != null && lon != null) ? LatLng(lat.toDouble(), lon.toDouble()) : existing.position;
  // A `location` frame may omit `ts`; fall back to the member's last-seen time
  // so a missing timestamp does not spuriously flip them to "stopped".
  final DateTime? timestamp = _parseTs(ts) ?? existing.lastSeen;
  // A `location` frame may omit `motion_state` (the backend emits null when the
  // value is empty); keep the existing movement rather than dropping a driving
  // member back to "none".
  final MovementType movement = (motion == null || motion.isEmpty)
      ? existing.movement
      : _movementFrom(motion);

  // For status derivation, fall back to the member's last-known battery when
  // the frame omits it, so a member at 10% does not flip to "normal" (the
  // default 100) on a frame that carries only a position. A member who has
  // never reported battery (0) stays null so _statusFrom defaults to 100.
  final num? effectiveBattery =
      batteryPct ?? (existing.batteryPercent > 0 ? existing.batteryPercent : null);

  return existing.copyWith(
    position: position,
    status: _statusFrom(
      position: position,
      timestamp: timestamp,
      batteryPct: effectiveBattery,
      accuracy: accuracy,
    ),
    batteryPercent: batteryPct != null ? batteryPct.round() : existing.batteryPercent,
    address: _addressFrom(
      position: position,
      timestamp: timestamp,
      movement: movement,
    ),
    movement: movement,
    speedMph: speedMps != null ? (speedMps * 2.23694).round() : existing.speedMph,
    lastSeen: timestamp,
    accuracyMeters: accuracy ?? existing.accuracyMeters,
  );
}

/// A member is "stale" when their last report is older than this.
const Duration kStaleAfter = Duration(minutes: 10);

/// Battery percentage at or below which a member is flagged as a warning.
const int kLowBatteryThreshold = 15;

/// Accuracy (meters) at or above which a member is flagged as a GPS issue.
const double kGpsIssueAccuracyMeters = 100.0;

/// Derives the [MemberStatus] from the raw backend fields.
MemberStatus _statusFrom({
  required LatLng? position,
  required DateTime? timestamp,
  required num? batteryPct,
  required num? accuracy,
}) {
  if (position == null) return MemberStatus.stopped;
  if (timestamp == null ||
      DateTime.now().toUtc().difference(timestamp) > kStaleAfter) {
    return MemberStatus.stopped;
  }
  if ((batteryPct ?? 100) < kLowBatteryThreshold) return MemberStatus.warning;
  if ((accuracy ?? 0) > kGpsIssueAccuracyMeters) return MemberStatus.gpsIssue;
  return MemberStatus.normal;
}

/// Derives a human-readable label (reverse geocoding is deferred).
String _addressFrom({
  required LatLng? position,
  required DateTime? timestamp,
  required MovementType movement,
}) {
  if (position == null) return 'No location yet';
  if (movement == MovementType.car) return 'Driving';
  if (movement == MovementType.bike) return 'Biking';
  if (timestamp == null) return 'No location yet';
  final Duration age = DateTime.now().toUtc().difference(timestamp);
  if (age > kStaleAfter) return 'Last seen ${_formatAgo(age)} ago';
  return 'Moving';
}

/// Maps the backend's free-form `motion_state` string to a [MovementType].
MovementType _movementFrom(String? motion) {
  switch (motion) {
    case 'driving':
      return MovementType.car;
    case 'cycling':
      return MovementType.bike;
    case 'still':
    case 'stationary':
    case 'walking':
    case 'running':
    case 'on_foot':
    case 'unknown':
    case null:
      return MovementType.none;
    default:
      return MovementType.none;
  }
}

/// Parses the backend `ts` field, which may be an ISO-8601 string or a Unix
/// timestamp (seconds or milliseconds). Returns null when absent/unparseable.
DateTime? _parseTs(dynamic ts) {
  if (ts == null) return null;
  if (ts is num) {
    final double v = ts.toDouble();
    final double ms = v < 1e12 ? v * 1000 : v;
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }
  if (ts is String) {
    return DateTime.tryParse(ts)?.toUtc();
  }
  return null;
}

/// Compact "Xm ago" / "Xh ago" / "Xd ago" label for a stale location.
String _formatAgo(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// Re-evaluates [member]'s staleness from [Member.lastSeen], returning a new
/// [Member] with the grey "stopped" status (and a "Last seen Xm ago" address)
/// once their last report is older than [kStaleAfter]. Returns [member]
/// unchanged when they are still fresh or have never reported.
///
/// Called on a periodic timer so a member whose updates stop (phone off / no
/// signal) transitions to "stopped" even though no `location` frame arrives.
Member refreshStaleness(Member member) {
  final DateTime? lastSeen = member.lastSeen;
  if (member.position == null || lastSeen == null) return member;
  final Duration age = DateTime.now().toUtc().difference(lastSeen);
  if (age <= kStaleAfter) return member;
  final String label = 'Last seen ${_formatAgo(age)} ago';
  // Already stopped with the current label — no change, so the staleness timer
  // does not fire a spurious `onMembersChanged`. The label still advances
  // ("10m" → "1h" → "1d") on later ticks because it is recomputed each time.
  if (member.status == MemberStatus.stopped && member.address == label) {
    return member;
  }
  return member.copyWith(
    status: MemberStatus.stopped,
    address: label,
  );
}
