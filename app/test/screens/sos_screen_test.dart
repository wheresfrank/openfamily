import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whereabouts/screens/sos_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('hides add emergency contacts when SMS is off',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SosScreen(smsConfigured: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add emergency contacts'), findsNothing);
    expect(find.textContaining('your family, with your location'), findsOneWidget);
  });

  testWidgets('shows add emergency contacts when SMS is on',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SosScreen(smsConfigured: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add emergency contacts'), findsOneWidget);
  });

  testWidgets('SOS success is not shown when the API fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SosScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('sos-send-button')));
    await tester.pump();
    await tester.tap(find.text('Send SOS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('SOS sent'), findsNothing);
  });

  testWidgets('practice SOS never claims a real send',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SosScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Practice SOS'));
    await tester.pump();
    expect(find.text('SOS sent'), findsNothing);
    expect(find.textContaining('Practice'), findsWidgets);
  });

  testWidgets('releasing a hold starts the countdown',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SosScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('sos-send-button'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(
      find.text('Keep holding… release to start the countdown'),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Slide to Cancel'), findsOneWidget);
    expect(
      find.text('Keep holding… release to start the countdown'),
      findsNothing,
    );

    await gesture.removePointer();
  });
}
