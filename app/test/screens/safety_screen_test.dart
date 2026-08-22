import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/screens/safety_screen.dart';

void main() {
  testWidgets('safety screen does not seed fake Mom/Dad contacts',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SafetyScreen()));
    expect(find.text('Mom'), findsNothing);
    expect(find.text('Dad'), findsNothing);
    await tester.pump();
    expect(find.text('Mom'), findsNothing);
    expect(find.text('Dad'), findsNothing);
  });
}
