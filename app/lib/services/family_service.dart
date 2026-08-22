import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/member.dart';
import 'api_client.dart';
import 'member_avatar_cache.dart';
import 'member_mapper.dart';
import 'server_config.dart';
import 'token_storage.dart';

/// The caller's family summary from `GET /family`.
class FamilyInfo {
  const FamilyInfo({
    required this.name,
    required this.role,
    required this.userId,
  });

  final String name;

  /// The caller's role: "admin", "member", or "child".
  final String role;

  /// The caller's own user id.
  final String userId;
}

/// Fetches the family + members over REST and streams live location and avatar
/// metadata updates over the `/ws/stream` WebSocket.
///
/// Usage:
/// ```dart
/// final service = FamilyService(
///   onMembersChanged: (members) => setState(() => _members = members),
///   onUserId: (id) => setState(() => _userId = id),
/// );
/// final name = await service.fetchFamilyName();
/// final members = await service.fetchMembers();
/// await service.start(); // opens the WebSocket
/// // ... later:
/// service.dispose();
/// ```
///
/// The WebSocket authenticates by carrying the access token as the
/// `Sec-WebSocket-Protocol` subprotocol (never in the URL). On error/close it
/// reconnects with exponential backoff (1s → 2s → 4s … capped at 30s) and
/// re-fetches members so a missed `members` frame is recovered.
class FamilyService {
  FamilyService({this.onMembersChanged, this.onUserId});

  /// Fired whenever the member list is replaced or a member is updated.
  void Function(List<Member> members)? onMembersChanged;

  /// Fired once the `welcome` frame identifies the caller's own user id.
  void Function(String userId)? onUserId;

  List<Member> _members = <Member>[];
  String? _userId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _stalenessTimer;
  bool _disposed = false;
  int _attempt = 0;

  /// The caller's own user id (from the `welcome` frame), or null until known.
  String? get userId => _userId;

  /// The current member list (live-updated).
  List<Member> get members => List<Member>.unmodifiable(_members);

  /// `GET /family` → the family name.
  Future<String> fetchFamilyName() async {
    final FamilyInfo info = await fetchFamily();
    return info.name;
  }

  /// `GET /family` → the caller's family summary (name, role, user id).
  Future<FamilyInfo> fetchFamily() async {
    final dynamic data = await ApiClient.get('/family');
    final Map<String, dynamic> map = data as Map<String, dynamic>;
    return FamilyInfo(
      name: map['name'] as String? ?? 'Family',
      role: map['role'] as String? ?? 'member',
      userId: map['user_id'] as String? ?? '',
    );
  }

  /// `GET /family/members` → the mapped member list.
  ///
  /// Also populates the internal [_members] list so a `location` frame that
  /// arrives between this fetch and the WebSocket `members` snapshot is not
  /// dropped (it can be matched against the freshly fetched members).
  Future<List<Member>> fetchMembers() async {
    final dynamic data = await ApiClient.get('/family/members');
    final List<dynamic> list = data as List<dynamic>;
    final List<Member> mapped = list
        .map((dynamic e) => memberFromJson(e as Map<String, dynamic>))
        .toList();
    return _replaceMembers(mapped);
  }

  /// Opens the WebSocket and begins streaming live updates.
  Future<void> start() async {
    _disposed = false;
    _attempt = 0;
    _startStalenessTimer();
    await _connect();
  }

