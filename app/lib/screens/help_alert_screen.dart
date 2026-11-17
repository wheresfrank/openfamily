import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// The Help Alert flow, reached from the map's `+` action sheet.
///
/// Sends a non-emergency help request to the family (distinct from SOS —
/// emergency contacts are not notified).
class HelpAlertScreen extends StatefulWidget {
  const HelpAlertScreen({super.key});

  @override
  State<HelpAlertScreen> createState() => _HelpAlertScreenState();
}

class _HelpAlertScreenState extends State<HelpAlertScreen> {
  bool _sent = false;
  bool _sending = false;
  String? _error;
  double? _lat;
  double? _lon;
  final TextEditingController _note = TextEditingController();

  /// Matches the server's limit on an alert note.
  static const int _maxNoteLength = 280;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final position = await LocationService.currentPosition();
    if (!mounted || position == null) return;
    setState(() {
      _lat = position.latitude;
      _lon = position.longitude;
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> body = <String, dynamic>{};
      if (_lat != null && _lon != null) {
        body['lat'] = _lat;
        body['lon'] = _lon;
      }
      final String note = _note.text.trim();
      if (note.isNotEmpty) body['note'] = note;
      await ApiClient.post('/alerts/help', body: body);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sending = false;
      });
    } on SessionExpiredException {
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = context.l10n.helpAlertFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.helpAlertTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _sent ? _buildSent() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final List<String> presets = <String>[
      context.l10n.helpPresetCar,
      context.l10n.helpPresetUnsafe,
      context.l10n.helpPresetLost,
      context.l10n.helpPresetFollowed,
      context.l10n.helpPresetAccident,
      context.l10n.helpPresetRide,
      context.l10n.helpPresetUnwell,
    ];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 56,
            color: BrandTheme.of(context).accentInk,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.helpAlertSubtitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.helpAlertExplainer,
            style: TextStyle(fontSize: 14, color: BrandTheme.of(context).muted),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.helpAlertUseSos,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.sosRed,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.helpQuickMessages,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _note,
            builder: (BuildContext context, TextEditingValue value, _) {
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final String preset in presets)
                    ChoiceChip(
                      label: Text(preset),
                      selected: value.text.trim() == preset,
                      onSelected: _sending
                          ? null
                          : (bool selected) {
                              _note.text = selected ? preset : '';
                              _note.selection = TextSelection.collapsed(
                                offset: _note.text.length,
                              );
                            },
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            enabled: !_sending,
            maxLength: _maxNoteLength,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.helpMessageLabel,
              hintText: context.l10n.helpMessageHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.sosRed)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onAccent,
                      ),
                    )
                  : Text(context.l10n.sendHelpAlert),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 72, color: AppColors.statusGreen),
        const SizedBox(height: 16),
        Text(
          context.l10n.helpAlertSentTitle,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.helpAlertSentBody,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: BrandTheme.of(context).muted),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.actionDone),
        ),
      ],
    );
  }
}
