import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which measurement system the user wants for distances and speeds.
enum UnitPreference {
  /// Follow the device region (imperial in the US, Liberia and Myanmar,
  /// metric everywhere else).
  system,

  /// Meters, kilometers and km/h.
  metric,

  /// Feet, miles and mph.
  imperial,
}

extension UnitPreferenceX on UnitPreference {
  static UnitPreference parse(String? raw) {
    switch (raw) {
      case 'metric':
        return UnitPreference.metric;
      case 'imperial':
        return UnitPreference.imperial;
      case 'system':
      default:
        return UnitPreference.system;
    }
  }
}

/// Persists the unit preference and exposes whether metric is in effect.
class UnitPreferenceService {
  UnitPreferenceService._();

  static const String _key = 'unit_preference';

  /// Regions that still use imperial units for everyday distances and speeds.
  static const Set<String> _imperialRegions = <String>{'US', 'LR', 'MM'};

  /// Live value. Missing keys mean [UnitPreference.system].
  static final ValueNotifier<UnitPreference> preference =
      ValueNotifier<UnitPreference>(UnitPreference.system);

  /// Whether distances and speeds should be shown in metric units.
  static bool get useMetric => resolveMetric(
        preference.value,
        PlatformDispatcher.instance.locale.countryCode,
      );

  /// Resolves [pref] to metric (true) or imperial (false). [countryCode] is the
  /// device region, used only for [UnitPreference.system].
  static bool resolveMetric(UnitPreference pref, String? countryCode) {
    switch (pref) {
      case UnitPreference.metric:
        return true;
      case UnitPreference.imperial:
        return false;
      case UnitPreference.system:
        return !_imperialRegions.contains(countryCode?.toUpperCase());
    }
  }

  static Future<UnitPreference> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final UnitPreference value = UnitPreferenceX.parse(prefs.getString(_key));
    preference.value = value;
    return value;
  }

  static Future<void> setPreference(UnitPreference value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
    preference.value = value;
  }
}
