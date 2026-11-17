import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which language the app should use.
enum LanguagePreference {
  /// Follow the device language (English when it is not supported).
  system,

  /// Always English.
  english,

  /// Always Spanish.
  spanish,
}

extension LanguagePreferenceX on LanguagePreference {
  /// The forced locale, or null to follow the device.
  Locale? get locale {
    switch (this) {
      case LanguagePreference.system:
        return null;
      case LanguagePreference.english:
        return const Locale('en');
      case LanguagePreference.spanish:
        return const Locale('es');
    }
  }

  static LanguagePreference parse(String? raw) {
    switch (raw) {
      case 'english':
        return LanguagePreference.english;
      case 'spanish':
        return LanguagePreference.spanish;
      case 'system':
      default:
        return LanguagePreference.system;
    }
  }
}

/// Persists the language choice and notifies [MaterialApp] so it switches live.
///
/// Resolution order: the user's explicit choice (English or Spanish), then the
/// server-wide default language an admin set, then the device language.
class LocalePreferenceService {
  LocalePreferenceService._();

  static const String _key = 'language_preference';
  static const String _serverKey = 'server_default_language';
  static const Set<String> _supported = <String>{'en', 'es'};

  /// The server's default language code ("en", "es"), or null to follow the
  /// device. Remembered across launches so the first frame already uses it.
  static final ValueNotifier<String?> serverDefault =
      ValueNotifier<String?>(null);

  /// The locale to force on the app, or null to follow the device.
  static Locale? get effectiveLocale =>
      resolveLocale(preference.value, serverDefault.value);

  /// Pure resolution of [pref] and the server default [serverLanguage].
  static Locale? resolveLocale(
    LanguagePreference pref,
    String? serverLanguage,
  ) {
    if (pref != LanguagePreference.system) return pref.locale;
    if (serverLanguage != null && _supported.contains(serverLanguage)) {
      return Locale(serverLanguage);
    }
    return null;
  }

  /// Applies `default_language` from a `GET /config` body. Servers that
  /// predate the field leave the stored value untouched.
  static Future<void> applyServerDefault(Map<String, dynamic> cfg) async {
    if (!cfg.containsKey('default_language')) return;
    final Object? raw = cfg['default_language'];
    final String? value =
        raw is String && _supported.contains(raw) ? raw : null;
    if (value == serverDefault.value) return;
    serverDefault.value = value;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_serverKey);
      } else {
        await prefs.setString(_serverKey, value);
      }
    } catch (_) {
      // The in-memory value still applies for this run.
    }
  }

  /// Live value. Missing keys mean [LanguagePreference.system].
  static final ValueNotifier<LanguagePreference> preference =
      ValueNotifier<LanguagePreference>(LanguagePreference.system);

  static Future<LanguagePreference> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LanguagePreference value =
        LanguagePreferenceX.parse(prefs.getString(_key));
    preference.value = value;
    final String? server = prefs.getString(_serverKey);
    serverDefault.value =
        server != null && _supported.contains(server) ? server : null;
    return value;
  }

  static Future<void> setPreference(LanguagePreference value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
    preference.value = value;
  }
}
