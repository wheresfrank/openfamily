import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/place.dart';
import '../services/api_client.dart';
import '../services/family_service.dart';
import '../services/geofence_service.dart';
import '../services/place_service.dart';
import '../theme/app_theme.dart';
import '../widgets/onboarding_step_indicator.dart';
import 'map_screen.dart';
import 'place_picker_screen.dart';

/// Onboarding step: add home/work/school places to the map (shared with all
/// family members), then land on the map.
///
/// Each place opens a real map picker that captures a lat/lon, address, and
/// radius — producing actual [Place] data, not a decorative toggle.
class AddLocationsScreen extends StatefulWidget {
  const AddLocationsScreen({super.key, this.circleName, this.step});

  final String? circleName;

  /// Onboarding step number (6 of 6). Null when reached outside onboarding.
  final int? step;

  @override
  State<AddLocationsScreen> createState() => _AddLocationsScreenState();
}

/// A preset place the user can add to the map.
class _PlacePreset {
  const _PlacePreset({required this.id, required this.icon});

  final String id;
  final IconData icon;

  /// The preset's default place name, in the current language.
  String name(AppLocalizations l10n) {
    switch (id) {
      case 'home':
        return l10n.placeHomeName;
      case 'work':
        return l10n.placeWorkName;
      case 'school':
        return l10n.placeSchoolName;
      default:
        return l10n.placeGymName;
    }
  }

  /// The one-line description shown until the place is set.
  String subtitle(AppLocalizations l10n) {
    switch (id) {
      case 'home':
        return l10n.placeHomeHint;
      case 'work':
        return l10n.placeWorkHint;
      case 'school':
        return l10n.placeSchoolHint;
      default:
        return l10n.placeGymHint;
    }
  }
}

/// Maps a preset id to the backend place type.
String _typeForPresetId(String id) {
  switch (id) {
    case 'home':
      return 'home';
    case 'work':
      return 'work';
    case 'school':
      return 'school';
    case 'gym':
      return 'gym';
    default:
      return 'custom';
  }
}

class _AddLocationsScreenState extends State<AddLocationsScreen> {
  static const List<_PlacePreset> _presets = [
    _PlacePreset(id: 'home', icon: Icons.home),
    _PlacePreset(id: 'work', icon: Icons.business_center),
    _PlacePreset(id: 'school', icon: Icons.school),
    _PlacePreset(id: 'gym', icon: Icons.fitness_center),
  ];

  /// Preset id → the real [Place] the user captured.
  final Map<String, Place> _places = <String, Place>{};

  /// Custom (non-preset) places the user added, in insertion order.
  final List<Place> _customPlaces = <Place>[];

  /// Re-entry guard so a double-tap on "Continue" doesn't fire concurrent POSTs.
  bool _finishing = false;

  /// Local ids of places already created on the backend, so a retry skips them
  /// (the backend's overlap check would reject duplicate submissions).
  final Set<String> _createdPlaceIds = <String>{};

