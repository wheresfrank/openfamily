import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'token_storage.dart';

/// Registers the current device with the backend so later location reporting
/// can attach to a stable device id.
class DeviceService {
  DeviceService._();

  /// App version reported to the backend. Override at build time with
  /// `--dart-define=WHEREABOUTS_APP_VERSION=...`.
  static const String _appVersion = String.fromEnvironment(
    'WHEREABOUTS_APP_VERSION',
    defaultValue: '0.1.0',
  );

  /// Single-flight guard: if two callers invoke [ensureRegistered] concurrently
  /// while no device id is stored, only the first issues `POST /devices`; the
  /// second awaits and reuses the same result.
  static Future<String>? _pendingRegistration;

  /// Returns the stored device id, registering the device first if needed.
  ///
  /// Idempotent-ish: once a device id is stored it is reused, so repeated
  /// calls (e.g. across app restarts) don't create duplicate devices.
  /// Concurrent calls with no stored id are single-flighted so only one
  /// `POST /devices` is issued.
  static Future<String> ensureRegistered() async {
    final String? existing = await TokenStorage.readDeviceId();
    if (existing != null) return existing;

    // Single-flight: reuse an in-flight registration rather than issuing a
    // second POST /devices that would create a duplicate device record.
    final Future<String> pending = _pendingRegistration ??= _register();
    try {
      return await pending;
    } finally {
      _pendingRegistration = null;
    }
  }

  static Future<String> _register() async {
    final Map<String, dynamic> device = await ApiClient.registerDevice(
      platform: _platform(),
      name: _deviceName(),
      appVersion: _appVersion,
    );
    final String id = device['id'] as String;
    await TokenStorage.saveDeviceId(id);
    return id;
  }

  /// Detects the current platform: ios / android / web.
  ///
  /// Uses [kIsWeb] + [defaultTargetPlatform] (web-safe) rather than `dart:io`
  /// `Platform`, which throws [UnsupportedError] on Flutter web.
  static String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'web';
    }
  }

  /// A friendly device name (web-safe; no `dart:io` hostname lookup).
  static String _deviceName() {
    if (kIsWeb) return 'Web browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iPhone';
      case TargetPlatform.android:
        return 'Android device';
      default:
        return 'Whereabouts device';
    }
  }
}
