import 'dart:convert';
import 'dart:io';

import 'package:unifiedpush/unifiedpush.dart';

const String _instance = 'default';

/// Android UnifiedPush connector. No-ops on iOS/desktop.
Future<void> initUnifiedPush({
  required Future<void> Function(String endpoint) onNewEndpoint,
  required Future<void> Function(String body) onMessage,
}) async {
  if (!Platform.isAndroid) return;
  await UnifiedPush.initialize(
    onNewEndpoint: (PushEndpoint endpoint, String instance) {
      if (instance != _instance || endpoint.url.isEmpty) return;
      onNewEndpoint(endpoint.url);
    },
    onMessage: (PushMessage message, String instance) {
      if (instance != _instance) return;
      final String body = utf8.decode(message.content, allowMalformed: true);
      onMessage(body);
    },
    onRegistrationFailed: (FailedReason reason, String instance) {},
    onUnregistered: (String instance) {},
  );
}

Future<void> registerUnifiedPush({String? ntfyBaseUrl}) async {
  if (!Platform.isAndroid) return;
  final bool ready = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
  if (!ready) {
    final List<String> distributors = await UnifiedPush.getDistributors();
    if (distributors.isEmpty) {
      return;
    }
    final String chosen = distributors.firstWhere(
      (String id) => id.toLowerCase().contains('ntfy'),
      orElse: () => distributors.first,
    );
    await UnifiedPush.saveDistributor(chosen);
  }
  await UnifiedPush.register(
    instance: _instance,
    messageForDistributor: ntfyBaseUrl,
  );
}

Future<void> unregisterUnifiedPush() async {
  if (!Platform.isAndroid) return;
  await UnifiedPush.unregister(_instance);
}
