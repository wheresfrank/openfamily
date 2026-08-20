import 'api_client.dart';
import 'server_config.dart';

/// Creates and shares alphanumeric family invite codes.
///
/// A single source of truth for the code format and the share message, used by
/// both the map's "Add a person" flow and the onboarding "Invite family" flow.
/// Codes are created on the server (family admin only) so they are real and
/// validated at registration/join time.
class InviteService {
  InviteService._();

  /// Creates a real invite code on the server and returns it.
  static Future<String> createCode() async {
    final Map<String, dynamic> data = await ApiClient.createInvite();
    return data['code'] as String;
  }

  /// The deep link a recipient can tap to join, pointing at the user's own
  /// server (resolved from [ServerConfig]).
  static String joinUrl(String code) =>
      '${ServerConfig.instance.apiBaseUrl}/join/$code';

  /// The share-sheet subject line.
  static const String shareSubject = 'Join my Whereabouts family';

  /// The share-sheet body: the code plus the join link.
  static String shareMessage(String code) =>
      'Join my Whereabouts family! Use code $code or tap ${joinUrl(code)}';
}
