/// Platform detection that also compiles for the web.
///
/// The app imports `location_dto.dart` and `settings_util.dart` even when
/// built for the web (e.g. for the browser-based device preview), where
/// `dart:io` does not exist. This shim resolves to the real `dart:io`
/// checks on VM platforms and to always-false stubs on the web, where the
/// plugin has no native implementation and is never invoked.
///
/// Mirrors the app's own `unifiedpush_bridge.dart` conditional-import
/// pattern.
export 'platform_is_stub.dart' if (dart.library.io) 'platform_is_io.dart';