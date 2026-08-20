import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/screens/profile_screen.dart';
import 'package:whereabouts/screens/settings_screen.dart';

void main() {
  test('smoke test', () {
    expect(true, isTrue);
  });

  testWidgets('profile setting opens the profile screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
