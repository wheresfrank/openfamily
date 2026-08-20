import 'api_client.dart';

/// Joins a family by invite code.
///
/// Calls POST /family/join, which validates the code against the server's
/// active invite codes and assigns the caller to the code's family and role.
class JoinService {
  JoinService._();

  /// Attempts to join the family for [code]. Returns true on success, false
  /// when the code is unknown/invalid/expired/exhausted.
  static Future<bool> join(String code) async {
    try {
      await ApiClient.joinFamily(code);
      return true;
    } on ApiException {
      return false;
    }
  }
}
