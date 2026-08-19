import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The Help Alert flow, reached from the map's `+` action sheet.
///
/// Sends a non-emergency help request to the Circle (distinct from the
/// emergency SOS). On confirm it shows a success state (a real screen, not a
/// snackbar no-op).
class HelpAlertScreen extends StatefulWidget {
  const HelpAlertScreen({super.key});

  @override
  State<HelpAlertScreen> createState() => _HelpAlertScreenState();
}

class _HelpAlertScreenState extends State<HelpAlertScreen> {
  bool _sent = false;

  void _send() {
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help Alert')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _sent ? _buildSent() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.campaign_outlined, size: 56, color: AppColors.purple),
        const SizedBox(height: 16),
        const Text(
          'Ask your Circle for help',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Send a non-emergency help alert with your location. Your Circle '
          'members get a notification and can see where you are.',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        const Text(
          'For a real emergency, use SOS instead.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.sosRed,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _send,
            child: const Text('Send Help Alert'),
          ),
        ),
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 72, color: AppColors.statusGreen),
        const SizedBox(height: 16),
        const Text(
          'Help alert sent',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your Circle has been notified with your location.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
