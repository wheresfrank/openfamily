import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/server_features.dart';
import 'package:openfamily/services/traffic_tiles.dart';

// A valid 1x1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  test('traffic tiles come from the server, never from the provider', () {
    const ApiTileImage image = ApiTileImage(z: 12, x: 2044, y: 1360);
    expect(image.path, '/traffic/tiles/12/2044/1360');
    expect(image, const ApiTileImage(z: 12, x: 2044, y: 1360));
    expect(image == const ApiTileImage(z: 12, x: 2044, y: 1361), isFalse);
    expect(
      const ApiTileImage(z: 11, x: 1022, y: 680, size: 512).path,
      '/traffic/tiles/11/1022/680?size=512',
    );
    expect(
      const ApiTileImage(z: 11, x: 1022, y: 680, size: 512) ==
          const ApiTileImage(z: 11, x: 1022, y: 680),
      isFalse,
    );
  });

  testWidgets('a tile is fetched through the injected fetcher and decoded',
      (WidgetTester tester) async {
    final List<String> requested = <String>[];
    final ApiTileImage image = ApiTileImage(
      z: 3,
      x: 4,
      y: 5,
      fetch: (String path) async {
        requested.add(path);
        return _png;
      },
    );
    final ImageStream stream = image.resolve(ImageConfiguration.empty);
    bool loaded = false;
    stream.addListener(ImageStreamListener((ImageInfo info, bool _) {
      loaded = true;
    }));
    await tester.runAsync(() async {
      for (int i = 0; i < 50 && !loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(requested, <String>['/traffic/tiles/3/4/5']);
    expect(loaded, isTrue);
  });

  group('ServerFeatures.trafficEnabled', () {
    test('follows traffic_enabled from /config', () {
      ServerFeatures.instance.apply(<String, dynamic>{'traffic_enabled': true});
      expect(ServerFeatures.instance.trafficEnabled, isTrue);
      ServerFeatures.instance.apply(<String, dynamic>{'traffic_enabled': false});
      expect(ServerFeatures.instance.trafficEnabled, isFalse);
    });

    test('servers that predate the field report no traffic', () {
      ServerFeatures.instance.apply(<String, dynamic>{'traffic_enabled': true});
      ServerFeatures.instance.apply(<String, dynamic>{'sms_configured': true});
      expect(ServerFeatures.instance.trafficEnabled, isFalse);
    });
  });
}
