import 'package:flutter/material.dart';

import '../services/join_service.dart';
import '../theme/app_theme.dart';
import '../widgets/onboarding_step_indicator.dart';

/// The Join a Circle flow, reached from the map's `+` action sheet, the
/// Circle switcher's `+` chip, and onboarding.
///
/// Accepts a 6-digit invite code and validates it against the server — an
/// invalid/unknown code shows a clear error (no false success).
class JoinCircleScreen extends StatefulWidget {
  const JoinCircleScreen({
    super.key,
    this.onDone,
    this.step,
    this.totalSteps = 4,
  });

  /// When provided, called instead of popping on "Done" (used by onboarding
  /// so joining lands on the map).
  final VoidCallback? onDone;

  /// Onboarding step number (4 of 4). Null when reached outside onboarding.
  final int? step;

  /// Total onboarding steps for the join path (4: sign-up → permissions →
  /// create-or-join → join). The join path is shorter than the create path
  /// (6 steps), so the indicator must not claim "of 6" and then skip 5–6.
  final int totalSteps;

  @override
  State<JoinCircleScreen> createState() => _JoinCircleScreenState();
}

class _JoinCircleScreenState extends State<JoinCircleScreen> {
  final TextEditingController _code = TextEditingController();
  String? _error;
  bool _joined = false;
  bool _submitting = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final String code = _code.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter a valid 6-digit code');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final bool ok = await JoinService.join(code);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (ok) {
        _joined = true;
      } else {
        _error = 'That code isn\'t valid. Check it and try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a Circle'),
        bottom: widget.step == null
            ? null
            : OnboardingStepIndicator(
                currentStep: widget.step!,
                totalSteps: widget.totalSteps,
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _joined ? _buildJoined() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter your invite code',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ask a Circle member for the 6-digit code to join their Circle.',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: '6-digit invite code',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _join,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Join'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJoined() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 72, color: AppColors.statusGreen),
        const SizedBox(height: 16),
        const Text(
          'Circle joined',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'You are now a member of the Circle.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            if (widget.onDone != null) {
              widget.onDone!();
            } else {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
