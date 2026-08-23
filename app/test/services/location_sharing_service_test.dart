import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whereabouts/services/location_sharing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocationSharingService.enabled.value = true;
  });

  test('defaults to sharing on', () async {
    expect(await LocationSharingService.load(), isTrue);
    expect(LocationSharingService.enabled.value, isTrue);
  });

  test('persists turning sharing off and on', () async {
    await LocationSharingService.setEnabled(false);
    expect(LocationSharingService.enabled.value, isFalse);
    expect(await LocationSharingService.load(), isFalse);

    await LocationSharingService.setEnabled(true);
    expect(LocationSharingService.enabled.value, isTrue);
    expect(await LocationSharingService.load(), isTrue);
  });
}
