import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's location-sharing preference and notifies listeners
/// (the map screen) so foreground and background reporters can start or stop.
class LocationSharingService {
  LocationSharingService._();

  static const String _key = 'location_sharing_enabled';

  /// Live value, defaulting to sharing on until [load] reads disk.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// Reads the stored preference. Missing keys mean sharing is on.
  static Future<bool> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool value = prefs.getBool(_key) ?? true;
    enabled.value = value;
    return value;
  }

  /// Persists [value] and notifies listeners. Does not start/stop reporters
  /// itself — [MapScreen] applies the change to the live services.
  static Future<void> setEnabled(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    enabled.value = value;
  }
}
