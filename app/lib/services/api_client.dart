import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'server_config.dart';
import 'token_storage.dart';

/// Thrown when the backend returns a non-2xx response.
///
/// [status] is the HTTP status code and [message] is the backend's
/// `{"error": "..."}` body (or a generic fallback when the body is not JSON).
class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'ApiException($status): $message';
}

/// Thrown when the session has expired and cannot be recovered by a token
/// refresh (e.g. the refresh token is missing or expired).
///
/// The app root has already redirected to the login screen via
/// [ApiClient.onSessionExpired] before this is thrown. Callers that run after
/// authentication (e.g. post-auth device registration) should catch this and
/// abort their own navigation rather than proceeding onto a protected screen
/// with cleared tokens.
class SessionExpiredException implements Exception {
  const SessionExpiredException([
    this.message = 'Your session has expired. Please log in again.',
  ]);

  final String message;

  @override
  String toString() => 'SessionExpiredException: $message';
}

/// A thin HTTP client for the Whereabouts backend.
///
/// Every authenticated request injects `Authorization: Bearer <access_token>`
/// from [TokenStorage]. On a 401 it attempts a single token refresh and retries
/// the original request once; if that fails it clears tokens and throws
/// [SessionExpiredException].
class ApiClient {
  ApiClient._();

  static const Duration _timeout = Duration(seconds: 15);

  /// Invoked when a session expires and cannot be recovered by refresh.
  ///
  /// The app root registers a handler here to redirect the user to the login
  /// screen. Tokens (and the device id) are already cleared before this fires.
  static void Function()? onSessionExpired;

  /// Whether the session-expired redirect has already fired for the current
  /// (now-dead) session. Guards against concurrent 401s each firing
  /// [onSessionExpired]. Reset by [markSessionActive] when a new session is
  /// established.
  static bool _sessionExpiredFired = false;

  /// Single-flight guard for token refresh: concurrent 401s share one refresh
  /// call instead of each issuing their own.
  static Future<bool>? _refreshInFlight;

  // ---------------------------------------------------------------------------
  // Typed helpers
  // ---------------------------------------------------------------------------

