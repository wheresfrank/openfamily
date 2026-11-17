import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart' show BiometricType;

import '../l10n/l10n.dart';
import '../services/locale_preference.dart';
import '../services/unit_preference.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/biometric_service.dart';
import '../services/location_sharing_service.dart';
import '../services/push_service.dart';
import '../services/server_config.dart';
import '../services/theme_preference.dart';
import '../theme/app_theme.dart';
import '../widgets/dot_grid.dart';
import 'profile_screen.dart';
import 'families_screen.dart';
import 'server_config_screen.dart';
import 'welcome_screen.dart';
import 'privacy_policy_screen.dart';

/// Build-time device-preview override. The device-frame preview is served by
/// the web engine but exists to rehearse mobile builds we cannot run (e.g.
/// iOS without a Mac); build it with
/// `--dart-define=OPENFAMILY_PLATFORM_OVERRIDE=ios` (or `android`) so
/// platform-copy reads as that platform. Empty by default, so platform
/// builds and genuine web builds are unaffected.
const String kPreviewPlatformOverride = String.fromEnvironment(
  'OPENFAMILY_PLATFORM_OVERRIDE',
);

/// One-line push-notification guidance for the Settings screen.
///
/// Platform-aware on purpose: Android's UnifiedPush guidance ("install the
/// ntfy app") must not leak into iOS (whose delivery rides APNs, nothing to
/// install) or the browser preview (where no push transport exists at all).
/// [isWeb] is passed explicitly because `kIsWeb` is a compile-time constant;
/// [previewPlatform] defaults to the build-time override so tests can pass
/// values explicitly.
String pushNotificationsSubtitle({
  required bool isWeb,
  TargetPlatform? platform,
  String previewPlatform = kPreviewPlatformOverride,
}) {
  // Device-preview override: present copy as the rehearsed platform even
  // though the rendering engine is the web.
  if (previewPlatform == 'android') {
    return CurrentL10n.value.pushHelpAndroid;
  }
  if (previewPlatform == 'ios') {
    return CurrentL10n.value.pushHelpIos;
  }
  if (isWeb) {
    return CurrentL10n.value.pushHelpWeb;
  }
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
      return CurrentL10n.value.pushHelpAndroid;
    case TargetPlatform.iOS:
      return CurrentL10n.value.pushHelpIos;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return CurrentL10n.value.pushHelpDefault;
  }
}

