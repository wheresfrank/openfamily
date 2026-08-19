import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';
import '../widgets/onboarding_step_indicator.dart';
import 'login_screen.dart';
import 'permissions_screen.dart';

/// A practical email format check (not RFC-exhaustive).
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// A practical phone format check: optional leading `+`, then digits with
/// spaces, dashes, dots, or parentheses — 7 to 15 digits total.
final RegExp _phonePattern = RegExp(r'^\+?[0-9][0-9\s\-().]*$');

bool _isValidPhone(String phone) {
  final String trimmed = phone.trim();
  if (!_phonePattern.hasMatch(trimmed)) return false;
  final int digits = trimmed.replaceAll(RegExp(r'\D'), '').length;
  return digits >= 7 && digits <= 15;
}

/// Sign-up: phone number, email address, password, and a profile photo.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  XFile? _photo;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _submit() async {
    final String name = _name.text.trim();
    final String phone = _phone.text.trim();
    final String email = _email.text.trim();
    final String password = _password.text;

    if (name.isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    if (phone.isNotEmpty && !_isValidPhone(phone)) {
      setState(() => _error =
          'Enter a valid phone number (e.g. +1 555 123 4567).');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    // A profile photo is a step, not a blocker: the user can continue without
    // one and add it later in Settings. We nudge (below) rather than gate.

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AuthService.signUp(
        name: name,
        email: email,
        password: password,
        phone: phone.isEmpty ? null : phone,
        photoPath: _photo?.path,
      );
    } on AccountCreatedException catch (e) {
      // The account was created but we couldn't establish a session. Send the
      // user to log in rather than leaving them to re-submit (which would 409).
      if (!mounted) return;
      _redirectToLogin(e.message);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409) {
        // Email already registered — offer to log in instead.
        _redirectToLogin('This email is already registered. Please log in.');
        return;
      }
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Something went wrong. Please try again.';
      });
      return;
    }

    // Auth succeeded; register the device (best-effort, non-blocking).
    try {
      await DeviceService.ensureRegistered();
    } on SessionExpiredException {
      // Session expired during device registration; the app root already
      // redirected to login. Abort navigation so we don't land on a protected
      // screen with cleared tokens.
      return;
    } catch (_) {
      // Non-fatal: device registration can be retried later.
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PermissionsScreen()),
    );
  }

  /// Shows [message] and redirects to the login screen (replacing this one).
  void _redirectToLogin(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    // Clear the stack so only one LoginScreen is ever on it (a plain
    // pushReplacement could stack duplicates when the sign-up screen was
    // itself pushed on top of an existing LoginScreen).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create your account'),
        bottom: const OnboardingStepIndicator(currentStep: 1, totalSteps: 6),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  hintText: 'Alex Rivera',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number (optional)',
                  hintText: '+1 555 123 4567',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(child: _PhotoPicker(photo: _photo, onTap: _pickPhoto)),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.statusRed,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
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
                      : const Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your email is used to sign you in. Your data stays on your '
                'own server — not ours, not anyone\'s.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account?',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    ),
                    child: const Text('Log In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable circular profile-photo picker with a live preview.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.photo, required this.onTap});

  final XFile? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceTint,
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: photo != null
                  ? _PhotoPreview(photo: photo!)
                  : const Icon(
                      Icons.add_a_photo_outlined,
                      size: 36,
                      color: AppColors.purple,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            photo == null ? 'Add a profile photo' : 'Change photo',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.purple,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Optional — helps your family recognize you on the map.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Displays a picked [XFile] image without `dart:io` (web-safe): reads the
/// bytes once and renders them with [Image.memory].
class _PhotoPreview extends StatefulWidget {
  const _PhotoPreview({required this.photo});

  final XFile photo;

  @override
  State<_PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends State<_PhotoPreview> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Uint8List bytes = await widget.photo.readAsBytes();
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;
    if (bytes == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.memory(bytes, fit: BoxFit.cover);
  }
}