  Future<void> _addPlace(_PlacePreset preset) async {
    final Place? place = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(
        builder: (_) => PlacePickerScreen(
          placeName: preset.name(context.l10n),
          icon: preset.icon,
          type: _typeForPresetId(preset.id),
          initial: _places[preset.id],
        ),
      ),
    );
    if (place != null && mounted) {
      setState(() => _places[preset.id] = place);
    }
  }

  /// Toggles the arrive/leave notification (bell) for a captured place.
  void _toggleAlerts(_PlacePreset preset) {
    final Place? place = _places[preset.id];
    if (place == null) return;
    setState(() {
      _places[preset.id] = place.copyWith(alertsOn: !place.alertsOn);
    });
  }

  /// Adds a custom (non-preset) place: prompt for a name, then open the map
  /// picker with that name and a generic pin icon.
  Future<void> _addCustomPlace() async {
    final String? name = await _promptForPlaceName();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final Place? place = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(
        builder: (_) => PlacePickerScreen(
          placeName: name.trim(),
          icon: Icons.place,
        ),
      ),
    );
    if (place != null && mounted) {
      setState(() => _customPlaces.add(place));
    }
  }

  /// Prompts for a custom place name; returns `null` when cancelled.
  ///
  /// Uses a captured local (no [TextEditingController]) so we don't dispose a
  /// controller while the dialog's exit transition is still running.
  Future<String?> _promptForPlaceName() async {
    String name = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.namePlaceTitle),
        content: TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onChanged: (String value) => name = value,
          decoration: InputDecoration(
            labelText: context.l10n.placeNameLabel,
            hintText: context.l10n.placeNameExampleGrandma,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(name),
            child: Text(context.l10n.actionNext),
          ),
        ],
      ),
    );
  }

  /// Toggles the arrive/leave notification (bell) for a custom place.
  void _toggleCustomAlerts(int index) {
    final Place place = _customPlaces[index];
    setState(() {
      _customPlaces[index] = place.copyWith(alertsOn: !place.alertsOn);
    });
  }

  /// Re-opens the picker to edit a custom place.
  Future<void> _editCustomPlace(int index) async {
    final Place? updated = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(
        builder: (_) => PlacePickerScreen(
          placeName: _customPlaces[index].name,
          icon: _customPlaces[index].icon,
          initial: _customPlaces[index],
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _customPlaces[index] = updated);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final List<Place> all = <Place>[
      ..._places.values,
      ..._customPlaces,
    ];
    var failed = false;
    String? callerUserId;
    var familyFetched = false;
    for (final Place place in all) {
      if (_createdPlaceIds.contains(place.id)) continue;
      try {
        final Place created = await PlaceService.createPlace(
          name: place.name,
          type: place.type,
          lat: place.position.latitude,
          lon: place.position.longitude,
          radiusMeters: place.radiusMeters,
          address: place.address,
        );
        _createdPlaceIds.add(place.id);
        if (place.alertsOn) {
          if (!familyFetched) {
            try {
              callerUserId = (await FamilyService().fetchFamily()).userId;
            } catch (_) {
              callerUserId = null;
            }
            familyFetched = true;
          }
          if (callerUserId != null && callerUserId.isNotEmpty) {
            try {
              await GeofenceService.createGeofence(
                placeId: created.id,
                userId: callerUserId,
                enterNotify: true,
                exitNotify: true,
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.savedButAlertsFailed(
                      place.name,
                      _errorMessage(e),
                    ),
                  ),
                ),
              );
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.savedButAlertsFailed(
                    place.name,
                    context.l10n.alertsToggleLater,
                  ),
                ),
              ),
            );
          }
        }
      } catch (e) {
        failed = true;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.couldNotSaveNamed(place.name, _errorMessage(e)),
            ),
          ),
        );
      }
    }
    if (!mounted) return;
    if (failed) {
      _finishing = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.placesSaveFailed,
          ),
        ),
      );
      return;
    }
    // Onboarding is complete; MapScreen starts background location reporting
    // once it is shown (and the app is in the foreground).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MapScreen()),
      (route) => false,
    );
  }

  String _errorMessage(Object e) {
    if (e is ApiException) return e.message;
    return context.l10n.pleaseTryAgain;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.addLocationsTitle),
        automaticallyImplyLeading: false,
        bottom: widget.step == null
            ? null
            : OnboardingStepIndicator(currentStep: widget.step!, totalSteps: 6),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    context.l10n.addPlacesHeading,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.placesSharedNote,
                    style: TextStyle(fontSize: 14, color: BrandTheme.of(context).muted),
                  ),
                  const SizedBox(height: 20),
                  for (final _PlacePreset preset in _presets) ...[
                    _PlaceCard(
                      preset: preset,
                      place: _places[preset.id],
                      onAdd: () => _addPlace(preset),
                      onToggleAlerts: () => _toggleAlerts(preset),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (int i = 0; i < _customPlaces.length; i++) ...[
                    _CustomPlaceCard(
                      place: _customPlaces[i],
                      onEdit: () => _editCustomPlace(i),
                      onToggleAlerts: () => _toggleCustomAlerts(i),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _AddCustomPlaceCard(onTap: _addCustomPlace),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _finish,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(context.l10n.actionContinue, style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _finish,
                    child: Text(context.l10n.actionSkipForNow),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A preset place card. Before adding it shows an "Add" button; once added it
/// shows the captured address + radius, a check, and a bell toggle for
/// arrive/leave notifications. Tapping the card re-opens the picker to edit.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.preset,
    required this.place,
    required this.onAdd,
    required this.onToggleAlerts,
  });

  final _PlacePreset preset;
  final Place? place;
  final VoidCallback onAdd;
  final VoidCallback onToggleAlerts;

  @override
  Widget build(BuildContext context) {
    final Place? p = place;
    return Material(
      color: BrandTheme.of(context).paper,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.purple.withValues(alpha: 0.12),
                ),
                child: Icon(preset.icon, color: BrandTheme.of(context).accentInk, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name(context.l10n),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p == null
                          ? preset.subtitle(context.l10n)
                          : '${p.address} · ${p.radiusLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        color: BrandTheme.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (p != null) ...[
                const Icon(Icons.check_circle, color: AppColors.statusGreen),
                const SizedBox(width: 4),
                // Bell toggle: arrive/leave notifications for this place.
                IconButton(
                  tooltip: p.alertsOn ? context.l10n.alertsOn : context.l10n.alertsOff,
                  icon: Icon(
                    p.alertsOn
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    color: p.alertsOn ? BrandTheme.of(context).accentInk : BrandTheme.of(context).muted,
                  ),
                  onPressed: onToggleAlerts,
                ),
              ] else
                OutlinedButton(
                  onPressed: onAdd,
                  child: Text(context.l10n.actionAdd),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A captured custom (non-preset) place: name, address + radius, a check, and
/// a bell toggle. Tapping the card re-opens the picker to edit.
class _CustomPlaceCard extends StatelessWidget {
  const _CustomPlaceCard({
    required this.place,
    required this.onEdit,
    required this.onToggleAlerts,
  });

  final Place place;
  final VoidCallback onEdit;
  final VoidCallback onToggleAlerts;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrandTheme.of(context).paper,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.purple.withValues(alpha: 0.12),
                ),
                child: Icon(place.icon, color: BrandTheme.of(context).accentInk, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${place.address} · ${place.radiusLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        color: BrandTheme.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle, color: AppColors.statusGreen),
              const SizedBox(width: 4),
              IconButton(
                tooltip: place.alertsOn ? context.l10n.alertsOn : context.l10n.alertsOff,
                icon: Icon(
                  place.alertsOn
                      ? Icons.notifications_active
                      : Icons.notifications_off,
                  color: place.alertsOn ? BrandTheme.of(context).accentInk : BrandTheme.of(context).muted,
                ),
                onPressed: onToggleAlerts,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed "add a custom place" affordance at the bottom of the preset list.
class _AddCustomPlaceCard extends StatelessWidget {
  const _AddCustomPlaceCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.add_location_alt_outlined,
                  color: BrandTheme.of(context).accentInk, size: 24),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.addCustomPlace,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BrandTheme.of(context).accentInk,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      context.l10n.customPlaceHint,
                      style: TextStyle(
                        fontSize: 13,
                        color: BrandTheme.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: BrandTheme.of(context).muted),
            ],
          ),
        ),
      ),
    );
  }
}
