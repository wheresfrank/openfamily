import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/onboarding_step_indicator.dart';
import 'add_locations_screen.dart';
import 'invite_screen.dart';

/// Onboarding step: optionally name your new family, then invite people.
///
/// Naming is optional — if the field is left blank the family is auto-named
/// "My Family" (the user can rename it later in Settings), so this step adds
/// no friction.
class CreateCircleScreen extends StatefulWidget {
  const CreateCircleScreen({super.key});

  @override
  State<CreateCircleScreen> createState() => _CreateCircleScreenState();
}

class _CreateCircleScreenState extends State<CreateCircleScreen> {
  final TextEditingController _name = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_submitting) return;
    final String trimmed = _name.text.trim();
    final String name = trimmed.isEmpty ? 'My Family' : trimmed;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.createFamily(name);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not create the family. Please try again.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => InviteScreen(
          circleName: name,
          doneLabel: 'Continue',
          step: 5,
          onDone: () => navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AddLocationsScreen(circleName: name, step: 6),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create a new family'),
        bottom: const OnboardingStepIndicator(currentStep: 4, totalSteps: 6),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Name your family',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Optional — this is the group your family will see on the map, '
                'e.g. "Family" or "The Smiths". Leave it blank and we\'ll call '
                'it "My Family".',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                autofocus: true,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Family name (optional)',
                  hintText: 'My Family',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.statusRed),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _submitting ? null : _create,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create family',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
