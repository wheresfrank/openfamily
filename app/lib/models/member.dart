import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Speed (m/s) at or above which a driving member is shown as a
/// "race car with flames" (70 mph, about 113 km/h).
const double kSpeedingMps = 31.2928;

/// Health/accuracy state of a member's location, mapped to the colored
/// status circle shown on their avatar bubble and list row.
enum MemberStatus {
/// Green — live, real-time, accurate location.
  normal,

  /// Orange — low battery or location-accuracy issue (warning).
  warning,

  /// Purple — GPS accuracy issue; app can't lock an exact spot.
  gpsIssue,

  /// Grey — location updates stopped (phone off / no signal).
  stopped,

  /// Red — location error (slow internet / settings).
  error,
}

/// What a member is currently doing / where they are, shown as a small
/// movement icon badge next to their avatar.
enum MovementType {
  /// Driving — car icon, speed shown in mph (race car + flames if speeding).
  car,

  /// Cycling.
  bike,

  /// On a boat.
  boat,

  /// On a plane — no speed shown.
  plane,

  /// Arrived at saved "Home".
  home,

  /// At "Work".
  work,

  /// At the "Gym".
  gym,

  /// Most-visited place (yellow star).
  star,

  /// No movement context.
  none,
}

/// A single past location in a member's day, shown on the Day Detail
/// location-history timeline.
class LocationHistoryEntry {
  const LocationHistoryEntry({
    required this.time,
    required this.address,
    this.movement = MovementType.none,
    this.position,
  });

  /// When the member was at this location.
  final DateTime time;

  /// Human-readable place / address label.
  final String address;

  /// What the member was doing (driving, at home, at work, etc.).
  final MovementType movement;

  /// Optional geographic position for a map trail.
  final LatLng? position;
}

/// A single family member rendered on the map and in the bottom sheet.
class Member {
  const Member({
    required this.id,
    required this.name,
    required this.position,
    required this.status,
    required this.batteryPercent,
    required this.address,
    this.hasAvatar = false,
    this.avatarUpdatedAt,
    this.avatarVersion = 0,
    this.avatarColor = AppColors.purple,
    this.movement = MovementType.none,
    this.speedMps,
    this.eta,
    this.waypoints,
    this.history = const [],
    this.lastSeen,
    this.accuracyMeters,
  });

  final String id;
  final String name;

  /// Geographic position pinned on the map (the "home" / base position).
  ///
  /// Nullable: a member who has never reported a location has no position yet
  /// and is rendered without a map bubble (see [MemberStatus.stopped]).
  final LatLng? position;

  final MemberStatus status;

  /// Battery percentage (0–100).
  final int batteryPercent;

  /// Human-readable current address / place label.
  final String address;

  /// Whether this member has uploaded a profile photo.
  ///
  /// Avatar bytes are always loaded through the authenticated family-avatar
  /// endpoint; the member payload deliberately never carries a public URL.
  final bool hasAvatar;

  /// Server timestamp for the current avatar. This is retained for display
  /// compatibility; [avatarVersion] is the durable cache and ordering value.
  final DateTime? avatarUpdatedAt;

  /// Monotonically increasing server-side revision for the member's avatar.
  ///
  /// Both uploads and removals increment this value. It is intentionally used
  /// instead of a timestamp to order WebSocket frames, so rapid changes cannot
  /// be mistaken for one another when timestamps have the same resolution.
  final int avatarVersion;

  /// Fill color for the initials fallback avatar.
  final Color avatarColor;

  final MovementType movement;

  /// Speed in meters per second, only meaningful when [movement] is
  /// [MovementType.car]. Formatted for display with `Units`.
  final double? speedMps;

  /// Estimated time of arrival, e.g. "12m" or "6:42 PM".
  final String? eta;

  /// Optional closed loop of waypoints used to simulate live movement.
  /// When present, the map animates the member along this path.
  final List<LatLng>? waypoints;

  /// The member's location history for the day (Day Detail timeline).
  /// Empty unless a caller has loaded it; Day Detail fetches from the API.
  final List<LocationHistoryEntry> history;

  /// When this member last reported a location (the backend `ts`), or null if
  /// they have never reported. Used to re-evaluate staleness on a timer so a
  /// member whose updates stop transitions to the grey "stopped" status.
  final DateTime? lastSeen;

  /// GPS accuracy in meters — the uncertainty radius of the reported fix.
  /// Null when the backend didn't provide an accuracy value. Used to draw the
  /// blue "range" circle around the member and to label their accuracy.
  final double? accuracyMeters;

  /// Whether this member is driving fast enough to show as "speeding".
  bool get isSpeeding =>
      movement == MovementType.car &&
      speedMps != null &&
      speedMps! >= kSpeedingMps;

  /// Whether the map pin should render a numeric speed caption.
  bool get hasDrivingSpeed =>
      movement == MovementType.car && speedMps != null;