  /// POST /auth/register → the created user object.
  ///
  /// [inviteCode], when provided, is validated by the server and assigns the
  /// new user to the code's family and role. On a managed server (one with a
  /// configured platform admin) it is required.
  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? inviteCode,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'email': email,
      'password': password,
      'name': name,
    };
    if (inviteCode != null && inviteCode.isNotEmpty) {
      body['invite_code'] = inviteCode;
    }
    final dynamic data = await _send(
      'POST',
      _uri('/auth/register'),
      body: body,
      auth: false,
    );
    return data as Map<String, dynamic>;
  }

  /// POST /family/invites → the created invite code (family admin only).
  static Future<Map<String, dynamic>> createInvite() async {
    final dynamic data = await _send(
      'POST',
      _uri('/family/invites'),
      body: <String, dynamic>{},
    );
    return data as Map<String, dynamic>;
  }

  /// POST /family/join → join a family by invite code.
  static Future<Map<String, dynamic>> joinFamily(String code) async {
    final dynamic data = await _send(
      'POST',
      _uri('/family/join'),
      body: <String, dynamic>{'code': code},
    );
    return data as Map<String, dynamic>;
  }

  /// POST /auth/login → the token pair.
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? totpCode,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (totpCode != null && totpCode.isNotEmpty) {
      body['totp_code'] = totpCode;
    }
    final dynamic data = await _send(
      'POST',
      _uri('/auth/login'),
      body: body,
      auth: false,
    );
    return data as Map<String, dynamic>;
  }

  /// POST /auth/refresh → a fresh token pair.
  static Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final dynamic data = await _send(
      'POST',
      _uri('/auth/refresh'),
      body: <String, dynamic>{'refresh_token': refreshToken},
      auth: false,
    );
    return data as Map<String, dynamic>;
  }

  /// POST /devices → the registered device object.
  static Future<Map<String, dynamic>> registerDevice({
    required String platform,
    required String name,
    String? pushToken,
    String? unifiedpushEndpoint,
    String? appVersion,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'platform': platform,
      'name': name,
    };
    if (pushToken != null) body['push_token'] = pushToken;
    if (unifiedpushEndpoint != null) {
      body['unifiedpush_endpoint'] = unifiedpushEndpoint;
    }
    if (appVersion != null) body['app_version'] = appVersion;
    final dynamic data = await _send('POST', _uri('/devices'), body: body);
    return data as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Generic verbs (for later pieces)
  // ---------------------------------------------------------------------------

  static Future<dynamic> get(String path, {Map<String, String>? query}) {
    return _send('GET', _uri(path, query: query));
  }

  static Future<dynamic> post(String path, {Object? body}) {
    return _send('POST', _uri(path), body: body);
  }

  static Future<dynamic> patch(String path, {Object? body}) {
    return _send('PATCH', _uri(path), body: body);
  }

  static Future<dynamic> delete(String path, {Object? body}) {
    return _send('DELETE', _uri(path), body: body);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Uri _uri(String path, {Map<String, String>? query}) {
    final Uri uri = Uri.parse('${ServerConfig.instance.apiBaseUrl}$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  /// Sends a request, transparently refreshing the access token and retrying
  /// once when the server responds 401.
  static Future<dynamic> _send(
    String method,
    Uri uri, {
    Object? body,
    bool auth = true,
  }) async {
    final http.Response response =
        await _rawSend(method, uri, body: body, auth: auth);

    if (response.statusCode == 401 && auth) {
      final bool refreshed = await _tryRefresh();
      if (refreshed) {
        final http.Response retry =
            await _rawSend(method, uri, body: body, auth: auth);
        if (retry.statusCode == 401) {
          // Refresh succeeded but the retry still 401s: the session is truly
          // dead. Clear the (fresh) tokens and surface the auth failure.
          await TokenStorage.clear();
          _notifySessionExpired();
          throw const SessionExpiredException();
        }
        return _decode(retry);
      }
      _notifySessionExpired();
      throw const SessionExpiredException();
    }

    return _decode(response);
  }

  /// Performs the actual HTTP request with auth headers injected.
  static Future<http.Response> _rawSend(
    String method,
    Uri uri, {
    Object? body,
    bool auth = true,
  }) async {
    if (ServerConfig.instance.apiBaseUrl.isEmpty) {
      throw const ApiException(
        0,
        'Server URL not configured. Enter your Whereabouts server address '
        'in the app settings.',
      );
    }

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final String? token = await TokenStorage.readAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final String? encoded = body == null ? null : jsonEncode(body);

    try {
      switch (method) {
        case 'GET':
          return await http.get(uri, headers: headers).timeout(_timeout);
        case 'POST':
          return await http
              .post(uri, headers: headers, body: encoded)
              .timeout(_timeout);
        case 'PATCH':
          return await http
              .patch(uri, headers: headers, body: encoded)
              .timeout(_timeout);
        case 'DELETE':
          return await http
              .delete(uri, headers: headers, body: encoded)
              .timeout(_timeout);
        default:
          throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
      }
    } on TimeoutException {
      throw const ApiException(0, 'The request timed out. Please try again.');
    } on http.ClientException {
      throw const ApiException(
        0,
        'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Attempts a single token refresh, single-flighted so concurrent 401s share
  /// one refresh call. Returns true and persists the new pair on success;
  /// otherwise clears tokens (and the device id) and returns false.
  static Future<bool> _tryRefresh() {
    final Future<bool>? inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final Future<bool> future = _performRefresh();
    _refreshInFlight = future;
    future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
    return future;
  }

  static Future<bool> _performRefresh() async {
    try {
      final String? refreshToken = await TokenStorage.readRefreshToken();
      if (refreshToken == null) {
        return await _recoverOrClear();
      }
      final http.Response response = await _rawSend(
        'POST',
        _uri('/auth/refresh'),
        body: <String, dynamic>{'refresh_token': refreshToken},
        auth: false,
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        await TokenStorage.saveTokens(
          access: data['access_token'] as String,
          refresh: data['refresh_token'] as String,
        );
        return true;
      }
    } catch (_) {
      // Fall through to recovery below.
    }
    return _recoverOrClear();
  }

  /// Handles a failed foreground refresh.
  ///
  /// The backend rotates refresh tokens, so a foreground refresh can fail with
  /// 401 because the background isolate already used (and rotated) the refresh
  /// token. Before destroying everything, try to recover the tokens the
  /// background wrote to shared_preferences. If found, return true so the
  /// caller retries with the recovered token; otherwise clear and return false.
  static Future<bool> _recoverOrClear() async {
    try {
      await TokenStorage.syncFromBackgroundStore();
      final String? recoveredAccess = await TokenStorage.readAccessToken();
      if (recoveredAccess != null && recoveredAccess.isNotEmpty) {
        // The background isolate refreshed; use its tokens.
        return true;
      }
    } catch (_) {
      // syncFromBackgroundStore or readAccessToken threw (platform-channel
      // failure). Fall through to clear so the session is torn down safely
      // rather than leaving a dead session with no redirect.
    }
    await TokenStorage.clear();
    return false;
  }

  /// Notifies the app root that the session expired so it can redirect to
  /// login. Tokens are cleared by the caller before this fires.
  ///
  /// Fires at most once per session: concurrent 401s all funnel through here,
  /// but only the first triggers the redirect.
  static void _notifySessionExpired() {
    if (_sessionExpiredFired) return;
    _sessionExpiredFired = true;
    onSessionExpired?.call();
  }

  /// Marks a fresh session as active, re-arming the session-expired redirect
  /// so a later expiry fires [onSessionExpired] again.
  static void markSessionActive() {
    _sessionExpiredFired = false;
  }

  /// Whether a valid (non-expired) session is stored, for the app's session
  /// gate. Checks that both tokens are present and that the access token's JWT
  /// `exp` claim is still in the future, so an expired-but-present token does
  /// not route the user onto a protected screen.
  static Future<bool> hasValidSession() async {
    final String? access = await TokenStorage.readAccessToken();
    final String? refresh = await TokenStorage.readRefreshToken();
    if (access == null || access.isEmpty) return false;
    if (refresh == null || refresh.isEmpty) return false;
    final DateTime? expiry = _jwtExpiry(access);
    return expiry != null && expiry.isAfter(DateTime.now().toUtc());
  }

  /// Decodes a JWT's `exp` claim (seconds since epoch) into a UTC [DateTime],
  /// or null if the token is malformed or has no `exp`.
  static DateTime? _jwtExpiry(String token) {
    final List<String> parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final String payload = parts[1];
      final String normalized =
          payload.replaceAll('-', '+').replaceAll('_', '/');
      final String padded = normalized.padRight(
        ((normalized.length + 3) ~/ 4) * 4,
        '=',
      );
      final List<int> bytes = base64Decode(padded);
      final dynamic decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final dynamic exp = decoded['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        (exp * 1000).round(),
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decodes a response body, throwing [ApiException] on non-2xx statuses.
  static dynamic _decode(http.Response response) {
    final String body = response.body;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body.isEmpty) return null;
      return jsonDecode(body);
    }

    String message = 'Request failed (${response.statusCode}).';
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } catch (_) {
      // Non-JSON error body; keep the generic message.
    }
    throw ApiException(response.statusCode, message);
  }
}
