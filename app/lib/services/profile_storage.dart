import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's profile photo locally (path only for now).
///
/// Uploading the photo to the backend is deferred to the "backend wiring"
/// piece; until then we keep the local file path so the photo survives
/// restarts.
class ProfileStorage {
  ProfileStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _photoPathKey = 'profile_photo_path';

  static Future<void> savePhotoPath(String path) =>
      _storage.write(key: _photoPathKey, value: path);

  static Future<String?> readPhotoPath() => _storage.read(key: _photoPathKey);
}
