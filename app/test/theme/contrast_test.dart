import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const double aa = 4.5;

  for (final MapEntry<String, BrandTheme> entry in <String, BrandTheme>{
    'ice': BrandTheme.ice,
    'night': BrandTheme.night,
  }.entries) {
    final BrandTheme brand = entry.value;
    final ThemeData theme =
        entry.key == 'ice' ? buildLightTheme() : buildDarkTheme();
    final Color ink = theme.colorScheme.onSurface;

    group('${entry.key} theme text contrast', () {
      test('primary text on the page and on cards', () {
        expect(contrast(ink, brand.paper), greaterThanOrEqualTo(aa));
        expect(contrast(ink, brand.sheet), greaterThanOrEqualTo(aa));
      });

      test('secondary text on the page and on cards', () {
        expect(contrast(brand.muted, brand.paper), greaterThanOrEqualTo(aa));
        expect(contrast(brand.muted, brand.sheet), greaterThanOrEqualTo(aa));
      });

      test('accent used as text or an icon', () {
        expect(contrast(brand.accentInk, brand.paper), greaterThanOrEqualTo(aa));
        expect(contrast(brand.accentInk, brand.sheet), greaterThanOrEqualTo(aa));
      });

      test('ink on an accent-filled button', () {
        expect(contrast(brand.onAccent, brand.accent), greaterThanOrEqualTo(aa));
      });
    });
  }

  test('the raw lime is not used for text on Ice (documents why accentInk exists)',
      () {
    expect(
      contrast(AppColors.accent, AppColors.icePaper),
      lessThan(aa),
    );
  });
}
