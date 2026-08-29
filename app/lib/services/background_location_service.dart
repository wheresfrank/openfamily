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
import 'location_outbox.dart';
import 'token_storage.dart';

/// Background location reporting: keeps the device's GPS position flowing to
/// the backend (`POST /locations`) even when the app is backgrounded or killed.
///
/// `background_locator_2` runs [onLocationUpdate] in a **separate background
/// isolate**, so it cannot touch the foreground app's [ApiClient] object. It
/// instead reads short-lived credentials (API base URL, device id, ingest key,
/// access token) from [BackgroundCredentialStore] (shared_preferences) and
/// talks to the backend directly via `dart:http`.
///
/// Authentication — preferred path is the **device ingest key**
/// (`X-Device-Key: <device_id>.<key>` header): a write-only, device-scoped
/// credential issued at registration and accepted by `POST /locations`,
/// `POST /locations/batch`, and `POST /devices/heartbeat`. It never expires,
/// so background reporting no longer depends on the Keystore-backed secure
/// store being reachable from a headless isolate — that dependency (reading
/// the refresh token there on a 401, WB-002) was production-proven to
/// silently stop reporting at the first access-token expiry (~15 minutes
/// after the app was last open).
///
/// The legacy path — short-lived access JWT with refresh-on-401 — is kept as
/// a fallback for devices whose server predates ingest keys, or whose ingest
/// key was rejected (401/403). The refresh token itself is still never
/// mirrored into shared_preferences (WB-002): it is read straight from
/// [TokenStorage] only on that fallback path.
///
/// Offline behavior: a fix that cannot be delivered is **queued** in the
/// [LocationOutbox] (store-and-forward) and delivered via `POST
/// /locations/batch` when a later report succeeds — hours later the family's
/// history shows the track through the dead zone instead of a hole. The
/// callbacks are deliberately non-throwing: any failure (missing credentials,
/// network error, stale `ts`, non-monotonic ordering) is captured or skipped
/// without ever surfacing an exception.

/// How long to wait for a single HTTP request before giving up.
const Duration _httpTimeout = Duration(seconds: 15);

/// Top-level liveness callback, invoked by the plugin's native alarm (roughly
/// every 10 minutes) even when no location fixes are produced — the device
/// stationary, GPS deferred by the OS power manager, etc. POSTs a bare
/// heartbeat so the family's "last seen" stays fresh without a location row.
@pragma('vm:entry-point')
Future<void> onHeartbeatTick() async {
  try {
    final _BackgroundCredentials? credentials = await _readCredentials();
    if (credentials == null) return;

    final int? batteryPct = await _readBattery();
    final Map<String, dynamic> body = <String, dynamic>{
      'device_id': credentials.deviceId,
    };
    if (batteryPct != null) body['battery_pct'] = batteryPct;

    await _report(credentials, '/devices/heartbeat', body);
  } catch (_) {
    // Never throw from the background callback.
  }
}

/// Top-level location callback, invoked by the plugin in the background isolate.
///
/// Must be top-level (or a static method) and annotated `@pragma('vm:entry-point')`
/// so the plugin can look it up by callback handle across isolates.
@pragma('vm:entry-point')
Future<void> onLocationUpdate(LocationDto location) async {
  try {
    // Skip spoofed locations (Android mock-location detection).
    if (location.isMocked) return;

    final _BackgroundCredentials? credentials = await _readCredentials();
    if (credentials == null) return;

    final int? batteryPct = await _readBattery();
    final Map<String, dynamic> body =
        _buildBody(location, credentials.deviceId, batteryPct);

    final bool sent = await _report(credentials, '/locations', body);
    if (sent) {
      // Connectivity is alive: opportunistically deliver anything the device
      // queued while it was offline. Bounded so one tick does not flood the
      // radio; subsequent successful reports keep draining.
      await LocationOutbox.drain(
        send: (List<Map<String, dynamic>> batch) =>
            _sendLocationBatch(credentials, batch),
      );
    } else {
      // Offline (or auth hiccup): park the fix for backfill instead of
      // dropping it — the batch endpoint accepts points older than the live
      // feed's 15-minute freshness rule.
      await LocationOutbox.enqueue(body);
    }
  } catch (_) {
    // Never throw from the background callback.
  }
}

