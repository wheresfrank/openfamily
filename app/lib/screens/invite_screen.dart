import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/invite_service.dart';
import '../services/server_config.dart';
import '../theme/app_theme.dart';
import '../widgets/onboarding_step_indicator.dart';

/// The "Invite" step: explain inviting, then "Send Code" generates an
/// alphanumeric code and opens the native share sheet (pick a share app →
/// send). The code is also tap-to-copy.
///
/// Used by both the map's `+` → Invite flow and onboarding (where [onDone]
/// continues to the next step).
class InviteScreen extends StatefulWidget {
  const InviteScreen({
    super.key,
    this.circleName,
    this.onDone,
    this.doneLabel = 'Done',
    this.step,
  });

  final String? circleName;
  final VoidCallback? onDone;
  final String doneLabel;

  /// Onboarding step number (5 of 6). Null when reached outside onboarding.
  final int? step;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  String? _code;

  Future<void> _sendCode() async {
    String code = _code ?? '';
    if (code.isEmpty) {
      try {
        code = await InviteService.createCode();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not create an invite code')),
          );
        }
        return;
      }
      setState(() => _code = code);
    }
    try {
      await Share.share(
        InviteService.shareMessage(code),
        subject: InviteService.shareSubject,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the share sheet')),
        );
      }
    }
  }

  Future<void> _copyCode() async {
    final String? code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied to clipboard')),
    );
  }

  void _done() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite'),
        bottom: widget.step == null
            ? null
            : OnboardingStepIndicator(currentStep: widget.step!, totalSteps: 6),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _code == null ? _buildInvite() : _buildSendCode(),
        ),
      ),
    );
  }

  Widget _buildInvite() {
    final String circle = widget.circleName ?? 'your family';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Icon(Icons.person_add_alt_1, size: 64, color: AppColors.purple),
        const SizedBox(height: 16),
        const Text(
          'Invite your family',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Share a code so your family can join $circle and appear on your map.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.textMuted),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _sendCode,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Send Code', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _buildSendCode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Text(
          'Your invite code',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Share it so your family can join.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                _code!,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ServerConfig.instance.apiBaseUrl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy code'),
              ),
            ],
          ),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _sendCode,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Send Code', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _done,
          child: Text(widget.doneLabel),
        ),
      ],
    );
  }
}
