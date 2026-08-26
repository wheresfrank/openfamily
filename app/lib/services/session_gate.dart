import 'dart:convert';

/// Startup session check: decides whether the locally stored credentials still
/// represent a live session WITHOUT ever destroying the session on a hunch.
///
/// Rationale (production incident): the previous gate
/// (`ApiClient.hasValidSession`) treated an expired 15-minute access JWT as
/// "no session" and wiped access token, refresh token, device id, and the
/// biometric-unlock opt-in on every app open — even though the 30-day refresh
/// token was still perfectly valid. Users were forced through a full password
/// login at almost every open.
///
/// The policy here instead:
///  - an unexpired access token is a valid session;
///  - an expired/missing access token with a refresh token triggers ONE
///    refresh attempt: success or a transport/server failure keeps the
///    session, only a definitive 401/403 rejection ends it;
///  - offline or server-error opens never log the user out.
enum SessionGateResult {
  /// Credentials are usable right now (fresh access token, possibly after a
  /// just-completed refresh).
  valid,

  /// The server definitively rejected the refresh token (401/403), or only a
  /// dead access token remains. The caller should clear the local session.
  expired,

  /// A refresh was needed but the server could not confirm it (offline,
  /// timeout, 5xx). The session is presumptively kept.
  unreachable,

  /// No credentials are stored at all.
  none,
}

/// The stored token pair as read from token storage.
typedef SessionTokens = ({String? access, String? refresh});

/// What the refresh endpoint answered. [ok] carries the rotated pair,
/// [rejected] is a definitive auth failure (401/403), and [unreachable]
/// covers every other outcome (network, timeout, 5xx, malformed body) — all
/// of which must NOT destroy the session.
enum SessionGateRefreshStatus { ok, rejected, unreachable }

class SessionGateRefreshOutcome {
  const SessionGateRefreshOutcome.ok({
    required this.access,
    required this.refresh,
  }) : status = SessionGateRefreshStatus.ok;

  const SessionGateRefreshOutcome.rejected()
      : status = SessionGateRefreshStatus.rejected,
        access = null,
        refresh = null;

  const SessionGateRefreshOutcome.unreachable()
      : status = SessionGateRefreshStatus.unreachable,
        access = null,
        refresh = null;

  final SessionGateRefreshStatus status;
  final String? access;
  final String? refresh;
}

/// Decides the session's fate with injectable IO so the policy is unit-testable
/// without platform channels or a live server.
class SessionGate {
  SessionGate({
    required Future<SessionTokens> Function() loadTokens,
    required Future<SessionGateRefreshOutcome> Function(String refreshToken)
        postRefresh,
    required Future<void> Function({
      required String access,
      required String refresh,
    }) saveTokens,
    DateTime Function()? now,
  })  : _loadTokens = loadTokens,
        _postRefresh = postRefresh,
        _saveTokens = saveTokens,
        _now = now ?? (() => DateTime.now().toUtc());

  final Future<SessionTokens> Function() _loadTokens;
  final Future<SessionGateRefreshOutcome> Function(String refreshToken)
      _postRefresh;
  final Future<void> Function({
    required String access,
    required String refresh,
  }) _saveTokens;
  final DateTime Function() _now;

  Future<SessionGateResult> evaluate() async {
    final SessionTokens tokens = await _loadTokens();
    final String? access = tokens.access;
    final String? refresh = tokens.refresh;

    if ((access == null || access.isEmpty) &&
        (refresh == null || refresh.isEmpty)) {
      return SessionGateResult.none;
    }

    if (access != null && access.isNotEmpty) {
      final DateTime? expiry = jwtExpiryOf(access);
      if (expiry != null && expiry.isAfter(_now())) {
        // Unexpired access token: usable session regardless of refresh state.
        return SessionGateResult.valid;
      }
    }

    // Access is expired or missing. Without a refresh token the session is
    // unrecoverable locally.
    if (refresh == null || refresh.isEmpty) return SessionGateResult.expired;

    SessionGateRefreshOutcome outcome;
    try {
      outcome = await _postRefresh(refresh);
    } catch (_) {
      // The IO layer is expected to classify failures itself, but a throwing
      // transport must never destroy the session.
      outcome = const SessionGateRefreshOutcome.unreachable();
    }
    switch (outcome.status) {
      case SessionGateRefreshStatus.ok:
        await _saveTokens(
          access: outcome.access!,
          refresh: outcome.refresh!,
        );
        return SessionGateResult.valid;
      case SessionGateRefreshStatus.rejected:
        return SessionGateResult.expired;
      case SessionGateRefreshStatus.unreachable:
        return SessionGateResult.unreachable;
    }
  }
}

/// Decodes a JWT's `exp` claim (seconds since epoch) into a UTC [DateTime], or
/// null when the token is malformed or has no usable `exp`.
DateTime? jwtExpiryOf(String token) {
  final List<String> parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final String payload = parts[1];
    final String normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
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
