import 'dart:convert';

import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:background_locator_2/settings/android_settings.dart';
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart'
    hide AndroidSettings, LocationAccuracy;
import 'package:http/http.dart' as http;

import 'background_credential_store.dart';
import 'token_storage.dart';

/// Background location reporting: keeps the device's GPS position flowing to
/// the backend (`POST /locations`) even when the app is backgrounded or killed.
///
/// `background_locator_2` runs [onLocationUpdate] in a **separate background
/// isolate**, so it cannot touch the foreground app's [ApiClient] object. It
/// instead reads credentials from [BackgroundCredentialStore]
/// (shared_preferences) and talks to the backend directly via `dart:http`,
/// refreshing the access token itself on a 401. On refresh it writes the new
/// pair to shared_preferences and best-effort to [TokenStorage] (secure
/// storage), so the foreground app sees the rotated tokens.
///
/// The callback is deliberately non-throwing: any failure (missing credentials,
/// network error, stale `ts`, non-monotonic ordering) is skipped silently and
/// the next update retries. The foreground app handles re-login when the
/// refresh token itself is dead.

/// How long to wait for a single HTTP request before giving up.
const Duration _httpTimeout = Duration(seconds: 15);

/// Top-level location callback, invoked by the plugin in the background isolate.
///
/// Must be top-level (or a static method) and annotated `@pragma('vm:entry-point')`
/// so the plugin can look it up by callback handle across isolates.
@pragma('vm:entry-point')
Future<void> onLocationUpdate(LocationDto location) async {
  try {
    // Skip spoofed locations (Android mock-location detection).
    if (location.isMocked) return;

    final String? apiBaseUrl = await BackgroundCredentialStore.readApiBaseUrl();
    final String? accessToken =
        await BackgroundCredentialStore.readAccessToken();
    final String? refreshToken =
        await BackgroundCredentialStore.readRefreshToken();
    final String? deviceId = await BackgroundCredentialStore.readDeviceId();

    // Without a full credential set there is nothing to report.
    if (apiBaseUrl == null ||
        apiBaseUrl.isEmpty ||
        accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty) {
      return;
    }

    final int? batteryPct = await _readBattery();
    final Map<String, dynamic> body = _buildBody(location, deviceId, batteryPct);

    final http.Response response =
        await _postLocation(apiBaseUrl, accessToken, body);
    if (response.statusCode == 201) return;

    if (response.statusCode == 401) {
      // Access token expired (TTL 15 min). Refresh and retry once.
      final String? newAccess = await _refresh(apiBaseUrl, refreshToken);
      if (newAccess == null) return; // Refresh failed; foreground re-logs in.
      await _postLocation(apiBaseUrl, newAccess, body);
      // 201 / 400 / anything else: done for this update.
    }
    // 400 (stale ts / non-monotonic) and all other statuses: skip silently.
  } catch (_) {
    // Never throw from the background callback.
  }
}

/// Reads the battery level, or null if unavailable (e.g. web, or the method
/// channel is not reachable from the background isolate). Bounded by a timeout
/// so a non-responsive method channel can't stall the callback indefinitely.
Future<int?> _readBattery() async {
  try {
    return await Battery()
        .batteryLevel
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    return null;
  }
}

/// Builds the `POST /locations` body from a [LocationDto].
Map<String, dynamic> _buildBody(
  LocationDto location,
  String deviceId,
  int? batteryPct,
) {
  final Map<String, dynamic> body = <String, dynamic>{
    'device_id': deviceId,
    'ts': DateTime.fromMillisecondsSinceEpoch(
      location.time.toInt(),
      isUtc: true,
    ).toUtc().toIso8601String(),
    'lat': location.latitude,
    'lon': location.longitude,
    'motion_state': '',
    'source': 'background',
  };
  if (batteryPct != null) body['battery_pct'] = batteryPct;
  if (location.accuracy > 0) body['accuracy_meters'] = location.accuracy;
  // Altitude is valid below sea level (negative), so send any finite value.
  if (location.altitude.isFinite) body['altitude_meters'] = location.altitude;
  if (location.speed > 0) body['speed_mps'] = location.speed;
  if (location.heading >= 0) body['heading_deg'] = location.heading;
  return body;
}

