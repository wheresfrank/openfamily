import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/screens/sos_screen.dart';

void main() {
  testWidgets('SOS success is not shown when the API fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SosScreen()));
    await tester.tap(find.text('Begin Setup'));
    await tester.pump();
    await tester.tap(find.text('SOS').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('SOS sent'), findsNothing);
  });

  testWidgets('practice SOS never claims a real send',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SosScreen()));
    await tester.tap(find.text('Begin Setup'));
    await tester.pump();
    await tester.tap(find.text('Practice SOS'));
    await tester.pump();
    expect(find.text('SOS sent'), findsNothing);
    expect(find.textContaining('Practice'), findsWidgets);
  });
}
