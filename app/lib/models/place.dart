import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../utils/units.dart';

/// Minimum place radius (250 feet) in meters.
const double kMinPlaceRadiusMeters = 76.2;

/// Maximum place radius (2 miles) in meters.
const double kMaxPlaceRadiusMeters = 3218.69;

/// A saved Place (geofence): a named location with a map position, an address
/// label, and an arrive/leave radius. Shared with all family members.
///
/// This is the real data model produced by the onboarding "Add locations" step
/// (via [PlacePickerScreen]) — a lat/lon + radius, not a decorative toggle.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.icon,
    required this.address,
    required this.position,
    required this.radiusMeters,
    this.type = 'custom',
    this.alertsOn = false,
    this.geofenceId,
  });

  final String id;
  final String name;
  final IconData icon;
  final String address;
  final LatLng position;
  final double radiusMeters;

  /// Backend place type: "home", "work", "school", "gym", or "custom".
  final String type;
  final bool alertsOn;

  /// The id of the geofence backing [alertsOn], when one exists. Client-side
  /// only — never serialized to the backend.
  final String? geofenceId;

  /// Sentinel passed to [copyWith] to explicitly clear [geofenceId].
  static const Object clearGeofence = Object();

  /// Maps a backend place [type] to its Material icon.
  static IconData iconForType(String type) {
    switch (type) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.business_center;
      case 'school':
        return Icons.school;
      case 'gym':
        return Icons.fitness_center;
      case 'custom':
      default:
        return Icons.place_outlined;
    }
  }

  /// Human-readable radius in the user's units, e.g. "500 ft", "1.5 mi",
  /// "150 m" or "2 km".
  String get radiusLabel => Units.distance(radiusMeters, metric: Units.current);

  Place copyWith({
    String? name,
    IconData? icon,
    String? address,
    LatLng? position,
    double? radiusMeters,
    String? type,
    bool? alertsOn,
    Object? geofenceId,
  }) {
    return Place(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      address: address ?? this.address,
      position: position ?? this.position,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      type: type ?? this.type,
      alertsOn: alertsOn ?? this.alertsOn,
      geofenceId: identical(geofenceId, clearGeofence)
          ? null
          : (geofenceId as String? ?? this.geofenceId),
    );
  }
}
