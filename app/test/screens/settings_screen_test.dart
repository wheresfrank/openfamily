import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/screens/settings_screen.dart';

void main() {
  group('pushNotificationsSubtitle', () {
    test('guides Android users to the UnifiedPush distributor', () {
      final String subtitle = pushNotificationsSubtitle(
        isWeb: false,
        platform: TargetPlatform.android,
      );

      expect(subtitle, contains('ntfy'));
      expect(subtitle, contains('unregisters this device'));
    });

    test('references APNs on iOS — no Android-specific copy', () {
      final String subtitle = pushNotificationsSubtitle(
        isWeb: false,
        platform: TargetPlatform.iOS,
      );

      expect(subtitle, contains('APNs'));
      expect(subtitle, isNot(contains('Android')));
      expect(subtitle, isNot(contains('ntfy')));
      expect(subtitle, isNot(contains('UnifiedPush')));
    });

    test('tells browser users push is unavailable rather than how to install',
        () {
      final String subtitle = pushNotificationsSubtitle(
        isWeb: true,
        platform: TargetPlatform.iOS,
      );

      expect(subtitle, contains('browser'));
      expect(subtitle, isNot(contains('ntfy')));
    });

    test('the default platform target (no override) yields non-empty copy',
        () {
      final String subtitle = pushNotificationsSubtitle(isWeb: kIsWeb);

      expect(subtitle, isNotEmpty);
    });

    test('the device-preview override renders iOS copy for a web build', () {
      final String subtitle = pushNotificationsSubtitle(
        isWeb: true,
        previewPlatform: 'ios',
      );

      expect(subtitle, contains('APNs'));
      expect(subtitle, isNot(contains('browser')));
      expect(subtitle, isNot(contains('ntfy')));
    });

    test('the device-preview override renders Android copy for a web build',
        () {
      final String subtitle = pushNotificationsSubtitle(
        isWeb: true,
        previewPlatform: 'android',
      );

      expect(subtitle, contains('ntfy'));
      expect(subtitle, isNot(contains('browser')));
    });

    test('an unknown override falls through to honest engine copy', () {
      final String subtitle = pushNotificationsSubtitle(
        isWeb: true,
        previewPlatform: 'whatchamacallit',
      );

      expect(subtitle, contains('browser'));
    });
  });
}