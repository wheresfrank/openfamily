import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the auth credentials into [SharedPreferences] so the background
/// location isolate can read them.
///
/// The foreground app stores tokens in [TokenStorage] (flutter_secure_storage →
/// iOS Keychain / Android Keystore), but that uses method channels that are not
/// reliably available in the background isolate spawned by `background_locator_2`.
/// [SharedPreferences] is a plain key-value store that works in the background
/// isolate (the plugin's callback dispatcher calls
/// `WidgetsFlutterBinding.ensureInitialized()`, which sets up the method
/// channels it needs).
///
/// The foreground app calls [sync] whenever tokens or the device id change, and
/// [clear] on logout. The background callback reads via the `read*` methods and
/// persists a refreshed token pair via [saveAccessToken] / [saveRefreshToken].
class BackgroundCredentialStore {
  BackgroundCredentialStore._();

  static const String _apiBaseUrlKey = 'wb_api_base_url';
  static const String _accessTokenKey = 'wb_access_token';
  static const String _refreshTokenKey = 'wb_refresh_token';
  static const String _deviceIdKey = 'wb_device_id';

  /// Writes all four credentials to shared_preferences.
  static Future<void> sync({
    required String apiBaseUrl,
    required String accessToken,
    required String refreshToken,
    required String deviceId,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseUrlKey, apiBaseUrl);
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(_deviceIdKey, deviceId);
  }

  /// Removes all four credentials from shared_preferences.
  static Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiBaseUrlKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_deviceIdKey);
  }

  static Future<String?> readApiBaseUrl() async =>
      (await SharedPreferences.getInstance()).getString(_apiBaseUrlKey);

  static Future<String?> readAccessToken() async =>
      (await SharedPreferences.getInstance()).getString(_accessTokenKey);

  static Future<String?> readRefreshToken() async =>
      (await SharedPreferences.getInstance()).getString(_refreshTokenKey);

  static Future<String?> readDeviceId() async =>
      (await SharedPreferences.getInstance()).getString(_deviceIdKey);

  /// Persists a refreshed access token (called from the background callback).
  static Future<void> saveAccessToken(String token) async =>
      (await SharedPreferences.getInstance()).setString(_accessTokenKey, token);

  /// Persists a refreshed refresh token (called from the background callback).
  static Future<void> saveRefreshToken(String token) async =>
      (await SharedPreferences.getInstance()).setString(_refreshTokenKey, token);

  /// Persists the device id (called from the foreground app after registration).
  static Future<void> saveDeviceId(String id) async =>
      (await SharedPreferences.getInstance()).setString(_deviceIdKey, id);
}
