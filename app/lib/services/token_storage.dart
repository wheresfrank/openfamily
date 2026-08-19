import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'background_credential_store.dart';
import 'server_config.dart';

/// Stores auth tokens in the platform secure store:
/// - iOS: Keychain
/// - Android: Keystore-backed EncryptedSharedPreferences
class TokenStorage {
  TokenStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';
  static const String _deviceIdKey = 'device_id';

  /// Persists an access + refresh token pair.
  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
    // Mirror the credentials into shared_preferences so the background isolate
    // can read them. The device id may still be null here (registration hasn't
    // happened yet); it is synced later by [saveDeviceId].
    final String? deviceId = await readDeviceId();
    await BackgroundCredentialStore.sync(
      apiBaseUrl: ServerConfig.instance.apiBaseUrl,
      accessToken: access,
      refreshToken: refresh,
      deviceId: deviceId ?? '',
    );
  }

  /// Returns the stored access token, or null if none.
  static Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  /// Returns the stored refresh token, or null if none.
  static Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  /// Removes all stored tokens AND the device id (full session teardown).
  ///
  /// The device id is tied to the authenticated user, so it must be cleared
  /// whenever tokens are cleared — otherwise a later login by a different user
  /// would reuse the previous user's device id.
  static Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _deviceIdKey);
    await BackgroundCredentialStore.clear();
  }

  /// Persists the backend device id returned by POST /devices.
  static Future<void> saveDeviceId(String id) async {
    await _storage.write(key: _deviceIdKey, value: id);
    // Mirror the device id into shared_preferences so the background isolate
    // can attach reports to the correct device.
    await BackgroundCredentialStore.saveDeviceId(id);
  }

  /// Returns the stored device id, or null if none.
  static Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  /// Reconciles the secure store with tokens the background isolate may have
  /// rotated while the app was backgrounded.
  ///
  /// The background callback writes refreshed tokens to shared_preferences
  /// (and best-effort to secure storage). If that secure-storage write failed
  /// (method channel unavailable in the background isolate), the foreground
  /// app calls this on resume to copy the newer tokens from shared_preferences
  /// into secure storage, so the foreground [ApiClient] uses the current
  /// (non-revoked) refresh token instead of racing the background isolate.
  static Future<void> syncFromBackgroundStore() async {
    final String? access = await BackgroundCredentialStore.readAccessToken();
    final String? refresh = await BackgroundCredentialStore.readRefreshToken();
    if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
      return;
    }
    final String? currentAccess = await readAccessToken();
    final String? currentRefresh = await readRefreshToken();
    if (access != currentAccess || refresh != currentRefresh) {
      await _storage.write(key: _accessKey, value: access);
      await _storage.write(key: _refreshKey, value: refresh);
    }
  }
}
