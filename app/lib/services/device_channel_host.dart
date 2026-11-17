import 'background_credential_store.dart';
import 'background_location_service.dart';
import 'device_channel.dart';
import 'push_service.dart';

/// Reads the device-channel credentials from the shared store, usable from any
/// isolate. Null while logged out or before the device has an ingest key.
Future<ChannelCredentials?> readChannelCredentials() async {
  final String? apiBaseUrl = await BackgroundCredentialStore.readApiBaseUrl();
  final String? deviceId = await BackgroundCredentialStore.readDeviceId();
  final String? ingestKey = await BackgroundCredentialStore.readIngestKey();
  if (apiBaseUrl == null ||
      apiBaseUrl.isEmpty ||
      deviceId == null ||
      deviceId.isEmpty ||
      ingestKey == null ||
      ingestKey.isEmpty) {
    return null;
  }
  return ChannelCredentials(
    apiBaseUrl: apiBaseUrl,
    deviceId: deviceId,
    ingestKey: ingestKey,
  );
}

/// Owns the app's own device channel (main isolate).
///
/// While the background location service runs, it holds the channel from its
/// own isolate so notifications keep arriving after the app is closed; this
/// one then stays idle and only connects when that service is not running.
class DeviceChannelHost {
  DeviceChannelHost._();

  static final DeviceChannel _channel = DeviceChannel(
    readCredentials: readChannelCredentials,
    onPush: PushService.handleDevicePush,
    mayConnect: () async => !await _backgroundServiceRunning(),
  );

  static Future<bool> _backgroundServiceRunning() async {
    try {
      return await BackgroundLocationService.isRunning();
    } catch (_) {
      return false;
    }
  }

  /// Starts the app's channel; it connects only when the background service
  /// is not already holding one.
  static void ensureRunning() => _channel.start();

  /// Stops the channel (logout).
  static Future<void> stop() => _channel.stop();
}
