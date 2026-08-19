import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/api_client.dart';
import 'services/background_location_service.dart';
import 'services/token_storage.dart';
import 'theme/app_theme.dart';

/// Global navigator key so non-widget code (e.g. [ApiClient]) can navigate on
/// session expiry.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const WhereaboutsApp());
}

/// Root widget for the Whereabouts app.
class WhereaboutsApp extends StatefulWidget {
  const WhereaboutsApp({super.key});

  @override
  State<WhereaboutsApp> createState() => _WhereaboutsAppState();
}

class _WhereaboutsAppState extends State<WhereaboutsApp> {
  @override
  void initState() {
    super.initState();
    // When a session expires mid-use (refresh fails), redirect to login.
    ApiClient.onSessionExpired = _handleSessionExpired;
  }

  void _handleSessionExpired() {
    // Stop background reporting: the session is dead and the background isolate
    // can no longer authenticate.
    BackgroundLocationService.stop();
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whereabouts',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildAppTheme(),
      home: const _SessionGate(),
    );
  }
}

/// Resolves the persisted session before showing the first screen, so a
/// logged-in user is routed to the map instead of being dumped into onboarding.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  /// Resolved once (not in [build]) so the session check does not re-run on
  /// every rebuild. The future first reconciles any tokens the background
  /// isolate rotated while the app was killed (syncing shared_preferences →
  /// secure storage), THEN checks whether a valid session exists — so a
  /// background-refreshed token that only reached shared_preferences is
  /// picked up before the session gate decides.
  late final Future<bool> _hasSession = _initSession();

  Future<bool> _initSession() async {
    try {
      await TokenStorage.syncFromBackgroundStore();
    } catch (_) {
      // Ignore sync failures; the reporter's 401→refresh path recovers.
    }
    final bool hasSession = await ApiClient.hasValidSession();
    if (hasSession) {
      // Start background location reporting (fire-and-forget) so the device
      // keeps reporting even when backgrounded.
      BackgroundLocationService.start();
    }
    return hasSession;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        final bool hasSession = snapshot.data ?? false;
        return hasSession ? const MapScreen() : const WelcomeScreen();
      },
    );
  }
}

/// A minimal loading screen shown while the persisted session is resolved.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
