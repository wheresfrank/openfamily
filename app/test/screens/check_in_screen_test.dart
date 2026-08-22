import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/screens/check_in_screen.dart';

void main() {
  testWidgets('check-in does not use a fake street address',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CheckInScreen()));
    expect(find.textContaining('123 Maple'), findsNothing);
  });

  testWidgets('check-in success is not shown when the API fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CheckInScreen()));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Checked in'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Check In'), findsOneWidget);
  });
}
