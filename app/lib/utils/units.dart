import '../services/unit_preference.dart';

const double _metersPerFoot = 0.3048;
const double _metersPerMile = 1609.344;
const double _mpsToMph = 2.23694;
const double _mpsToKmh = 3.6;

/// Distance and speed formatting for both measurement systems. Every function
/// takes [metric] explicitly so it is pure; [Units.current] reads the user's
/// preference for call sites that just want what the user asked for.
class Units {
  Units._();

  /// Whether the user's current preference resolves to metric.
  static bool get current => UnitPreferenceService.useMetric;

  /// A short distance, e.g. "500 ft", "1.5 mi", "150 m" or "2 km".
  static String distance(double meters, {required bool metric}) {
    if (metric) {
      if (meters >= 1000) {
        return '${_trim(meters / 1000)} km';
      }
      return '${meters.round()} m';
    }
    if (meters >= _metersPerMile) {
      return '${_trim(meters / _metersPerMile)} mi';
    }
    return '${(meters / _metersPerFoot).round()} ft';
  }

  /// The numeric part of a speed in the chosen system, rounded.
  static int speedValue(double metersPerSecond, {required bool metric}) {
    return (metersPerSecond * (metric ? _mpsToKmh : _mpsToMph)).round();
  }

  /// The unit label for speeds in the chosen system.
  static String speedUnit({required bool metric}) => metric ? 'km/h' : 'mph';

  /// A speed with its unit, e.g. "42 mph" or "68 km/h".
  static String speed(double metersPerSecond, {required bool metric}) {
    return '${speedValue(metersPerSecond, metric: metric)} '
        '${speedUnit(metric: metric)}';
  }

  /// Whole numbers print without a decimal; everything else with one.
  static String _trim(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }
}
