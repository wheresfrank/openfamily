// Build-time configuration for the Whereabouts app.
//
// All values are overridable via `--dart-define` so a self-hosted deployment
// can point the app at its own infrastructure without code changes.

/// Base URL for the Whereabouts backend.
///
/// Override at build time with:
///   flutter run --dart-define=WHEREABOUTS_API_URL=https://your.server
///
/// When unset this is the empty string, and requests fail loudly with a
/// "not configured" message rather than a confusing DNS error.
const String kApiBaseUrl = String.fromEnvironment('WHEREABOUTS_API_URL');

/// Standard (street) map tile URL template, with `{z}`/`{x}`/`{y}` placeholders.
///
/// PRIVACY: the default points at the public OpenStreetMap tile server, which
/// receives the map viewport (i.e. roughly where your family is) on every
/// pan/zoom. A self-hosted deployment MUST override this with its own tile
/// server to avoid leaking family locations to a third party:
///
///   --dart-define=WHEREABOUTS_TILE_URL=https://tiles.your.server/{z}/{x}/{y}.png
const String kTileUrl = String.fromEnvironment(
  'WHEREABOUTS_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// Satellite imagery tile URL template (same privacy caveat as [kTileUrl]).
const String kSatelliteTileUrl = String.fromEnvironment(
  'WHEREABOUTS_SATELLITE_TILE_URL',
  defaultValue:
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
);
