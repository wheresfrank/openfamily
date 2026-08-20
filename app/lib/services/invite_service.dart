import 'server_config.dart';
import 'api_client.dart';

/// Requests and shares 6-digit circle invite codes.
///
/// A single source of truth for the code format and the share message, used by
/// both the map's "Add a person" flow and the onboarding "Invite family" flow.
class InviteService {
  InviteService._();

  /// Requests a fresh invite code from the server.
  static Future<String> createCode() async {
    final dynamic data = await ApiClient.post('/family/invites');
    final Map<String, dynamic> map = data as Map<String, dynamic>;
    return map['code'] as String;
  }

  /// The deep link a recipient can tap to join, pointing at the user's own
  /// server (resolved from [ServerConfig]).
  static String joinUrl(String code) =>
      '${ServerConfig.instance.apiBaseUrl}/join/$code';

  /// The share-sheet subject line.
  static const String shareSubject = 'Join my Whereabouts circle';

  /// The share-sheet body: the code plus the join link.
  static String shareMessage(String code) =>
      'Join my Whereabouts circle! Use code $code or tap ${joinUrl(code)}';
}