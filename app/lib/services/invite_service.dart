import 'api_client.dart';
import 'server_config.dart';

import '../l10n/l10n.dart';

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
  static String get shareSubject => CurrentL10n.value.shareSubject;

  /// The share-sheet body: the code and the operator's server URL.
  ///
  /// There is no `/join/{code}` web route; the recipient installs the Android
  /// app, enters this server, and types the code.
  static String shareMessage(String code) => CurrentL10n.value.shareMessage(
        ServerConfig.instance.apiBaseUrl,
        code,
      );
}
