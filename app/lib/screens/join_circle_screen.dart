import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/api_client.dart';
import '../services/join_service.dart';
import '../theme/app_theme.dart';
import '../widgets/onboarding_step_indicator.dart';

/// The join-a-family flow, reached from the map's `+` action sheet, the
/// family switcher's `+` chip, and onboarding.
///
/// Accepts an alphanumeric invite code and validates it against the server —
/// an invalid/unknown code shows a clear error (no false success).
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
    if (code.isEmpty) {
      setState(() => _error = context.l10n.enterInviteCodeTitle);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final bool ok = await JoinService.join(code);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (ok) {
          _joined = true;
        } else {
          _error = context.l10n.inviteCodeInvalid;
        }
      });
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = context.l10n.joinFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.joinFamilyTitle),
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
        Text(
          context.l10n.enterInviteCodeTitle,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.enterInviteCodeBody,
          style: TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: context.l10n.inviteCodeLabel,
            hintText: context.l10n.inviteCodeExample,
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
                  : Text(context.l10n.actionJoin),
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
        Text(
          context.l10n.familyJoinedTitle,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.familyJoinedBody,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            if (widget.onDone != null) {
              widget.onDone!();
            } else {
              Navigator.of(context).pop(true);
            }
          },
          child: Text(context.l10n.actionDone),
        ),
      ],
    );
  }
}
