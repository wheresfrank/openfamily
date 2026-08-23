import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whereabouts/services/theme_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ThemePreferenceService.preference.value = ThemePreference.system;
  });

  test('defaults to system when nothing is stored', () async {
    expect(await ThemePreferenceService.load(), ThemePreference.system);
    expect(ThemePreferenceService.themeMode, ThemeMode.system);
  });

  test('unknown stored values fall back to system', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'theme_preference': 'sepia'},
    );
    expect(await ThemePreferenceService.load(), ThemePreference.system);
  });

  test('persists light and dark overrides', () async {
    await ThemePreferenceService.setPreference(ThemePreference.light);
    expect(ThemePreferenceService.preference.value, ThemePreference.light);
    expect(ThemePreferenceService.themeMode, ThemeMode.light);
    expect(await ThemePreferenceService.load(), ThemePreference.light);

    await ThemePreferenceService.setPreference(ThemePreference.dark);
    expect(ThemePreferenceService.themeMode, ThemeMode.dark);
    expect(await ThemePreferenceService.load(), ThemePreference.dark);
  });
}
