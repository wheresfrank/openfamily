import 'package:flutter/material.dart';

import '../services/server_config.dart';
import '../theme/app_theme.dart';
import 'welcome_screen.dart';

/// First-launch server configuration screen.
///
/// Shown when no API URL is configured (neither `--dart-define` nor a
/// previously entered value). The user enters their Whereabouts server URL
/// (e.g. `https://whereabouts.example.com`), which is persisted to
/// `shared_preferences` and used for all subsequent API + WebSocket calls.
class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter your server URL.');
      return;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.scheme.isEmpty ||
        parsed.host.isEmpty ||
        !(parsed.scheme == 'http' || parsed.scheme == 'https')) {
      setState(() => _error = "That doesn't look like a valid URL.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ServerConfig.instance.setUrl(url);
      if (mounted) {
        // Replace this screen with the welcome screen so the user can't
        // navigate back to the server config. pushAndRemoveUntil is needed
        // because ServerConfigScreen is the root — pop() would show black.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: AppGradients.brand,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Whereabouts',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.purple,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your server address to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://whereabouts.example.com',
                  prefixIcon: const Icon(Icons.dns_outlined),
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect', style: TextStyle(fontSize: 16)),
                ),
              ),
              const Spacer(),
              const Text(
                'Your server URL is stored on this device only.\n'
                'It is sent nowhere except your own server.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}