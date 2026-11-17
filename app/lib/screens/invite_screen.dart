import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
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
            SnackBar(content: Text(context.l10n.inviteCodeCreateFailed)),
          );
        }
        return;
      }
      if (!mounted) return;
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
          SnackBar(content: Text(context.l10n.shareSheetFailed)),
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
      SnackBar(content: Text(context.l10n.codeCopied)),
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
        title: Text(context.l10n.actionInvite),
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
    final String circle = widget.circleName ?? context.l10n.yourFamilyFallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.person_add_alt_1, size: 64, color: BrandTheme.of(context).accentInk),
        const SizedBox(height: 16),
        Text(
          context.l10n.inviteYourFamily,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.shareCodeToJoin(circle),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: BrandTheme.of(context).muted),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _sendCode,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(context.l10n.sendCode, style: TextStyle(fontSize: 16)),
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
        Text(
          context.l10n.yourInviteCode,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.shareCodeHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: BrandTheme.of(context).muted),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: BrandTheme.of(context).paper,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                _code!,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: BrandTheme.of(context).accentInk,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ServerConfig.instance.apiBaseUrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: BrandTheme.of(context).muted,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy, size: 18),
                label: Text(context.l10n.copyCode),
              ),
            ],
          ),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _sendCode,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(context.l10n.sendCode, style: TextStyle(fontSize: 16)),
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
