/// Validates and joins a Circle by invite code.
///
/// The backend is not wired up yet, so this simulates a server round-trip:
/// only codes the (simulated) server knows about are valid. A later phase
/// replaces this with a real POST /circles/join call that validates against
/// active invite codes and returns the joined circle.
class JoinService {
  JoinService._();

  /// Codes the simulated server currently knows. In production the server
  /// validates against real, active invite codes — a random 6-digit code is
  /// almost always invalid, which is exactly the error path this models.
  static const Set<String> _knownCodes = <String>{'123456'};

  /// Attempts to join the circle for [code]. Returns true on success, false
  /// when the code is unknown/invalid.
  static Future<bool> join(String code) async {
    // Simulated network latency.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return _knownCodes.contains(code);
  }
}
