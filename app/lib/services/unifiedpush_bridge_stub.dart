/// Web / non-IO stub. UnifiedPush is an Android distributor protocol.
Future<void> initUnifiedPush({
  required Future<void> Function(String endpoint) onNewEndpoint,
  required Future<void> Function(String body) onMessage,
  Future<void> Function()? onUnregistered,
  Future<void> Function(String reason)? onRegistrationFailed,
}) async {}

Future<void> registerUnifiedPush({String? ntfyBaseUrl}) async {}

Future<void> unregisterUnifiedPush() async {}
