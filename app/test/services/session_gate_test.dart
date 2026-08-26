import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/session_gate.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 8, 26, 12);

  ({String? access, String? refresh}) tokens({String? access, String? refresh}) =>
      (access: access, refresh: refresh);

  /// Builds a syntactically valid JWT-like token with the given epoch-expiry.
  String accessTokenExpiringAt(DateTime expiry) {
    final String header = base64UrlEncode(utf8.encode('{"alg":"HS256"}'));
    final String payload = base64UrlEncode(utf8.encode(jsonEncode(<String,
        dynamic>{
      'exp': expiry.millisecondsSinceEpoch ~/ 1000,
    })));
    return '$header.$payload.signature';
  }

  SessionGate gate({
    SessionTokens stored = (access: null, refresh: null),
    Future<SessionGateRefreshOutcome> Function(String)? onRefresh,
    List<({String access, String refresh})>? saved,
    DateTime? at,
  }) {
    return SessionGate(
      loadTokens: () async => stored,
      postRefresh: onRefresh ??
          (refresh) async => throw StateError('no refresh expected'),
      saveTokens: ({required access, required refresh}) async {
        saved?.add((access: access, refresh: refresh));
      },
      now: () => at ?? now,
    );
  }

  test('no credentials at all is none', () async {
    expect(await gate().evaluate(), SessionGateResult.none);
  });

  test('an unexpired access token is valid without touching the network',
      () async {
    expect(
      await gate(
        stored: tokens(
          access: accessTokenExpiringAt(now.add(const Duration(minutes: 10))),
          refresh: 'refresh-1',
        ),
      ).evaluate(),
      SessionGateResult.valid,
    );
  });

  test('an unexpired access token alone (no refresh) is still valid', () async {
    expect(
      await gate(
        stored: tokens(
          access: accessTokenExpiringAt(now.add(const Duration(minutes: 10))),
        ),
      ).evaluate(),
      SessionGateResult.valid,
    );
  });

  test('the 15-minute-expiry case refreshes instead of wiping', () async {
    final List<({String access, String refresh})> saved =
        <({String access, String refresh})>[];
    final SessionGateResult result = await gate(
      stored: tokens(
        access: accessTokenExpiringAt(now.subtract(const Duration(minutes: 1))),
        refresh: 'refresh-1',
      ),
      onRefresh: (refresh) async {
        expect(refresh, 'refresh-1');
        return const SessionGateRefreshOutcome.ok(
          access: 'access-2',
          refresh: 'refresh-2',
        );
      },
      saved: saved,
    ).evaluate();

    expect(result, SessionGateResult.valid);
    expect(saved, hasLength(1));
    expect(saved.single.access, 'access-2');
    expect(saved.single.refresh, 'refresh-2');
  });

  test('a missing access token also refreshes when a refresh token exists',
      () async {
    expect(
      await gate(
        stored: tokens(refresh: 'refresh-1'),
        onRefresh: (refresh) async => const SessionGateRefreshOutcome.ok(
          access: 'access-2',
          refresh: 'refresh-2',
        ),
      ).evaluate(),
      SessionGateResult.valid,
    );
  });

  test('a rejected refresh is the only path to expired', () async {
    expect(
      await gate(
        stored: tokens(
          access:
              accessTokenExpiringAt(now.subtract(const Duration(minutes: 1))),
          refresh: 'refresh-1',
        ),
        onRefresh: (refresh) async =>
            const SessionGateRefreshOutcome.rejected(),
      ).evaluate(),
      SessionGateResult.expired,
    );
  });

  test('an offline refresh keeps the session (unreachable)', () async {
    expect(
      await gate(
        stored: tokens(
          access:
              accessTokenExpiringAt(now.subtract(const Duration(minutes: 1))),
          refresh: 'refresh-1',
        ),
        onRefresh: (refresh) async =>
            const SessionGateRefreshOutcome.unreachable(),
      ).evaluate(),
      SessionGateResult.unreachable,
    );
  });

  test('a throwing refresh call is treated as unreachable, not expired',
      () async {
    expect(
      await gate(
        stored: tokens(
          access:
              accessTokenExpiringAt(now.subtract(const Duration(minutes: 1))),
          refresh: 'refresh-1',
        ),
        onRefresh: (refresh) async => throw const FormatException('offline'),
      ).evaluate(),
      SessionGateResult.unreachable,
    );
  });

  test('a dead access token with no refresh token is expired', () async {
    expect(
      await gate(
        stored: tokens(
          access:
              accessTokenExpiringAt(now.subtract(const Duration(minutes: 1))),
        ),
      ).evaluate(),
      SessionGateResult.expired,
    );
  });

  test('a malformed access token falls back to refreshing', () async {
    expect(
      await gate(
        stored: tokens(access: 'not-a-jwt', refresh: 'refresh-1'),
        onRefresh: (refresh) async => const SessionGateRefreshOutcome.ok(
          access: 'access-2',
          refresh: 'refresh-2',
        ),
      ).evaluate(),
      SessionGateResult.valid,
    );
  });

  group('jwtExpiryOf', () {
    test('reads a valid exp claim', () {
      final DateTime expiry =
          jwtExpiryOf(accessTokenExpiringAt(now))!.toUtc();
      expect(expiry.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('returns null for malformed tokens', () {
      expect(jwtExpiryOf(''), isNull);
      expect(jwtExpiryOf('a.b'), isNull);
      expect(jwtExpiryOf('a.b.c'), isNull); // payload is not valid base64 JSON
    });
  });
}
