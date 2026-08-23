import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whereabouts/services/invite_service.dart';
import 'package:whereabouts/services/server_config.dart';

void main() {
  test('share message includes the server URL and code, not a /join link',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfig.instance.debugReset();
    await ServerConfig.instance.setUrl('https://family.example.com');

    final String message = InviteService.shareMessage('ABCD2345');
    expect(message, contains('https://family.example.com'));
    expect(message, contains('ABCD2345'));
    expect(message.contains('/join/'), isFalse);
  });
}
