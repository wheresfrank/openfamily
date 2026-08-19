import 'dart:math' as math;

/// Generates and shares 6-digit circle invite codes.
///
/// A single source of truth for the code format and the share message, used by
/// both the map's "Add a person" flow and the onboarding "Invite family" flow.
class InviteService {
  InviteService._();

  /// Base URL for the deep-link join page (self-hosted).
  static const String baseUrl = 'https://whereabouts.example/join';

  /// Generates a fresh 6-digit invite code.
  static String generateCode() {
    final math.Random rng = math.Random.secure();
    return (rng.nextInt(900000) + 100000).toString();
  }

  /// The deep link a recipient can tap to join.
  static String joinUrl(String code) => '$baseUrl/$code';

  /// The share-sheet subject line.
  static const String shareSubject = 'Join my Whereabouts circle';

  /// The share-sheet body: the code plus the join link.
  static String shareMessage(String code) =>
      'Join my Whereabouts circle! Use code $code or tap ${joinUrl(code)}';
}
