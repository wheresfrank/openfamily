import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/device_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSocket implements ChannelSocket {
  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<String> sent = <String>[];
  @override
  int? closeCode;
  bool closed = false;

  @override
  Stream<Object?> get messages => incoming.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!incoming.isClosed) await incoming.close();
  }
}

const ChannelCredentials creds = ChannelCredentials(
  apiBaseUrl: 'https://family.example.com',
  deviceId: 'dev1',
  ingestKey: 'key',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('channelUri', () {
    test('maps https to wss and appends the path', () {
      expect(
        DeviceChannel.channelUri('https://family.example.com').toString(),
        'wss://family.example.com/ws/device',
      );
      expect(
        DeviceChannel.channelUri('https://example.com/openfamily/').toString(),
        'wss://example.com/openfamily/ws/device',
      );
      expect(
        DeviceChannel.channelUri('http://10.0.0.5:8080').toString(),
        'ws://10.0.0.5:8080/ws/device',
      );
    });

    test('rejects values that are not http(s) URLs', () {
      expect(DeviceChannel.channelUri(''), isNull);
      expect(DeviceChannel.channelUri('ftp://example.com'), isNull);
    });
  });

  group('DevicePushFrame.tryParse', () {
    test('reads stored and ephemeral frames', () {
      final DevicePushFrame stored = DevicePushFrame.tryParse(
        '{"type":"push","id":7,"title":"SOS","body":"Mom needs help"}',
      )!;
      expect(stored.id, 7);
      expect(stored.title, 'SOS');
      final DevicePushFrame ephemeral = DevicePushFrame.tryParse(
        '{"type":"push","title":"","body":"{}"}',
      )!;
      expect(ephemeral.id, isNull);
    });

    test('ignores other frames and garbage', () {
      expect(DevicePushFrame.tryParse('{"type":"hello"}'), isNull);
      expect(DevicePushFrame.tryParse('not json'), isNull);
      expect(DevicePushFrame.tryParse(42), isNull);
    });
  });

  test('delivers a frame, acknowledges it once and skips replays', () async {
    final FakeSocket socket = FakeSocket();
    final List<DevicePushFrame> received = <DevicePushFrame>[];
    Map<String, String>? usedHeaders;
    Uri? usedUri;
    final DeviceChannel channel = DeviceChannel(
      readCredentials: () async => creds,
      onPush: (DevicePushFrame f) async => received.add(f),
      connector: (Uri uri, Map<String, String> headers) async {
        usedUri = uri;
        usedHeaders = headers;
        return socket;
      },
    )..start();

    socket.incoming
      ..add('{"type":"hello"}')
      ..add('{"type":"push","id":5,"title":"A","body":"B"}')
      ..add('{"type":"push","id":5,"title":"A","body":"B"}');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(usedUri.toString(), 'wss://family.example.com/ws/device');
    expect(usedHeaders, <String, String>{'X-Device-Key': 'dev1.key'});
    expect(received, hasLength(1));
    expect(received.single.title, 'A');
    // Both copies are acknowledged so the server stops replaying.
    expect(
      socket.sent.where((String s) => jsonDecode(s)['type'] == 'ack'),
      hasLength(2),
    );
    await channel.stop();
    expect(socket.closed, isTrue);
  });

  test('ephemeral frames are delivered without an ack', () async {
    final FakeSocket socket = FakeSocket();
    final List<DevicePushFrame> received = <DevicePushFrame>[];
    final DeviceChannel channel = DeviceChannel(
      readCredentials: () async => creds,
      onPush: (DevicePushFrame f) async => received.add(f),
      connector: (Uri uri, Map<String, String> headers) async => socket,
    )..start();
    socket.incoming.add('{"type":"push","title":"","body":"cmd"}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received.single.body, 'cmd');
    expect(socket.sent.where((String s) => s.contains('ack')), isEmpty);
    await channel.stop();
  });

  test('a failing handler does not break the channel', () async {
    final FakeSocket socket = FakeSocket();
    int calls = 0;
    final DeviceChannel channel = DeviceChannel(
      readCredentials: () async => creds,
      onPush: (DevicePushFrame f) async {
        calls++;
        throw StateError('boom');
      },
      connector: (Uri uri, Map<String, String> headers) async => socket,
    )..start();
    socket.incoming
      ..add('{"type":"push","id":1,"title":"","body":"a"}')
      ..add('{"type":"push","id":2,"title":"","body":"b"}');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(calls, 2);
    expect(channel.isConnected, isTrue);
    await channel.stop();
  });

  test('stops by itself when logged out', () async {
    int connects = 0;
    final DeviceChannel channel = DeviceChannel(
      readCredentials: () async => null,
      onPush: (DevicePushFrame f) async {},
      connector: (Uri uri, Map<String, String> headers) async {
        connects++;
        return FakeSocket();
      },
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(connects, 0);
    expect(channel.isRunning, isFalse);
  });

  test('reconnects with backoff after the socket drops', () async {
    final List<FakeSocket> sockets = <FakeSocket>[];
    final DeviceChannel channel = DeviceChannel(
      readCredentials: () async => creds,
      onPush: (DevicePushFrame f) async {},
      backoff: (int attempt) => const Duration(milliseconds: 20),
      connector: (Uri uri, Map<String, String> headers) async {
        final FakeSocket socket = FakeSocket();
        sockets.add(socket);
        return socket;
      },
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sockets.first.incoming.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(sockets.length, greaterThanOrEqualTo(2));
    await channel.stop();
  });

  test('waits much longer before reconnecting after being replaced', () async {
    final List<FakeSocket> sockets = <FakeSocket>[];
    final DeviceChannel channel = DeviceChannel(
      readCredentials: () async => creds,
      onPush: (DevicePushFrame f) async {},
      backoff: (int attempt) => const Duration(milliseconds: 10),
      replacedBackoff: const Duration(minutes: 5),
      connector: (Uri uri, Map<String, String> headers) async {
        final FakeSocket socket = FakeSocket();
        sockets.add(socket);
        return socket;
      },
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    sockets.first.closeCode = DeviceChannel.replacedCloseCode;
    await sockets.first.incoming.close();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(sockets.length, 1, reason: 'must not reconnect right away');
    await channel.stop();
  });

  test('does not connect while another owner holds the channel', () async {
    int connects = 0;
    bool allowed = false;
    final DeviceChannel channel = DeviceChannel(
      readCredentials: () async => creds,
      onPush: (DevicePushFrame f) async {},
      mayConnect: () async => allowed,
      replacedBackoff: const Duration(milliseconds: 30),
      connector: (Uri uri, Map<String, String> headers) async {
        connects++;
        return FakeSocket();
      },
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(connects, 0);
    allowed = true;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(connects, 1);
    await channel.stop();
  });
}
