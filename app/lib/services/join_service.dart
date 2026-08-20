import 'api_client.dart';

/// Joins the currently signed-in user to a family using a server-issued code.
class JoinService {
  JoinService._();

  static Future<bool> join(String code) async {
    await ApiClient.post(
      '/family/join',
      body: <String, dynamic>{'code': code},
    );
    return true;
  }
}