/// The Settings screen. Account profile is server-backed; the remaining
/// location and notification values are local toggles for now.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _locationSharing = true;
  bool _locationSharingLoading = true;
  bool _notifications = true;
  bool _notificationsLoading = true;
  bool _loggingOut = false;
  bool _deletingAccount = false;
  final BiometricService _biometricService = BiometricService.instance;
  bool _biometricLoading = true;
  bool _biometricUpdating = false;
  bool _biometricEnabled = false;
  BiometricAvailability? _biometricAvailability;
  String? _biometricError;
  Duration _lockGrace = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadBiometricSettings();
    _loadLocationSharing();
    _loadPushNotifications();
  }

  Future<void> _loadPushNotifications() async {
    final bool enabled = await PushService.load();
    if (!mounted) return;
    setState(() {
      _notifications = enabled;
      _notificationsLoading = false;
    });
  }

  Future<void> _setPushNotifications(bool enabled) async {
    setState(() => _notifications = enabled);
    await PushService.setEnabled(enabled);
  }

  Future<void> _loadLocationSharing() async {
    final bool enabled = await LocationSharingService.load();
    if (!mounted) return;
    setState(() {
      _locationSharing = enabled;
      _locationSharingLoading = false;
    });
  }

  Future<void> _setLocationSharing(bool enabled) async {
    setState(() => _locationSharing = enabled);
    await LocationSharingService.setEnabled(enabled);
  }

  Future<void> _loadBiometricSettings() async {
    try {
      final bool enabled = await _biometricService.isEnabled();
      final BiometricAvailability availability =
          await _biometricService.getAvailability();
      final Duration lockGrace = await _biometricService.lockGrace();
      if (!mounted) return;
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailability = availability;
        _lockGrace = lockGrace;
        _biometricLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _biometricLoading = false;
        _biometricError =
            context.l10n.biometricReadFailedReopen;
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
            ? context.l10n.biometricConfirmEnable
            : context.l10n.biometricConfirmDisable,
        requireEnabled: !enabled,
      );
      if (!mounted) return;
      if (!result.authenticated) {
        _finishBiometricUpdateWithError(
          result.error?.message ??
              context.l10n.biometricNotCompleted,
        );
        return;
      }
    }

    final bool saved = await _biometricService.setEnabled(enabled);
    if (!mounted) return;
    if (!saved) {
      _finishBiometricUpdateWithError(
        context.l10n.biometricSaveFailed,
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
          enabled ? context.l10n.biometricEnabled : context.l10n.biometricDisabled,
        ),
      ),
    );
  }

  Future<void> _setLockGrace(Duration? grace) async {
    if (grace == null) return;
    final bool saved = await _biometricService.setLockGrace(grace);
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.lockDelaySaveFailed)),
      );
      return;
    }
    setState(() => _lockGrace = grace);
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
    if (_biometricLoading) return context.l10n.checkingDevice;
    if (_biometricUpdating) return context.l10n.waitingConfirmation;
    if (_biometricError != null) return _biometricError!;
    final BiometricAvailability? availability = _biometricAvailability;
    if (availability == null || !availability.isAvailable) {
      return availability?.message ??
          context.l10n.biometricUnavailable;
    }

    final List<BiometricType> enrolled = availability.enrolledBiometrics;
    final bool hasFace = enrolled.contains(BiometricType.face);
    final bool hasFingerprint = enrolled.contains(BiometricType.fingerprint);
    final String method = hasFace && hasFingerprint
        ? context.l10n.biometricMethodBoth
        : hasFace
            ? context.l10n.biometricMethodFace
            : hasFingerprint
                ? context.l10n.biometricMethodFingerprint
                : context.l10n.biometricMethodGeneric;
    return _biometricEnabled
        ? context.l10n.biometricRequire(method)
        : context.l10n.biometricUse(method);
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
        SnackBar(
          content: Text(context.l10n.logOutFailed),
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

  Future<void> _changeServer() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.l10n.changeServerQuestion),
          content: Text(context.l10n.changeServerBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.actionContinue),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await AuthService.logout();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.signOutFailed),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const ServerConfigScreen(allowCancel: false),
      ),
      (route) => false,
    );
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.l10n.deleteAccountQuestion),
          content: Text(
            context.l10n.deleteAccountBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.sosRed),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.actionDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingAccount = true);
    try {
      await ApiClient.deleteAccount();
      await AuthService.logout(notifyServer: false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.status == 409
                ? e.message
                : e.status == 404
                    ? context.l10n.serverCannotDeleteAccounts
                    : e.message,
          ),
        ),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.deleteAccountFailed)),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: DotGridBackground(
        child: ListView(
          children: [
            _SectionHeader(context.l10n.sectionAccount),
          ListTile(
            leading: const Icon(Icons.person_outline, color: AppColors.purple),
            title: Text(context.l10n.profileTitle),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined, color: AppColors.purple),
            title: Text(context.l10n.familyLabel),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FamiliesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined, color: AppColors.purple),
            title: Text(context.l10n.serverLabel),
            subtitle: Text(
              ServerConfig.instance.apiBaseUrl.isEmpty
                  ? context.l10n.notSet
                  : ServerConfig.instance.apiBaseUrl,
            ),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: _changeServer,
          ),
            const Divider(height: 1),
            _SectionHeader(context.l10n.sectionAppearance),
            const _AppearanceTile(),
            const _UnitsTile(),
            const _LanguageTile(),
            const Divider(height: 1),
            _SectionHeader(context.l10n.privacySecurityHeader),
          SwitchListTile(
            secondary: const Icon(
              Icons.fingerprint,
              color: AppColors.purple,
            ),
            title: Text(context.l10n.biometricUnlock),
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
          if (_biometricEnabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.lock_clock_outlined,
                color: AppColors.purple,
              ),
              title: Text(context.l10n.lockDelay),
              subtitle: Text(
                context.l10n.lockDelayHelp,
              ),
              trailing: DropdownButton<Duration>(
                value: _lockGrace,
                underline: const SizedBox.shrink(),
                onChanged: _biometricUpdating ? null : _setLockGrace,
                items: [
                  DropdownMenuItem(
                    value: Duration.zero,
                    child: Text(context.l10n.lockImmediately),
                  ),
                  DropdownMenuItem(
                    value: Duration(seconds: 30),
                    child: Text(context.l10n.lock30Seconds),
                  ),
                  DropdownMenuItem(
                    value: Duration(minutes: 1),
                    child: Text(context.l10n.lock1Minute),
                  ),
                  DropdownMenuItem(
                    value: Duration(minutes: 5),
                    child: Text(context.l10n.lock5Minutes),
                  ),
                  DropdownMenuItem(
                    value: Duration(minutes: 15),
                    child: Text(context.l10n.lock15Minutes),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          _SectionHeader(context.l10n.sectionLocation),
          SwitchListTile(
            secondary:
                const Icon(Icons.location_on_outlined, color: AppColors.purple),
            title: Text(context.l10n.locationSharing),
            subtitle: Text(context.l10n.locationSharingHelp,
            ),
            value: _locationSharing,
            onChanged: _locationSharingLoading ? null : _setLocationSharing,
          ),
          if (BatteryOptimizationService.isSupported)
            ListTile(
              leading: const Icon(
                Icons.battery_alert_outlined,
                color: AppColors.purple,
              ),
              title: Text(context.l10n.backgroundUpdates),
              subtitle: Text(
                context.l10n.backgroundUpdatesHelp,
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                  onTap: BatteryOptimizationService.openSettings,
            ),
          const Divider(height: 1),
          _SectionHeader(context.l10n.notificationsTitle),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined,
                color: AppColors.purple),
            title: Text(context.l10n.pushNotifications),
            subtitle: Text(pushNotificationsSubtitle(isWeb: kIsWeb)),
            value: _notifications,
            onChanged: _notificationsLoading ? null : _setPushNotifications,
          ),
          const Divider(height: 1),
          _SectionHeader(context.l10n.sectionAbout),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.purple),
            title: Text(context.l10n.privacyPolicy),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline, color: AppColors.purple),
            title: Text('OpenFamily'),
            subtitle: Text('Version 0.1.0'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.sosRed),
            title: Text(
              context.l10n.actionLogOut,
              style: TextStyle(color: AppColors.sosRed),
            ),
            enabled: !_loggingOut && !_deletingAccount,
            onTap: _logout,
          ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.sosRed),
              title: Text(
                context.l10n.deleteAccount,
                style: TextStyle(color: AppColors.sosRed),
              ),
              enabled: !_loggingOut && !_deletingAccount,
              onTap: _deleteAccount,
            ),
          ],
        ),
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemePreference>(
      valueListenable: ThemePreferenceService.preference,
      builder: (context, preference, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.themeTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                preference == ThemePreference.system
                    ? context.l10n.themeHelpSystem
                    : preference == ThemePreference.light
                        ? context.l10n.themeHelpLight
                        : context.l10n.themeHelpDark,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<ThemePreference>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<ThemePreference>(
                    value: ThemePreference.system,
                    label: Text(context.l10n.themeSystem),
                    icon: Icon(Icons.brightness_auto, size: 18),
                  ),
                  ButtonSegment<ThemePreference>(
                    value: ThemePreference.light,
                    label: Text(context.l10n.themeLight),
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                  ),
                  ButtonSegment<ThemePreference>(
                    value: ThemePreference.dark,
                    label: Text(context.l10n.themeDark),
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                  ),
                ],
                selected: <ThemePreference>{preference},
                onSelectionChanged: (Set<ThemePreference> next) {
                  if (next.isEmpty) return;
                  ThemePreferenceService.setPreference(next.first);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnitsTile extends StatelessWidget {
  const _UnitsTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UnitPreference>(
      valueListenable: UnitPreferenceService.preference,
      builder: (context, preference, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.unitsSetting,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.unitsSettingHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<UnitPreference>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<UnitPreference>(
                    value: UnitPreference.system,
                    label: Text(context.l10n.unitsAuto),
                  ),
                  ButtonSegment<UnitPreference>(
                    value: UnitPreference.metric,
                    label: Text(context.l10n.unitsMetric),
                  ),
                  ButtonSegment<UnitPreference>(
                    value: UnitPreference.imperial,
                    label: Text(context.l10n.unitsImperial),
                  ),
                ],
                selected: <UnitPreference>{preference},
                onSelectionChanged: (Set<UnitPreference> next) {
                  if (next.isEmpty) return;
                  UnitPreferenceService.setPreference(next.first);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LanguagePreference>(
      valueListenable: LocalePreferenceService.preference,
      builder: (context, preference, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.languageSetting,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.languageSettingHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<LanguagePreference>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<LanguagePreference>(
                    value: LanguagePreference.system,
                    label: Text(context.l10n.languageAuto),
                  ),
                  ButtonSegment<LanguagePreference>(
                    value: LanguagePreference.english,
                    label: Text(context.l10n.languageEnglish),
                  ),
                  ButtonSegment<LanguagePreference>(
                    value: LanguagePreference.spanish,
                    label: Text(context.l10n.languageSpanish),
                  ),
                ],
                selected: <LanguagePreference>{preference},
                onSelectionChanged: (Set<LanguagePreference> next) {
                  if (next.isEmpty) return;
                  LocalePreferenceService.setPreference(next.first);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