/// The credentials the background isolate can see (shared_preferences mirror).
class _BackgroundCredentials {
  const _BackgroundCredentials({
    required this.apiBaseUrl,
    required this.deviceId,
    this.accessToken,
    this.ingestKey,
  });

  final String apiBaseUrl;
  final String deviceId;
  final String? accessToken;
  final String? ingestKey;
}

/// Reads the credential set, requiring the base URL and device id plus at
/// least one usable credential (ingest key or access token).
Future<_BackgroundCredentials?> _readCredentials() async {
  final String? apiBaseUrl = await BackgroundCredentialStore.readApiBaseUrl();
  final String? deviceId = await BackgroundCredentialStore.readDeviceId();
  if (apiBaseUrl == null ||
      apiBaseUrl.isEmpty ||
      deviceId == null ||
      deviceId.isEmpty) {
    return null;
  }
  final String? accessToken =
      await BackgroundCredentialStore.readAccessToken();
  final String? ingestKey = await BackgroundCredentialStore.readIngestKey();
  final bool hasAccess = accessToken != null && accessToken.isNotEmpty;
  final bool hasKey = ingestKey != null && ingestKey.isNotEmpty;
  if (!hasKey && !hasAccess) return null;
  return _BackgroundCredentials(
    apiBaseUrl: apiBaseUrl,
    deviceId: deviceId,
    accessToken: hasAccess ? accessToken : null,
    ingestKey: hasKey ? ingestKey : null,
  );
}

