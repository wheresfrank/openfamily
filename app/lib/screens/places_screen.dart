import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/place.dart';
import '../services/api_client.dart';
import '../services/family_service.dart';
import '../services/geofence_service.dart';
import '../services/place_service.dart';
import '../theme/app_theme.dart';
import 'place_picker_screen.dart';

/// The Places / geofences list screen. Lists saved Places with their radius
/// and an arrive/leave alert toggle, and lets the user add a new Place.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final FamilyService _familyService = FamilyService();

  List<Place>? _places;
  String? _error;
  String _role = 'member';
  String _userId = '';

  /// True while a geofence create/delete is in flight, to disable the toggle.
  bool _toggling = false;

  /// Whether the caller can manage places (add/delete). Children cannot.
  bool get _canManage => _role != 'child';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _places = null;
      _error = null;
    });
    try {
      final List<dynamic> results = await Future.wait<dynamic>([
        _familyService.fetchFamily(),
        PlaceService.fetchPlaces(),
        GeofenceService.fetchGeofences(),
      ]);
      final FamilyInfo family = results[0] as FamilyInfo;
      final List<Place> places = results[1] as List<Place>;
      final List<Geofence> geofences = results[2] as List<Geofence>;
      if (!mounted) return;
      setState(() {
        _role = family.role;
        _userId = family.userId;
        _places = _applyGeofences(places, geofences);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e));
    }
  }

  /// Marks each place's [Place.alertsOn] from the geofences that belong to the
  /// caller (or are family-wide, i.e. `user_id == null`).
  List<Place> _applyGeofences(List<Place> places, List<Geofence> geofences) {
    return places.map((Place p) {
      Geofence? match;
      for (final Geofence g in geofences) {
        if (g.placeId == p.id && (g.userId == null || g.userId == _userId)) {
          match = g;
          break;
        }
      }
      if (match == null) {
        return p.copyWith(alertsOn: false, geofenceId: Place.clearGeofence);
      }
      return p.copyWith(alertsOn: true, geofenceId: match.id);
    }).toList();
  }

  String _errorMessage(Object e) {
    if (e is ApiException) return e.message;
    return context.l10n.loadPlacesFailed;
  }

  Future<void> _addPlace() async {
    final Place? picked = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(
        builder: (_) => const PlacePickerScreen(
          placeName: '',
          icon: Icons.place_outlined,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final Place created = await PlaceService.createPlace(
        name: picked.name,
        type: picked.type,
        lat: picked.position.latitude,
        lon: picked.position.longitude,
        radiusMeters: picked.radiusMeters,
        address: picked.address,
      );
      if (!mounted) return;
      setState(() => _places = <Place>[...?_places, created]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    }
  }

  Future<void> _editPlace(int index) async {
    final Place place = _places![index];
    final Place? picked = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(
        builder: (_) => PlacePickerScreen(
          placeName: place.name,
          icon: place.icon,
          type: place.type,
          initial: place,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final Place saved = await PlaceService.updatePlace(
        id: place.id,
        name: picked.name,
        lat: picked.position.latitude,
        lon: picked.position.longitude,
        radiusMeters: picked.radiusMeters,
        address: picked.address,
      );
      if (!mounted) return;
      setState(() {
        // Keep the client-side alert state; it is not part of the place.
        _places![index] = saved.copyWith(
          alertsOn: place.alertsOn,
          geofenceId: place.geofenceId,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    }
  }

  Future<void> _deletePlace(Place place) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deletePlaceQuestion),
        content: Text(context.l10n.removePlaceBody(place.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await PlaceService.deletePlace(place.id);
      if (!mounted) return;
      setState(() {
        _places = _places!.where((Place p) => p.id != place.id).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    }
  }

  Future<void> _toggleAlerts(int index) async {
    if (_toggling) return;
    final List<Place> places = _places!;
    final Place place = places[index];
    final bool turningOn = !place.alertsOn;

    // Optimistically flip the toggle; revert on failure.
    setState(() {
      _toggling = true;
      places[index] = place.copyWith(alertsOn: turningOn);
    });

    try {
      if (turningOn) {
        final Geofence geofence = await GeofenceService.createGeofence(
          placeId: place.id,
          userId: _userId.isEmpty ? null : _userId,
          enterNotify: true,
          exitNotify: true,
        );
        if (!mounted) return;
        setState(() {
          places[index] = places[index].copyWith(geofenceId: geofence.id);
        });
      } else {
        final String? geofenceId = place.geofenceId;
        if (geofenceId != null) {
          await GeofenceService.deleteGeofence(geofenceId);
        }
        if (!mounted) return;
        setState(() {
          places[index] = places[index].copyWith(
            geofenceId: Place.clearGeofence,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => places[index] = place); // revert
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _toggling = false);
      } else {
        _toggling = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.placesTitle)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(context.l10n.actionRetry)),
          ],
        ),
      );
    }
    final List<Place>? places = _places;
    if (places == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (places.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              context.l10n.noPlacesYet,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          if (_canManage) _AddPlaceTile(onTap: _addPlace),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (int i = 0; i < places.length; i++)
          _PlaceTile(
            place: places[i],
            onToggleAlerts: _canManage ? () => _toggleAlerts(i) : null,
            toggling: _toggling,
            onEdit: _canManage ? () => _editPlace(i) : null,
            onDelete: _canManage ? () => _deletePlace(places[i]) : null,
          ),
        if (_canManage) _AddPlaceTile(onTap: _addPlace),
      ],
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.place,
    required this.onToggleAlerts,
    required this.toggling,
    required this.onEdit,
    required this.onDelete,
  });

  final Place place;
  final VoidCallback? onToggleAlerts;
  final bool toggling;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final String subtitle = place.address.isEmpty
        ? place.radiusLabel
        : '${place.address} · ${place.radiusLabel}';
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.purple.withValues(alpha: 0.12),
        ),
        child: Icon(place.icon, color: AppColors.purple, size: 22),
      ),
      title: Text(
        place.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleAlerts != null)
            IconButton(
              tooltip: place.alertsOn ? context.l10n.alertsOn : context.l10n.alertsOff,
              icon: Icon(
                place.alertsOn
                    ? Icons.notifications_active
                    : Icons.notifications_off,
                color: place.alertsOn ? AppColors.purple : AppColors.textMuted,
              ),
              onPressed: toggling ? null : onToggleAlerts,
            ),
          if (onEdit != null)
            IconButton(
              tooltip: context.l10n.editPlace,
              icon: const Icon(Icons.edit_outlined, color: AppColors.textMuted),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              tooltip: context.l10n.deletePlace,
              icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _AddPlaceTile extends StatelessWidget {
  const _AddPlaceTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.add_circle_outline, color: AppColors.purple),
      title: Text(
        context.l10n.addAPlace,
        style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