  /// Initials used while no avatar is available.
  String get initials {
    final List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Returns a copy of this member with the given fields replaced. Used to
  /// apply live location updates without mutating the immutable member.
  ///
  /// Note: nullable fields ([position], [speedMph], [eta], [lastSeen]) cannot
  /// be cleared here — pass a value to change them, omit to keep the current
  /// one. Live updates always carry a fresh position, so clearing is never
  /// needed.
  Member copyWith({
    LatLng? position,
    MemberStatus? status,
    int? batteryPercent,
    String? address,
    String? name,
    MovementType? movement,
    double? speedMps,
    String? eta,
    DateTime? lastSeen,
    double? accuracyMeters,
  }) {
    return Member(
      id: id,
      name: name ?? this.name,
      position: position ?? this.position,
      status: status ?? this.status,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      address: address ?? this.address,
      hasAvatar: hasAvatar,
      avatarUpdatedAt: avatarUpdatedAt,
      avatarVersion: avatarVersion,
      avatarColor: avatarColor,
      movement: movement ?? this.movement,
      speedMps: speedMps ?? this.speedMps,
      eta: eta ?? this.eta,
      waypoints: waypoints,
      history: history,
      lastSeen: lastSeen ?? this.lastSeen,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
    );
  }

  /// Returns a copy with only the family-avatar metadata changed.
  ///
  /// Unlike [copyWith], this method permits clearing [avatarUpdatedAt] when a
  /// member removes their photo.
  Member copyWithAvatar({
    required bool hasAvatar,
    required int avatarVersion,
    DateTime? avatarUpdatedAt,
  }) {
    return Member(
      id: id,
      name: name,
      position: position,
      status: status,
      batteryPercent: batteryPercent,
      address: address,
      hasAvatar: hasAvatar,
      avatarUpdatedAt: hasAvatar ? avatarUpdatedAt : null,
      avatarVersion: avatarVersion,
      avatarColor: avatarColor,
      movement: movement,
      speedMps: speedMps,
      eta: eta,
      waypoints: waypoints,
      history: history,
      lastSeen: lastSeen,
      accuracyMeters: accuracyMeters,
    );
  }
}

/// Maps a [MemberStatus] to its display color.
extension MemberStatusColor on MemberStatus {
  Color get color {
    switch (this) {
      case MemberStatus.normal:
        return AppColors.statusGreen;
      case MemberStatus.warning:
        return AppColors.statusOrange;
      case MemberStatus.gpsIssue:
        return AppColors.statusPurple;
      case MemberStatus.stopped:
        return AppColors.statusGrey;
      case MemberStatus.error:
        return AppColors.statusRed;
    }
  }

  /// Short human-readable label for the list row.
  String get label {
    switch (this) {
      case MemberStatus.normal:
        return CurrentL10n.value.statusLive;
      case MemberStatus.warning:
        return CurrentL10n.value.statusLowBatteryAccuracy;
      case MemberStatus.gpsIssue:
        return CurrentL10n.value.statusGpsIssue;
      case MemberStatus.stopped:
        return CurrentL10n.value.statusUpdatesStopped;
      case MemberStatus.error:
        return CurrentL10n.value.statusLocationError;
    }
  }

  /// Longer, colorblind-safe description used for tooltips / semantics.
  String get description {
    switch (this) {
      case MemberStatus.normal:
        return CurrentL10n.value.statusDescLive;
      case MemberStatus.warning:
        return CurrentL10n.value.statusDescWarning;
      case MemberStatus.gpsIssue:
        return CurrentL10n.value.statusDescGpsIssue;
      case MemberStatus.stopped:
        return CurrentL10n.value.statusDescStopped;
      case MemberStatus.error:
        return CurrentL10n.value.statusDescError;
    }
  }
}

/// Maps a [MovementType] to its icon and display color.
extension MovementTypeIcon on MovementType {
  IconData get icon {
    switch (this) {
      case MovementType.car:
        return Icons.directions_car;
      case MovementType.bike:
        return Icons.directions_bike;
      case MovementType.boat:
        return Icons.directions_boat;
      case MovementType.plane:
        return Icons.flight;
      case MovementType.home:
        return Icons.home;
      case MovementType.work:
        return Icons.business_center;
      case MovementType.gym:
        return Icons.fitness_center;
      case MovementType.star:
        return Icons.star;
      case MovementType.none:
        // No movement icon is defined for "none"; MovementIcon renders
        // nothing for this state, so this fallback is never shown.
        return Icons.person_outline;
    }
  }

  /// Accent color for the movement icon; the "most-visited place" star is
  /// yellow, everything else uses the brand purple.
  Color get color {
    switch (this) {
      case MovementType.star:
        return AppColors.starYellow;
      default:
        return AppColors.purple;
    }
  }

  /// Short human-readable label used in tooltips / semantics.
  String get label {
    switch (this) {
      case MovementType.car:
        return CurrentL10n.value.movementDriving;
      case MovementType.bike:
        return CurrentL10n.value.movementBiking;
      case MovementType.boat:
        return CurrentL10n.value.movementBoat;
      case MovementType.plane:
        return CurrentL10n.value.movementFlying;
      case MovementType.home:
        return CurrentL10n.value.movementAtHome;
      case MovementType.work:
        return CurrentL10n.value.movementAtWork;
      case MovementType.gym:
        return CurrentL10n.value.movementAtGym;
      case MovementType.star:
        return CurrentL10n.value.movementMostVisited;
      case MovementType.none:
        return '';
    }
  }
}
