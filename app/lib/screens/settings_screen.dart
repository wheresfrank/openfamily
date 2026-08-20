import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'family_management_screen.dart';
import 'profile_screen.dart';
import 'welcome_screen.dart';

/// The Settings screen. A simple list of account, notification, location, and
/// privacy settings. Values are local toggles for now (no backend).
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

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthService.logout();
    } catch (_) {
      // Logout is best-effort; always navigate away even if clearing fails.
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
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined, color: AppColors.purple),
            title: const Text('Family management'),
            subtitle: const Text('Create, join, and manage members'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FamilyManagementScreen()),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('Location'),
          SwitchListTile(
            secondary: const Icon(Icons.location_on_outlined, color: AppColors.purple),
            title: const Text('Location sharing'),
            value: _locationSharing,
            onChanged: (v) => setState(() => _locationSharing = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.directions_car_outlined, color: AppColors.purple),
            title: const Text('Drive detection'),
            value: _driveDetection,
            onChanged: (v) => setState(() => _driveDetection = v),
          ),
          const Divider(height: 1),
          const _SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined, color: AppColors.purple),
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
