import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/unit_preference.dart';
import 'package:openfamily/utils/units.dart';

void main() {
  group('Units.distance', () {
    test('imperial uses feet below a mile and miles above', () {
      expect(Units.distance(76.2, metric: false), '250 ft');
      expect(Units.distance(152.4, metric: false), '500 ft');
      expect(Units.distance(1609.344, metric: false), '1 mi');
      expect(Units.distance(2414.016, metric: false), '1.5 mi');
    });

    test('metric uses meters below a kilometer and km above', () {
      expect(Units.distance(100, metric: true), '100 m');
      expect(Units.distance(999, metric: true), '999 m');
      expect(Units.distance(1000, metric: true), '1 km');
      expect(Units.distance(2500, metric: true), '2.5 km');
    });
  });

  group('Units.speed', () {
    test('converts meters per second to mph and km/h', () {
      expect(Units.speed(20, metric: false), '45 mph');
      expect(Units.speed(20, metric: true), '72 km/h');
      expect(Units.speedValue(0, metric: true), 0);
    });
  });

  group('UnitPreferenceService.resolveMetric', () {
    test('explicit choices ignore the region', () {
      expect(UnitPreferenceService.resolveMetric(UnitPreference.metric, 'US'),
          isTrue);
      expect(
          UnitPreferenceService.resolveMetric(UnitPreference.imperial, 'VE'),
          isFalse);
    });

    test('system follows the region', () {
      expect(UnitPreferenceService.resolveMetric(UnitPreference.system, 'US'),
          isFalse);
      expect(UnitPreferenceService.resolveMetric(UnitPreference.system, 'us'),
          isFalse);
      expect(UnitPreferenceService.resolveMetric(UnitPreference.system, 'VE'),
          isTrue);
      expect(
          UnitPreferenceService.resolveMetric(UnitPreference.system, null),
          isTrue);
    });
  });

  test('UnitPreference parses stored values', () {
    expect(UnitPreferenceX.parse('metric'), UnitPreference.metric);
    expect(UnitPreferenceX.parse('imperial'), UnitPreference.imperial);
    expect(UnitPreferenceX.parse('junk'), UnitPreference.system);
    expect(UnitPreferenceX.parse(null), UnitPreference.system);
  });
}