/// POSTs a location report with the given access token.
Future<http.Response> _postLocation(
  String apiBaseUrl,
  String accessToken,
  Map<String, dynamic> body,
) {
  return http
      .post(
        Uri.parse('$apiBaseUrl/locations'),
        headers: <String, String>{
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(_httpTimeout);
}

/// Refreshes the token pair via `POST /auth/refresh`, persisting the new pair
/// to BOTH shared_preferences and (best-effort) flutter_secure_storage.
/// Returns the new access token, or null on failure.
///
/// The backend rotates refresh tokens (each refresh revokes the old one), so
/// the foreground and background must converge on the same pair or they will
/// revoke each other's tokens. shared_preferences always works in the
/// background isolate; the secure-storage write may fail (method channel
/// unavailable), in which case [TokenStorage.syncFromBackgroundStore] on app
/// resume reconciles the foreground.
Future<String?> _refresh(String apiBaseUrl, String refreshToken) async {
  try {
    final http.Response response = await http
        .post(
          Uri.parse('$apiBaseUrl/auth/refresh'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{'refresh_token': refreshToken}),
        )
        .timeout(_httpTimeout);
    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String access = data['access_token'] as String;
      final String refresh = data['refresh_token'] as String;
      // Persist to shared_preferences (always works in the background isolate).
      await BackgroundCredentialStore.saveAccessToken(access);
      await BackgroundCredentialStore.saveRefreshToken(refresh);
      // Best-effort persist to secure storage so the foreground app sees the
      // rotated tokens. May fail in the background isolate; the resume-sync
      // fallback covers that case.
      try {
        await TokenStorage.saveTokens(access: access, refresh: refresh);
      } catch (_) {
        // Secure storage unavailable in the background isolate. shared_preferences
        // already has the new pair; the foreground syncs on resume.
      }
      return access;
    }
  } catch (_) {
    // Fall through to returning null.
  }
  return null;
}

/// Foreground-facing control surface for the background location service.
class BackgroundLocationService {
  BackgroundLocationService._();

  /// Whether [start] should proceed to register the location update. Set true
  /// at [start] entry and false by [stop], so a [stop] that lands while [start]
  /// is still awaiting its async setup aborts the registration instead of
  /// leaving the foreground service running after logout.
  static bool _shouldRun = false;

  /// Starts background location tracking.
  ///
  /// Tuned for battery: a 60-second interval and 50-meter distance filter are
  /// far less aggressive than the foreground reporter's continuous 10-meter
  /// stream, while still keeping the family's view of the user fresh.
  static Future<void> start() async {
    _shouldRun = true;
    await BackgroundLocator.initialize();
    if (!_shouldRun) return;
    // The background isolate's foreground service needs background location
    // ("Allow all the time"). With only foreground ("While using the app")
    // access, Android 15+ rejects starting a `location` foreground service
    // unless the app is in the foreground — which crashes the app when start()
    // runs during startup. Only proceed when background access is granted.
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        return;
      }
    } catch (_) {
      // checkPermission can throw on some platforms (e.g. web); proceed anyway
      // and let the plugin surface any remaining problem.
    }
    if (!_shouldRun) return;
    try {
      await BackgroundLocator.registerLocationUpdate(
        onLocationUpdate,
        androidSettings: const AndroidSettings(
          accuracy: LocationAccuracy.HIGH,
          interval: 60,
          distanceFilter: 50,
          wakeLockTime: 60,
          client: LocationClient.google,
          androidNotificationSettings: AndroidNotificationSettings(
            notificationChannelName: 'Whereabouts',
            notificationTitle: 'Whereabouts',
            notificationMsg: 'Sharing your location with your family',
            notificationBigMsg:
                'Whereabouts is sharing your location in the background so your '
                'family can see where you are.',
          ),
        ),
        iosSettings: const IOSSettings(
          accuracy: LocationAccuracy.HIGH,
          distanceFilter: 50,
          showsBackgroundLocationIndicator: true,
          stopWithTerminate: false,
        ),
      );
    } catch (_) {
      // Never throw from start(): it is called fire-and-forget, and a failure
      // here (e.g. permission revoked mid-flight) must not crash the app.
    }
  }

  /// Stops background location tracking.
  static Future<void> stop() async {
    _shouldRun = false;
    await BackgroundLocator.unRegisterLocationUpdate();
  }

  /// Whether background location tracking is currently active.
  static Future<bool> isRunning() => BackgroundLocator.isServiceRunning();
}
