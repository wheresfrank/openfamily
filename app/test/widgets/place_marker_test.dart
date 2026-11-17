import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:openfamily/models/place.dart';
import 'package:openfamily/theme/app_theme.dart';
import 'package:openfamily/widgets/place_marker.dart';

Place _home() => Place(
      id: 'p1',
      name: 'Home',
      icon: Place.iconForType('home'),
      address: '',
      position: const LatLng(10.5, -66.9),
      radiusMeters: 150,
      type: 'home',
    );

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  testWidgets('shows the place icon and name and reports taps',
      (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: Center(child: PlaceMarker(place: _home(), onTap: () => taps++)),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    await tester.tap(find.text('Home'));
    expect(taps, 1);
  });

  for (final ThemeData theme in <ThemeData>[
    buildLightTheme(),
    buildDarkTheme(),
  ]) {
    testWidgets('the label is readable in the ${theme.brightness.name} theme',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: Center(child: PlaceMarker(place: _home()))),
        ),
      );
      final Text label = tester.widget<Text>(find.text('Home'));
      final Color pill = BrandTheme.ice.sheet == BrandTheme.of(
        tester.element(find.text('Home')),
      ).sheet
          ? BrandTheme.ice.sheet
          : BrandTheme.night.sheet;
      expect(_contrast(label.style!.color!, pill), greaterThan(4.5));
    });
  }

  test('every backend place type has its own icon', () {
    final Set<IconData> icons =
        Place.types.map(Place.iconForType).toSet();
    // custom and unknown share the generic pin; every other type is distinct.
    expect(icons.length, Place.types.length);
  });
}
