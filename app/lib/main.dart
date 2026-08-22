import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/server_config_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/background_location_service.dart';
import 'services/push_service.dart';
import 'services/server_config.dart';
import 'services/token_storage.dart';
import 'theme/app_theme.dart';
import 'widgets/biometric_app_lock.dart';

/// Global navigator key so non-widget code (e.g. [ApiClient]) can navigate on
/// session expiry.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Plugin callbacks must be registered before the first frame so a
  // UnifiedPush/APNs token arriving at launch is not dropped.
  PushService.initialize();
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

  Future<void> _handleBiometricLogout() async {
    // Let failures propagate to BiometricAppLock so protected content stays
    // covered unless credential deletion was verified.
    await AuthService.logout();
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) {
      throw StateError('The app navigator is unavailable.');
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
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
      builder: (context, child) => BiometricAppLock(
        onLogout: _handleBiometricLogout,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _SessionGate(),
    );
  }
}

/// Resolves the persisted session before showing the first screen, so a
/// logged-in user is routed to the map instead of being dumped into onboarding.
///
/// The gate first loads the runtime server config (from `shared_preferences`
/// if the compile-time dart-define was empty), then checks whether a valid
/// session exists.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<_GateResult> _result = _init();

  Future<_GateResult> _init() async {
    // Load the runtime server URL (shared_preferences → ServerConfig).
    await ServerConfig.instance.load();

    // Remove the path-only local photo pointer used by an older avatar
    // implementation. Current avatars are private authenticated bytes and are
    // never persisted as a device file path.
    try {
      await TokenStorage.removeLegacyProfilePhotoPath();
    } catch (_) {
      // A secure-storage hiccup should not prevent the app from starting; a
      // later launch or logout will retry this idempotent cleanup.
    }

    if (!ServerConfig.instance.isConfigured) {
      return _GateResult.needsServerConfig;
    }

    try {
      await TokenStorage.syncFromBackgroundStore();
    } catch (_) {
      // Ignore sync failures; the reporter's 401→refresh path recovers.
    }
    final bool hasSession = await ApiClient.hasValidSession();
    if (!hasSession) {
      // Remove an incomplete, malformed, or expired token pair. Besides
      // keeping startup deterministic, this clears biometric opt-in so it can
      // never carry over to a future account on the same device.
      await TokenStorage.clear();
    }
    // Background location reporting is started by MapScreen once it is shown
    // (and the app is in the foreground), not here — starting a `location`
    // foreground service during startup, before the activity is visible, is
    // rejected on Android 15+.
    return hasSession ? _GateResult.hasSession : _GateResult.noSession;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateResult>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        switch (snapshot.data) {
          case _GateResult.needsServerConfig:
            return const ServerConfigScreen();
          case _GateResult.hasSession:
            return const MapScreen();
          default:
            return const WelcomeScreen();
        }
      },
    );
  }
}

enum _GateResult { needsServerConfig, hasSession, noSession }

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
