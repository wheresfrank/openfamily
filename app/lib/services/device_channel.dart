import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A notification or command the server pushed over the device channel.
class DevicePushFrame {
  const DevicePushFrame({
    required this.title,
    required this.body,
    this.id,
    this.silent = false,
  });

  /// Server id of a stored notification, acknowledged once handled. Null for
  /// ephemeral messages such as location requests.
  final int? id;
  final String title;
  final String body;
  final bool silent;

  /// Parses a `push` frame; returns null for anything else.
  static DevicePushFrame? tryParse(Object? raw) {
    if (raw is! String) return null;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'push') {
        return null;
      }
      final Object? id = decoded['id'];
      return DevicePushFrame(
        id: id is int && id > 0 ? id : null,
        title: decoded['title'] as String? ?? '',
        body: decoded['body'] as String? ?? '',
        silent: decoded['silent'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the channel needs to authenticate: the server and the device's
/// ingest key. Readable from any isolate (see `BackgroundCredentialStore`).
class ChannelCredentials {
  const ChannelCredentials({
    required this.apiBaseUrl,
    required this.deviceId,
    required this.ingestKey,
  });

  final String apiBaseUrl;
  final String deviceId;
  final String ingestKey;
}

/// The minimal WebSocket surface the channel uses, so tests can fake it.
abstract class ChannelSocket {
  Stream<Object?> get messages;
  void send(String data);

  /// The close code the peer ended the connection with, once closed.
  int? get closeCode;
  Future<void> close();
}

typedef ChannelConnector = Future<ChannelSocket> Function(
  Uri uri,
  Map<String, String> headers,
);

class _IoChannelSocket implements ChannelSocket {
  _IoChannelSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  void send(String data) => _socket.add(data);

  @override
  int? get closeCode => _socket.closeCode;

  @override
  Future<void> close() => _socket.close();
}

Future<ChannelSocket> _connectIo(Uri uri, Map<String, String> headers) async {
  final WebSocket socket = await WebSocket.connect(
    uri.toString(),
    headers: headers,
  );
  return _IoChannelSocket(socket);
}

/// Remembers which notification ids were already shown, shared by every
/// isolate through shared_preferences, so a replay after a reconnect (or a
/// second connection) never shows the same alert twice.
class SeenNotifications {
  SeenNotifications._();

  static const String _key = 'device_channel_seen_ids';
  static const int _max = 100;

  /// Records [id]; returns false when it had already been seen.
  static Future<bool> markSeen(int id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final List<String> ids = prefs.getStringList(_key) ?? <String>[];
    final String value = id.toString();
    if (ids.contains(value)) return false;
    await prefs.setStringList(
      _key,
      <String>[value, ...ids].take(_max).toList(growable: false),
    );
    return true;
  }
}

/// A long-lived, authenticated WebSocket to `GET /ws/device` that delivers
/// notifications and commands from the server without any external push app.
///
/// It reconnects with backoff, keeps the link alive with pings, acknowledges
/// stored notifications, and stops by itself when there are no credentials
/// (logged out). The same class runs in the app's main isolate and in the
/// background location service's isolate; only one of them should run at a
/// time (the server replaces older connections of the same device).
class DeviceChannel {
  DeviceChannel({
    required this.readCredentials,
    required this.onPush,
    ChannelConnector? connector,
    this.pingInterval = const Duration(seconds: 25),
    this.silenceTimeout = const Duration(seconds: 75),
    this.replacedBackoff = const Duration(minutes: 5),
    this.mayConnect,
    Duration Function(int attempt)? backoff,
    Random? random,
  })  : _connector = connector ?? _connectIo,
        _backoff = backoff ?? defaultBackoff,
        _random = random ?? Random();

  /// Close code the server uses when a newer connection replaced this one.
  static const int replacedCloseCode = 4001;

  final Future<ChannelCredentials?> Function() readCredentials;
  final Future<void> Function(DevicePushFrame frame) onPush;
  final Duration pingInterval;
  final Duration silenceTimeout;
  final Duration replacedBackoff;

  /// Checked before every connection attempt. Returning false (for example
  /// because another isolate owns the connection) waits [replacedBackoff] and
  /// asks again instead of connecting.
  final Future<bool> Function()? mayConnect;
  final ChannelConnector _connector;
  final Duration Function(int attempt) _backoff;
  final Random _random;

  bool _running = false;
  ChannelSocket? _socket;

  bool get isRunning => _running;
  bool get isConnected => _socket != null;

  /// 2s, 4s, 8s … capped at one minute, with up to 20% jitter.
  static Duration defaultBackoff(int attempt) {
    final int seconds = min(60, 2 << min(attempt, 5));
    return Duration(milliseconds: (seconds * 1000 * (1 + Random().nextDouble() * 0.2)).round());
  }

  /// `https://host` becomes `wss://host/ws/device` (and http becomes ws).
  static Uri? channelUri(String apiBaseUrl) {
    final Uri? base = Uri.tryParse(apiBaseUrl);
    if (base == null || !base.hasAuthority) return null;
    final String scheme = base.scheme == 'https' ? 'wss' : 'ws';
    if (base.scheme != 'https' && base.scheme != 'http') return null;
    final String basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(scheme: scheme, path: '$basePath/ws/device');
  }

  /// Starts the connection loop. Safe to call repeatedly.
  void start() {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  /// Stops the loop and closes the connection.
  Future<void> stop() async {
    _running = false;
    final ChannelSocket? socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } catch (_) {}
  }

  Future<void> _run() async {
    int attempt = 0;
    while (_running) {
      final ChannelCredentials? credentials = await readCredentials();
      final Uri? uri =
          credentials == null ? null : channelUri(credentials.apiBaseUrl);
      if (credentials == null || uri == null) {
        // Logged out (or not configured): nothing to connect to. The next
        // start() call picks it up again.
        _running = false;
        return;
      }
      final Future<bool> Function()? gate = mayConnect;
      if (gate != null && !await gate()) {
        await Future<void>.delayed(replacedBackoff);
        continue;
      }
      bool replaced = false;
      try {
        final ChannelSocket socket = await _connector(uri, <String, String>{
          'X-Device-Key': '${credentials.deviceId}.${credentials.ingestKey}',
        }).timeout(const Duration(seconds: 15));
        if (!_running) {
          await socket.close();
          return;
        }
        _socket = socket;
        attempt = 0;
        await _serve(socket);
        replaced = socket.closeCode == replacedCloseCode;
      } catch (_) {
        // Fall through to the backoff below.
      } finally {
        _socket = null;
      }
      if (!_running) return;
      final Duration wait = replaced
          ? replacedBackoff + Duration(seconds: _random.nextInt(30))
          : _backoff(attempt++);
      await Future<void>.delayed(wait);
    }
  }

  Future<void> _serve(ChannelSocket socket) async {
    DateTime lastReceived = DateTime.now();
    final Timer keepAlive = Timer.periodic(pingInterval, (Timer _) {
      if (DateTime.now().difference(lastReceived) > silenceTimeout) {
        // No pong for too long: the link is dead without a FIN. Closing makes
        // the message stream end so the loop reconnects.
        unawaited(socket.close());
        return;
      }
      try {
        socket.send('{"type":"ping"}');
      } catch (_) {}
    });
    try {
      await for (final Object? message in socket.messages) {
        lastReceived = DateTime.now();
        final DevicePushFrame? frame = DevicePushFrame.tryParse(message);
        if (frame == null) continue;
        await _handle(socket, frame);
      }
    } finally {
      keepAlive.cancel();
    }
  }

  Future<void> _handle(ChannelSocket socket, DevicePushFrame frame) async {
    final int? id = frame.id;
    // Stored notifications are replayed until acknowledged, so skip ones this
    // device already handled but could not acknowledge before a disconnect.
    final bool fresh = id == null || await SeenNotifications.markSeen(id);
    if (fresh) {
      try {
        await onPush(frame);
      } catch (_) {
        // A handler failure must not tear down the channel.
      }
    }
    if (id != null) {
      try {
        socket.send(jsonEncode(<String, Object>{'type': 'ack', 'id': id}));
      } catch (_) {}
    }
  }
}
