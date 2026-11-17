import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/screens/help_alert_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HelpAlertScreen()));
  }

  testWidgets('help alert success is not shown when the API fails',
      (WidgetTester tester) async {
    await pumpScreen(tester);
    final Finder send = find.widgetWithText(FilledButton, 'Send Help Alert');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Help alert sent'), findsNothing);
    expect(send, findsOneWidget);
  });

  testWidgets('a quick message fills the note and can be cleared',
      (WidgetTester tester) async {
    await pumpScreen(tester);
    final Finder field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.ensureVisible(find.text('I\'m lost'));
    await tester.tap(find.text('I\'m lost'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'I\'m lost');
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'I\'m lost')).selected,
      isTrue,
    );

    // Tapping the selected message again clears it.
    await tester.tap(find.widgetWithText(ChoiceChip, 'I\'m lost'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
  });

  testWidgets('a custom message deselects the quick messages',
      (WidgetTester tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(find.text('I need a ride'));
    await tester.tap(find.text('I need a ride'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'I need a ride home');
    await tester.pump();
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'I need a ride')).selected,
      isFalse,
    );
  });
}
