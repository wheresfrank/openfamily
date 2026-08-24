import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/widgets/map_bottom_bar.dart';

/// Wraps [MapBottomBar] with every action captured by a spy so the wiring of
/// each control (especially the new People destination) can be asserted.
Widget _bar(Map<String, VoidCallback> spies) {
  return MaterialApp(
    home: Scaffold(
      body: MapBottomBar(
        onSos: spies['sos'],
        onPeople: spies['people'],
        onPlaces: spies['places'],
        onSafety: spies['safety'],
        onSettings: spies['settings'],
      ),
    ),
  );
}

void main() {
  testWidgets('People destination is present and fires onPeople', (
    WidgetTester tester,
  ) async {
    final Map<String, int> calls = <String, int>{};
    final Map<String, VoidCallback> spies = <String, VoidCallback>{
      for (final String key in [
        'sos',
        'people',
        'places',
        'safety',
        'settings'
      ])
        key: () => calls[key] = (calls[key] ?? 0) + 1,
    };

    await tester.pumpWidget(_bar(spies));

    // The People control is present (icon + tooltip) alongside the others.
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    expect(find.byTooltip('People'), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    expect(find.byIcon(Icons.key_outlined), findsNothing);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);

    // Tapping it fires the wired callback.
    await tester.tap(find.byTooltip('People'));
    await tester.pump();
    expect(calls['people'], 1);
    expect(calls['sos'], isNull);

    // No runtime overflow with SOS plus People / Places / Safety / Settings.
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar renders without overflow on a narrow 360dp screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_bar(const <String, VoidCallback>{}));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides emergency contacts when onSafety is omitted', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapBottomBar(
            onSos: null,
            onPeople: null,
            onPlaces: null,
            onSettings: null,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
  });
}
