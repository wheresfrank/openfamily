import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/tile_config.dart';

void main() {
  setUp(TileConfig.instance.resetToDefaults);

  test('starts on public OSM and Esri defaults', () {
    expect(TileConfig.instance.streetUrl, kDefaultStreetTileUrl);
    expect(TileConfig.instance.satelliteUrl, kDefaultSatelliteTileUrl);
  });

  test('resetToDefaults restores the public hosts', () {
    TileConfig.instance.streetUrl = 'https://tiles.example.com/{z}/{x}/{y}.png';
    TileConfig.instance.resetToDefaults();
    expect(TileConfig.instance.streetUrl, kDefaultStreetTileUrl);
  });
}
