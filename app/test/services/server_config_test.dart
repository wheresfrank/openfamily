import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openfamily/services/server_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfig.instance.debugReset();
  });

  test('stored preference wins over an empty dart-define', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wb_api_base_url': 'https://family.example.com',
    });
    await ServerConfig.instance.load();
    expect(ServerConfig.instance.apiBaseUrl, 'https://family.example.com');
    expect(ServerConfig.instance.isConfigured, isTrue);
  });

  test('setUrl strips a trailing slash', () async {
    await ServerConfig.instance.setUrl('https://family.example.com/');
    expect(ServerConfig.instance.apiBaseUrl, 'https://family.example.com');
  });

  test('clear forgets the stored URL', () async {
    await ServerConfig.instance.setUrl('https://family.example.com');
    await ServerConfig.instance.clear();
    expect(ServerConfig.instance.isConfigured, isFalse);
  });
}
