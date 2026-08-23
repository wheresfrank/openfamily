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

  /// The share-sheet subject line.
  static const String shareSubject = 'Join my Whereabouts family';

  /// The share-sheet body: the code and the operator's server URL.
  ///
  /// There is no `/join/{code}` web route; the recipient installs the Android
  /// app, enters this server, and types the code.
  static String shareMessage(String code) =>
      'Join my Whereabouts family!\n\n'
      '1. Install the Whereabouts Android app\n'
      '2. Enter this server: ${ServerConfig.instance.apiBaseUrl}\n'
      '3. Use invite code $code';
}
