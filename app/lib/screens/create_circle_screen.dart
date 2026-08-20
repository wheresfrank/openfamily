import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/onboarding_step_indicator.dart';
import 'add_locations_screen.dart';
import 'invite_screen.dart';

/// Onboarding step: optionally name your new Circle, then invite family.
///
/// Naming is optional — if the field is left blank the Circle is auto-named
/// "My Circle" (the user can rename it later in Settings), so this step adds
/// no friction.
class CreateCircleScreen extends StatefulWidget {
  const CreateCircleScreen({super.key, this.onCreated});

  /// Called after the server creates the family when this screen is opened
  /// from Settings instead of onboarding.
  final VoidCallback? onCreated;

  @override
  State<CreateCircleScreen> createState() => _CreateCircleScreenState();
}

class _CreateCircleScreenState extends State<CreateCircleScreen> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _creating = false;

  Future<void> _create() async {
    if (_creating) return;
    final String trimmed = _name.text.trim();
    final String name = trimmed.isEmpty ? 'My Circle' : trimmed;
    setState(() => _creating = true);
    try {
      await ApiClient.post(
        '/families',
        body: <String, dynamic>{'name': name},
      );
      if (!mounted) return;
      if (widget.onCreated != null) {
        widget.onCreated!();
        Navigator.of(context).pop();
        return;
      }
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
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create a New Circle'),
        bottom: const OnboardingStepIndicator(currentStep: 4, totalSteps: 6),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Name your Circle',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Optional — this is the group your family will see on the map, '
                'e.g. "Family" or "The Smiths". Leave it blank and we\'ll call '
                'it "My Circle".',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Circle name (optional)',
                  hintText: 'My Circle',
                  border: OutlineInputBorder(),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _creating ? null : _create,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _creating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Circle', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