  /// Periodically re-evaluates each member's staleness so a member whose
  /// updates stop (phone off / no signal) transitions to the grey "stopped"
  /// status even though no `location` frame arrives for them.
  void _startStalenessTimer() {
    _stalenessTimer?.cancel();
    _stalenessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed || _members.isEmpty) return;
      final List<Member> refreshed = _members.map(refreshStaleness).toList();
      var changed = false;
      for (int i = 0; i < _members.length; i++) {
        if (!identical(refreshed[i], _members[i])) {
          changed = true;
          break;
        }
      }
      if (changed) {
        _members = refreshed;
        onMembersChanged?.call(_members);
      }
    });
  }

  Future<void> _connect() async {
    if (_disposed) return;

    final String? token = await TokenStorage.readAccessToken();
    if (token == null) {
      // No session: ApiClient.onSessionExpired handles the redirect. Nothing
      // to stream without a token.
      return;
    }

    final WebSocketChannel channel =
        WebSocketChannel.connect(_wsUri(), protocols: <String>[token]);
    _channel = channel;
    _subscription = channel.stream.listen(
      _onFrame,
      onError: (Object _) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return; // Ignore malformed frames.
    }

    switch (map['type']) {
      case 'welcome':
        final String? id = map['user_id'] as String?;
        if (id != null) {
          _userId = id;
          onUserId?.call(id);
        }
        break;
      case 'members':
        final List<dynamic> list =
            (map['members'] as List<dynamic>?) ?? const [];
        final List<Member> mapped = list
            .map((dynamic e) => memberFromJson(e as Map<String, dynamic>))
            .toList();
        _replaceMembers(mapped);
        _attempt = 0; // Successful connection — reset reconnect backoff.
        onMembersChanged?.call(_members);
        break;
      case 'location':
        _applyLocation(map);
        break;
      case 'avatar':
        _applyAvatar(map);
        break;
    }
  }

  void _applyLocation(Map<String, dynamic> map) {
    final String? id = map['user_id'] as String?;
    if (id == null) return;
    final int index = _members.indexWhere((Member m) => m.id == id);
    if (index < 0) return;
    _members[index] = memberFromLocationUpdate(_members[index], map);
    onMembersChanged?.call(_members);
  }

  /// Applies an `avatar` metadata frame and clears the old private image bytes
  /// so visible avatar widgets fetch the replacement immediately.
  void _applyAvatar(Map<String, dynamic> map) {
    final String? id = map['user_id'] as String?;
    if (id == null) return;
    final int index = _members.indexWhere((Member m) => m.id == id);
    if (index < 0) return;

    final Member updated = memberFromAvatarUpdate(_members[index], map);
    if (identical(updated, _members[index])) return;

    MemberAvatarCache.instance.invalidate(id);
    _members[index] = updated;
    onMembersChanged?.call(_members);
  }

  /// Replaces the member snapshot while releasing private image bytes for
  /// changed or removed avatar metadata.
  ///
  /// A REST response or `members` WebSocket snapshot can arrive after a newer
  /// avatar frame. Preserve the highest known durable revision in that case so
  /// an older snapshot never makes a fresh photo disappear or reappear.
  List<Member> _replaceMembers(List<Member> incoming) {
    final Map<String, Member> previousById = <String, Member>{
      for (final Member member in _members) member.id: member,
    };
    final Set<String> incomingIds = incoming
        .map((Member member) => member.id)
        .where((String id) => id.isNotEmpty)
        .toSet();

    for (final Member previous in _members) {
      if (previous.id.isNotEmpty && !incomingIds.contains(previous.id)) {
        MemberAvatarCache.instance.invalidate(previous.id);
      }
    }

    final List<Member> reconciled = incoming.map((Member candidate) {
      final Member? previous = previousById[candidate.id];
      if (previous == null) return candidate;

      // The version changes atomically with every avatar upload/removal. A
      // snapshot at the same or a lower revision cannot authoritatively change
      // avatar metadata, so retain the newest metadata already observed.
      final Member next = candidate.avatarVersion <= previous.avatarVersion
          ? candidate.copyWithAvatar(
              hasAvatar: previous.hasAvatar,
              avatarUpdatedAt: previous.avatarUpdatedAt,
              avatarVersion: previous.avatarVersion,
            )
          : candidate;

      if (_avatarMetadataChanged(previous, next) && previous.id.isNotEmpty) {
        MemberAvatarCache.instance.invalidate(previous.id);
      }
      return next;
    }).toList();

    _members = reconciled;
    return _members;
  }

  bool _avatarMetadataChanged(Member before, Member after) {
    return before.hasAvatar != after.hasAvatar ||
        before.avatarVersion != after.avatarVersion ||
        before.avatarUpdatedAt != after.avatarUpdatedAt;
  }

  /// Schedules a reconnect with exponential backoff, re-fetching members first
  /// so any missed `members` frame is recovered.
  void _scheduleReconnect() {
    if (_disposed) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff(), () async {
      if (_disposed) return;
      try {
        await fetchMembers();
        onMembersChanged?.call(_members);
      } catch (_) {
        // Keep the previous members; the next reconnect will retry the fetch.
      }
      await _connect();
    });
  }

  /// 1s → 2s → 4s → 8s → 16s → 30s (capped).
  Duration _backoff() {
    final int exp = _attempt < 5 ? _attempt : 5;
    _attempt++;
    final int seconds = math.min(1 << exp, 30);
    return Duration(seconds: seconds);
  }

  /// Derives the WebSocket URL from the configured API base URL by swapping
  /// the scheme (https→wss, http→ws) and appending `/ws/stream`.
  Uri _wsUri() {
    final Uri base = Uri.parse(ServerConfig.instance.apiBaseUrl);
    final String scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme, path: '/ws/stream');
  }

  /// Closes the WebSocket and cancels any pending reconnect + staleness timer.
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _stalenessTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    MemberAvatarCache.instance.clear();
  }
}
