import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/services/background_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('sync persists the background-visible credentials', () async {
    await BackgroundCredentialStore.sync(
      apiBaseUrl: 'https://family.example.com',
      accessToken: 'access-1',
      deviceId: 'device-1',
    );

    expect(await BackgroundCredentialStore.readApiBaseUrl(),
        'https://family.example.com');
    expect(await BackgroundCredentialStore.readAccessToken(), 'access-1');
    expect(await BackgroundCredentialStore.readDeviceId(), 'device-1');
  });

  test('the ingest key round-trips independently of the tokens', () async {
    await BackgroundCredentialStore.saveIngestKey('ingest-key-1');
    expect(
      await BackgroundCredentialStore.readIngestKey(),
      'ingest-key-1',
    );
  });

  test('clear removes every background credential, including the ingest key',
      () async {
    await BackgroundCredentialStore.sync(
      apiBaseUrl: 'https://family.example.com',
      accessToken: 'access-1',
      deviceId: 'device-1',
    );
    await BackgroundCredentialStore.saveIngestKey('ingest-key-1');

    await BackgroundCredentialStore.clear();

    expect(await BackgroundCredentialStore.readApiBaseUrl(), isNull);
    expect(await BackgroundCredentialStore.readAccessToken(), isNull);
    expect(await BackgroundCredentialStore.readDeviceId(), isNull);
    expect(await BackgroundCredentialStore.readIngestKey(), isNull);
  });
}
