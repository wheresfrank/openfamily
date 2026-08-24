import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors non-long-lived session credentials into [SharedPreferences] so the
/// background location isolate can read them.
///
/// The foreground app stores tokens in [TokenStorage] (flutter_secure_storage →
/// iOS Keychain / Android Keystore). This store deliberately holds **only**
/// short-lived values: the API base URL, the current access token (15-minute
/// TTL), and the device id. The long-lived refresh token is NOT mirrored here:
/// SharedPreferences is a plaintext XML file inside the app sandbox, and
/// writing a 30-day credential to it would defeat the Keystore-backed
/// protection the secure store provides (audit finding WB-002). The background
/// isolate reads the refresh token directly from [TokenStorage] on the rare
/// occasions it must refresh (see background_location_service.dart); when that
/// read fails there, reporting pauses until the app is next opened.
///
/// The foreground app calls [sync] whenever tokens or the device id change,
/// and [clear] on logout.
class BackgroundCredentialStore {
  BackgroundCredentialStore._();

  static const String _apiBaseUrlKey = 'wb_api_base_url';
  static const String _accessTokenKey = 'wb_access_token';
  static const String _deviceIdKey = 'wb_device_id';

  /// Writes the background-visible credentials to shared_preferences.
  static Future<void> sync({
    required String apiBaseUrl,
    required String accessToken,
    required String deviceId,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseUrlKey, apiBaseUrl);
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_deviceIdKey, deviceId);
  }

  /// Removes all credentials from shared_preferences.
  static Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiBaseUrlKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_deviceIdKey);
  }

  static Future<String?> readApiBaseUrl() async =>
      (await SharedPreferences.getInstance()).getString(_apiBaseUrlKey);

  static Future<String?> readAccessToken() async =>
      (await SharedPreferences.getInstance()).getString(_accessTokenKey);

  static Future<String?> readDeviceId() async =>
      (await SharedPreferences.getInstance()).getString(_deviceIdKey);

  /// Persists a refreshed access token (called from the background callback).
  static Future<void> saveAccessToken(String token) async =>
      (await SharedPreferences.getInstance()).setString(_accessTokenKey, token);

  /// Persists the device id (called from the foreground app after registration).
  static Future<void> saveDeviceId(String id) async =>
      (await SharedPreferences.getInstance()).setString(_deviceIdKey, id);
}
