import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/screens/family_management_screen.dart';
import 'package:whereabouts/screens/profile_screen.dart';
import 'package:whereabouts/screens/settings_screen.dart';
import 'package:whereabouts/services/family_management_service.dart';

void main() {
  test('managed family member decodes the server contract', () {
    final ManagedFamilyMember member = ManagedFamilyMember.fromJson(<String, dynamic>{
      'id': 'user-1',
      'name': 'Frank',
      'email': 'frank@example.com',
      'role': 'admin',
    });

    expect(member.id, 'user-1');
    expect(member.name, 'Frank');
    expect(member.email, 'frank@example.com');
    expect(member.role, 'admin');
  });

  testWidgets('profile setting opens the profile screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