/// Delivers one report (location or heartbeat), trying the ingest key first
/// and falling back to the access-token + refresh path.
///
/// Returns true only when the backend accepted the report (2xx). Any other
/// outcome — network failure, stale `ts` 400, auth dead end — returns false
/// so [onLocationUpdate] can queue the fix for backfill. This function never
/// throws to the caller's catch block for "expected" statuses.
Future<bool> _report(
  _BackgroundCredentials credentials,
  String path,
  Map<String, dynamic> body,
) async {
  final String? ingestKey = credentials.ingestKey;
  if (ingestKey != null) {
    final http.Response response = await _post(
      credentials.apiBaseUrl,
      <String, String>{
        'X-Device-Key': '${credentials.deviceId}.$ingestKey',
        'Content-Type': 'application/json',
      },
      path,
      body,
    );
    // 201 = stored; 200 = stationary-deduped (the server refreshed liveness
    // and skipped the locations row); 204 = heartbeat ack.
    if (response.statusCode == 201 ||
        response.statusCode == 200 ||
        response.statusCode == 204) {
      return true;
    }
    if (response.statusCode != 401 && response.statusCode != 403) {
      // 400 (stale ts / non-monotonic), 5xx, ...: terminal for this update.
      return false;
    }
    // 401/403: key rejected (rotated or the device was re-registered
    // elsewhere). Fall through to the legacy token path when available.
  }

  // Legacy path: the 15-minute access JWT, with a one-shot refresh on 401.
  final String? accessToken = credentials.accessToken;
  if (accessToken == null) return false;
  http.Response response = await _post(
    credentials.apiBaseUrl,
    <String, String>{
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    path,
    body,
  );
  if (response.statusCode == 201 ||
      response.statusCode == 200 ||
      response.statusCode == 204) {
    return true;
  }
  if (response.statusCode == 401) {
    // Access token expired. Refresh and retry once, reading the refresh token
    // straight from secure storage — it is never mirrored to
    // shared_preferences (WB-002), so this fails gracefully when secure
    // storage is unavailable in the background isolate.
    final String? refreshToken = await _readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    final String? newAccess =
        await _refresh(credentials.apiBaseUrl, refreshToken);
    if (newAccess == null) return false; // Refresh failed; foreground re-logs in.
    final http.Response retry = await _post(
      credentials.apiBaseUrl,
      <String, String>{
        'Authorization': 'Bearer $newAccess',
        'Content-Type': 'application/json',
      },
      path,
      body,
    );
    return retry.statusCode == 201 ||
        retry.statusCode == 200 ||
        retry.statusCode == 204;
  }
  // All other statuses: not delivered.
  return false;
}

/// Sends one drained outbox batch to `POST /locations/batch`, ingest key
/// first, with the same Bearer-token fallback as [_report]. Returns true only
/// on 2xx (the endpoint answers with a stored/skipped/rejected summary and is
/// idempotent for retried batches).
Future<bool> _sendLocationBatch(
  _BackgroundCredentials credentials,
  List<Map<String, dynamic>> points,
) async {
  if (points.isEmpty) return true; // Nothing to send.
  final Map<String, dynamic> body = LocationOutbox.batchBody(points);
  final String? ingestKey = credentials.ingestKey;
  if (ingestKey != null) {
    final http.Response response = await _post(
      credentials.apiBaseUrl,
      <String, String>{
        'X-Device-Key': '${credentials.deviceId}.$ingestKey',
        'Content-Type': 'application/json',
      },
      '/locations/batch',
      body,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }
    if (response.statusCode != 401 && response.statusCode != 403) {
      return false;
    }
    // 401/403: fall through to the legacy token path.
  }
  final String? accessToken = credentials.accessToken;
  if (accessToken == null) return false;
  final http.Response response = await _post(
    credentials.apiBaseUrl,
    <String, String>{
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    '/locations/batch',
    body,
  );
  return response.statusCode >= 200 && response.statusCode < 300;
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

/// Builds the `POST /locations` body from a [LocationDto]. The motion state
/// arrives piggybacked on the location payload from the native side — the
/// earlier design read it through shared_preferences, which never worked
/// (native writes the plugin's own prefs file; Dart reads Flutter's), leaving
/// every background row's motion_state empty.
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
    'motion_state': location.motionState,
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

/// POSTs a JSON body to the API with the given headers.
Future<http.Response> _post(
  String apiBaseUrl,
  Map<String, String> headers,
  String path,
  Map<String, dynamic> body,
) {
  return http
      .post(
        Uri.parse('$apiBaseUrl$path'),
        headers: headers,
        body: jsonEncode(body),
      )
      .timeout(_httpTimeout);
}

/// Reads the refresh token from secure storage. Returns null when unavailable
/// (e.g. web, or the method channel is not reachable from the background
/// isolate) so callers treat refresh as impossible rather than crashing.
Future<String?> _readRefreshToken() async {
  try {
    return await TokenStorage.readRefreshToken();
  } catch (_) {
    return null;
  }
}

/// Refreshes the token pair via `POST /auth/refresh`, persisting the new
/// access token to shared_preferences and the full pair best-effort to
/// flutter_secure_storage. Returns the new access token, or null on failure.
///
/// Legacy fallback for installs without an ingest key. The rotated token pair
/// reconciliation with the foreground is unchanged: best-effort secure-storage
/// write plus foreground resume-sync.
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
      // Only the short-lived access token goes there — never the refresh token.
      await BackgroundCredentialStore.saveAccessToken(access);
      // Best-effort persist to secure storage so the foreground app sees the
      // rotated tokens. May fail in the background isolate; the resume-sync
      // fallback covers that case.
      try {
        await TokenStorage.saveTokens(access: access, refresh: refresh);
      } catch (_) {
        // Secure storage unavailable in the background isolate.
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
  /// Tuned for battery: a 60-second interval is far less aggressive than the
  /// foreground reporter's continuous 10-meter stream, while still keeping the
  /// family's view of the user fresh. The distance filter is deliberately zero:
  /// with a displacement filter a stationary device produces no fixes at all,
  /// which would silence both position updates and liveness. The server dedups
  /// stationary points, so periodic fixes cost no storage and keep "last seen"
  /// fresh. While stationary the native side further drops to a slow,
  /// low-power request profile (see ActivityTransitionsManager), and the
  /// native liveness alarm drives [onHeartbeatTick] as a safety net.
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
        heartbeatCallback: onHeartbeatTick,
        androidSettings: const AndroidSettings(
          accuracy: LocationAccuracy.HIGH,
          interval: 60,
          distanceFilter: 0,
          wakeLockTime: 60,
          client: LocationClient.google,
          androidNotificationSettings: AndroidNotificationSettings(
            notificationChannelName: 'OpenFamily',
            notificationTitle: 'OpenFamily',
            notificationMsg: 'Sharing your location with your family',
            notificationBigMsg:
                'OpenFamily is sharing your location in the background so your '
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
