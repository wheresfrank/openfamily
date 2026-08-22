import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart' show BiometricType;

import '../services/auth_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/biometric_service.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'families_screen.dart';
import 'welcome_screen.dart';

/// The Settings screen. Account profile is server-backed; the remaining
/// location and notification values are local toggles for now.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _locationSharing = true;
  bool _notifications = true;
  bool _driveDetection = true;
  bool _loggingOut = false;
  final BiometricService _biometricService = BiometricService.instance;
  bool _biometricLoading = true;
  bool _biometricUpdating = false;
  bool _biometricEnabled = false;
  BiometricAvailability? _biometricAvailability;
  String? _biometricError;

  @override
  void initState() {
    super.initState();
    _loadBiometricSettings();
  }

  Future<void> _loadBiometricSettings() async {
    try {
      final bool enabled = await _biometricService.isEnabled();
      final BiometricAvailability availability =
          await _biometricService.getAvailability();
      if (!mounted) return;
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailability = availability;
        _biometricLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _biometricLoading = false;
        _biometricError =
            'Could not read biometric settings. Please reopen Settings.';
      });
    }
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    if (_biometricUpdating) return;
    setState(() {
      _biometricUpdating = true;
      _biometricError = null;
    });

    BiometricAvailability availability =
        await _biometricService.getAvailability();
    if (!mounted) return;
    _biometricAvailability = availability;

    if (enabled && !availability.isAvailable) {
      _finishBiometricUpdateWithError(availability.message);
      return;
    }

    // Confirm both opt-in and opt-out while biometrics are available. If the
    // user removed all enrolled biometrics, still let them turn a now-unusable
    // lock off from this already-authenticated session.
    if (enabled || availability.isAvailable) {
      final BiometricAuthenticationResult result =
          await _biometricService.authenticate(
        localizedReason: enabled
            ? 'Confirm your identity to enable biometric unlock.'
            : 'Confirm your identity to disable biometric unlock.',
        requireEnabled: !enabled,
      );
      if (!mounted) return;
      if (!result.authenticated) {
        _finishBiometricUpdateWithError(
          result.error?.message ??
              'Biometric authentication was not completed.',
        );
        return;
      }
    }

    final bool saved = await _biometricService.setEnabled(enabled);
    if (!mounted) return;
    if (!saved) {
      _finishBiometricUpdateWithError(
        'Could not save the biometric setting. Please try again.',
      );
      return;
    }

    setState(() {
      _biometricEnabled = enabled;
      _biometricUpdating = false;
      _biometricError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled ? 'Biometric unlock enabled.' : 'Biometric unlock disabled.',
        ),
      ),
    );
  }

  void _finishBiometricUpdateWithError(String message) {
    if (!mounted) return;
    setState(() {
      _biometricUpdating = false;
      _biometricError = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get _biometricSubtitle {
    if (_biometricLoading) return 'Checking this device…';
    if (_biometricUpdating) return 'Waiting for confirmation…';
    if (_biometricError != null) return _biometricError!;
    final BiometricAvailability? availability = _biometricAvailability;
    if (availability == null || !availability.isAvailable) {
      return availability?.message ??
          'Biometric authentication is unavailable.';
    }

    final List<BiometricType> enrolled = availability.enrolledBiometrics;
    final bool hasFace = enrolled.contains(BiometricType.face);
    final bool hasFingerprint = enrolled.contains(BiometricType.fingerprint);
    final String method = hasFace && hasFingerprint
        ? 'face or fingerprint recognition'
        : hasFace
            ? 'face recognition'
            : hasFingerprint
                ? 'your fingerprint'
                : 'your biometrics';
    return _biometricEnabled
        ? 'Require $method when opening or returning to the app.'
        : 'Use $method to protect your private family map.';
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthService.logout();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not log out safely. Please try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    // Clear the stack so the back button can't return to the (now logged-out)
    // map screen.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.person_outline, color: AppColors.purple),
            title: const Text('Profile'),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined, color: AppColors.purple),
            title: const Text('Family'),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FamiliesScreen()),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('Privacy & Security'),
          SwitchListTile(
            secondary: const Icon(
              Icons.fingerprint,
              color: AppColors.purple,
            ),
            title: const Text('Biometric unlock'),
            subtitle: Text(
              _biometricSubtitle,
              style: _biometricError == null
                  ? null
                  : const TextStyle(color: AppColors.statusRed),
            ),
            value: _biometricEnabled,
            onChanged: !_biometricLoading &&
                    !_biometricUpdating &&
                    ((_biometricAvailability?.isAvailable ?? false) ||
                        _biometricEnabled)
                ? _setBiometricEnabled
                : null,
          ),
          const Divider(height: 1),
          const _SectionHeader('Location'),
          SwitchListTile(
            secondary:
                const Icon(Icons.location_on_outlined, color: AppColors.purple),
            title: const Text('Location sharing'),
            value: _locationSharing,
            onChanged: (v) => setState(() => _locationSharing = v),
          ),
          if (BatteryOptimizationService.isSupported)
            ListTile(
              leading: const Icon(
                Icons.battery_alert_outlined,
                color: AppColors.purple,
              ),
              title: const Text('Background updates'),
              subtitle: const Text(
                'Let Whereabouts run freely so your location stays fresh '
                'when the app is closed.',
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
              onTap: BatteryOptimizationService.openSettings,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.directions_car_outlined,
                color: AppColors.purple),
            title: const Text('Drive detection'),
            value: _driveDetection,
            onChanged: (v) => setState(() => _driveDetection = v),
          ),
          const Divider(height: 1),
          const _SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined,
                color: AppColors.purple),
            title: const Text('Push notifications'),
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
          const Divider(height: 1),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline, color: AppColors.purple),
            title: Text('Whereabouts'),
            subtitle: Text('Version 0.1.0'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.sosRed),
            title: const Text(
              'Log Out',
              style: TextStyle(color: AppColors.sosRed),
            ),
            enabled: !_loggingOut,
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
