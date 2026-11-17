import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'api_client.dart';

/// URL template given to the traffic [TileLayer]. It is never requested
/// directly; [ApiTileProvider] ignores it and asks the OpenFamily server.
const String kTrafficTileTemplate = 'traffic/{z}/{x}/{y}';

/// Downloads one tile's bytes. Injectable so tests need no server.
typedef TileFetcher = Future<Uint8List> Function(String path);

Future<Uint8List> _fetchFromServer(String path) => ApiClient.getBytes(path);

/// Loads map tiles from the OpenFamily server (GET /traffic/tiles/z/x/y), with
/// the app's normal sign-in and token refresh, so the traffic provider's key
/// never reaches the phone.
class ApiTileProvider extends TileProvider {
  ApiTileProvider({this.fetch = _fetchFromServer});

  final TileFetcher fetch;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return ApiTileImage(
      // The layer's zoom offset lets 512 px tiles cover the same area as 256 px
      // tiles one level up, so the server is asked for the matching level.
      z: coordinates.z + options.zoomOffset.round(),
      x: coordinates.x,
      y: coordinates.y,
      size: options.tileSize.round() >= 512 ? 512 : 256,
      fetch: fetch,
    );
  }
}

/// An [ImageProvider] for one server-hosted tile.
@immutable
class ApiTileImage extends ImageProvider<ApiTileImage> {
  const ApiTileImage({
    required this.z,
    required this.x,
    required this.y,
    this.size = 256,
    this.fetch = _fetchFromServer,
  });

  final int z;
  final int x;
  final int y;

  /// Tile edge in pixels (256 or 512).
  final int size;
  final TileFetcher fetch;

  String get path =>
      '/traffic/tiles/$z/$x/$y${size == 256 ? '' : '?size=$size'}';

  @override
  Future<ApiTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ApiTileImage>(this);

  @override
  ImageStreamCompleter loadImage(ApiTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: path,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final Uint8List bytes = await fetch(path);
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is ApiTileImage &&
      other.z == z &&
      other.x == x &&
      other.y == y &&
      other.size == size;

  @override
  int get hashCode => Object.hash(z, x, y, size);
}
