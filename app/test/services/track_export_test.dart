import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/history_service.dart';

void main() {
  test('track formats map to the server format names and file types', () {
    expect(TrackFormat.gpx.name, 'gpx');
    expect(TrackFormat.gpx.extension, 'gpx');
    expect(TrackFormat.gpx.mimeType, 'application/gpx+xml');
    expect(TrackFormat.geojson.name, 'geojson');
    expect(TrackFormat.geojson.extension, 'geojson');
    expect(TrackFormat.geojson.mimeType, 'application/geo+json');
  });
}
