import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whereabouts/services/push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PushService.enabled.value = true;
  });

  test('defaults to push on', () async {
    expect(await PushService.load(), isTrue);
    expect(PushService.enabled.value, isTrue);
  });

  test('persists turning push off', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'push_notifications_enabled': true,
    });
    await PushService.load();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_notifications_enabled', false);
    expect(await PushService.load(), isFalse);
    expect(PushService.enabled.value, isFalse);
  });
}
