import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/screens/help_alert_screen.dart';

void main() {
  testWidgets('help alert success is not shown when the API fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpAlertScreen()));
    await tester.tap(find.widgetWithText(FilledButton, 'Send Help Alert'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Help alert sent'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Send Help Alert'), findsOneWidget);
  });
}
