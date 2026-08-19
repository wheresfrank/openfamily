import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_config.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'sign_up_screen.dart';

/// The onboarding entry point: a brand hero with "Get Started" (sign-up) and
/// "Log In" (existing users).
///
/// Map-first: a subtle, non-interactive live map sits behind the hero so the
/// brand promise ("know where your family is") is visible from the first
/// screen. The map is a neutral world view — it deliberately does NOT request
/// the user's location here, because the OS permission prompt belongs in the
/// sequenced permissions step (requesting it here would leak a dialog out of
/// the flow and double-prompt on iOS). The app mark is a pink-and-purple
/// rounded-square fingerprint.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  /// Neutral world view for the hero map (no location request on this screen).
  static const LatLng _center = LatLng(0, 0);
  static const double _zoom = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Subtle map background (non-interactive).
          Positioned.fill(
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: _center,
                initialZoom: _zoom,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: kTileUrl,
                  userAgentPackageName: 'com.whereabouts.whereabouts',
                ),
              ],
            ),
          ),
          // Soft wash so the hero text stays readable over the map. Kept light
          // (0.55) so the map-first promise reads through — the map is the
          // hero, not a faint backdrop.
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.55)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        gradient: AppGradients.brand,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Whereabouts',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.purple,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Know where your family is — privately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Self-hosted. No ads. Your location stays in your circle.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignUpScreen(),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Get Started', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    ),
                    child: const Text('Log In'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
