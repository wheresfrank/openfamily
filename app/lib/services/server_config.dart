// Runtime server configuration for the Whereabouts app.
//
// The API base URL can come from two sources:
//   1. A compile-time `--dart-define=WHEREABOUTS_API_URL=...` (preferred for
//      managed deployments).
//   2. A user-entered value stored in `shared_preferences` (needed for
//      self-hosted deployments where the user installs a generic APK and
//      enters their own server URL on first launch).
//
// [ServerConfig] resolves the two: the dart-define takes priority; when it is
// empty, the stored value is used.  This lets a pre-built APK work for any
// deployment without rebuilding.

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

const String _kPrefKey = 'wb_api_base_url';

/// Singleton that holds the resolved API base URL.
class ServerConfig {
  ServerConfig._();

  static final ServerConfig instance = ServerConfig._();

  String _apiBaseUrl = kApiBaseUrl; // compile-time default
  bool _loaded = false;

  /// The resolved API base URL (no trailing slash).
  String get apiBaseUrl => _apiBaseUrl;

  /// Whether a non-empty URL is configured.
  bool get isConfigured => _apiBaseUrl.isNotEmpty;

  /// Loads the stored URL from `shared_preferences` if the dart-define was
  /// empty.  Safe to call multiple times; only the first call does I/O.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (kApiBaseUrl.isNotEmpty) {
      _apiBaseUrl = kApiBaseUrl;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPrefKey) ?? '';
    _apiBaseUrl = stored;
  }

  /// Persists a user-entered URL and updates the live value.
  Future<void> setUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    _apiBaseUrl = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, cleaned);
  }

  /// Clears the stored URL (used on logout / reset).
  Future<void> clear() async {
    _apiBaseUrl = kApiBaseUrl; // fall back to dart-define
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }
}