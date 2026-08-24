import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/server_features.dart';

void main() {
  setUp(ServerFeatures.instance.reset);

  test('smsConfigured is off until /config says otherwise', () {
    expect(ServerFeatures.instance.smsConfigured, isFalse);
  });

  test('apply reads sms_configured', () {
    ServerFeatures.instance.apply(<String, dynamic>{'sms_configured': true});
    expect(ServerFeatures.instance.smsConfigured, isTrue);
    ServerFeatures.instance.apply(<String, dynamic>{'sms_configured': false});
    expect(ServerFeatures.instance.smsConfigured, isFalse);
  });

  test('missing sms_configured keeps contacts visible for older servers', () {
    ServerFeatures.instance.apply(<String, dynamic>{'tile_url': 'https://example'});
    expect(ServerFeatures.instance.smsConfigured, isTrue);
  });
}
