import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the user wants Ice (light) and Night (dark) to be chosen.
enum ThemePreference {
  /// Follow the device light/dark setting.
  system,

  /// Always Ice.
  light,

  /// Always Night.
  dark,
}

extension ThemePreferenceX on ThemePreference {
  ThemeMode get themeMode {
    switch (this) {
      case ThemePreference.system:
        return ThemeMode.system;
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  static ThemePreference parse(String? raw) {
    switch (raw) {
      case 'light':
        return ThemePreference.light;
      case 'dark':
        return ThemePreference.dark;
      case 'system':
      default:
        return ThemePreference.system;
    }
  }
}

/// Persists appearance and notifies [MaterialApp] so Ice/Night swap live.
class ThemePreferenceService {
  ThemePreferenceService._();

  static const String _key = 'theme_preference';

  /// Live value. Missing keys mean [ThemePreference.system].
  static final ValueNotifier<ThemePreference> preference =
      ValueNotifier<ThemePreference>(ThemePreference.system);

  static ThemeMode get themeMode => preference.value.themeMode;

  static Future<ThemePreference> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ThemePreference value = ThemePreferenceX.parse(prefs.getString(_key));
    preference.value = value;
    return value;
  }

  static Future<void> setPreference(ThemePreference value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
    preference.value = value;
  }
}
