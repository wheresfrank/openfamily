import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The SOS flow: setup, tap-to-send, press-and-hold (discreet), a 10-second
/// countdown, and slide-to-cancel (swipe left).
///
/// * **Begin Setup** — first-run setup, then **Practice SOS**.
/// * **Tap** the SOS button to send immediately.
/// * **Press and hold** to arm discreetly; on release a 10-second countdown
///   begins. Slide the "Slide to Cancel" control **left** to abort before it
///   fires.
/// * Cancelling sends a "you are safe" follow-up to the family and contacts.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _SosPhase {
  setup,
  idle,
  holding,
  countdown,
  practice,
  sent,
  practiceDone,
  cancelled,
}

class _SosScreenState extends State<SosScreen> {
  _SosPhase _phase = _SosPhase.setup;
  int _countdown = 10;
  Timer? _timer;
  bool _practice = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _beginSetup() {
    setState(() => _phase = _SosPhase.idle);
  }

  void _startPractice() {
    _practice = true;
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _phase = _practice ? _SosPhase.practice : _SosPhase.countdown;
      _countdown = 10;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        _send();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _send() {
    _timer?.cancel();
    setState(() {
      _phase = _practice ? _SosPhase.practiceDone : _SosPhase.sent;
      _practice = false;
    });
  }

  void _cancel() {
    _timer?.cancel();
    setState(() {
      _phase = _practice ? _SosPhase.idle : _SosPhase.cancelled;
      _practice = false;
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _phase = _SosPhase.idle;
      _countdown = 10;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              _buildBody(),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _SosPhase.setup:
        return _SetupCard(onBeginSetup: _beginSetup);
      case _SosPhase.idle:
        return Column(
          children: [
            _SosButton(
              onTap: _send,
              onHoldStart: () => setState(() => _phase = _SosPhase.holding),
              onHoldEnd: _startCountdown,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _startPractice,
              child: const Text('Practice SOS'),
            ),
          ],
        );
      case _SosPhase.holding:
        return const _HoldingIndicator();
      case _SosPhase.countdown:
        return _Countdown(seconds: _countdown, onCancel: _cancel);
      case _SosPhase.practice:
        return _Countdown(
          seconds: _countdown,
          onCancel: _cancel,
          label: 'Practice SOS…',
        );
      case _SosPhase.sent:
        return _ResultCard(
          icon: Icons.check_circle,
          color: AppColors.statusGreen,
          title: 'SOS sent',
          subtitle:
              'Your family and emergency contacts have been alerted with your location.',
          actionLabel: 'Done',
          onAction: () => Navigator.of(context).pop(),
        );
      case _SosPhase.practiceDone:
        return _ResultCard(
          icon: Icons.check_circle,
          color: AppColors.purple,
          title: 'Practice complete',
          subtitle: 'No alert was sent. You are ready to send a real SOS.',
          actionLabel: 'Done',
          onAction: _reset,
        );
      case _SosPhase.cancelled:
        return _ResultCard(
          icon: Icons.info_outline,
          color: AppColors.purple,
          title: 'Cancelled',
          subtitle:
              'No SOS was sent. A "you are safe" follow-up was sent to your '
              'family and contacts.',
          actionLabel: 'Back',
          onAction: _reset,
        );
    }
  }
}

/// First-run setup card: "Begin Setup" → then "Practice SOS".
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.onBeginSetup});

  final VoidCallback onBeginSetup;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.sos, size: 72, color: AppColors.sosRed),
        const SizedBox(height: 16),
        const Text(
          'Set up SOS',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'SOS alerts your family and emergency contacts with your location, '
          'even on silent.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onBeginSetup,
          child: const Text('Begin Setup'),
        ),
      ],
    );
  }
}

/// The large SOS button: tap to send, press-and-hold to arm discreetly.
class _SosButton extends StatelessWidget {
  const _SosButton({
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          onLongPressStart: (_) => onHoldStart(),
          onLongPressEnd: (_) => onHoldEnd(),
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.sosRed,
              boxShadow: [
                BoxShadow(
                  color: AppColors.sosRed.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Only the "SOS" word is drawn. The `sos` glyph icon already
                // renders the letters "SOS", so drawing both would read the
                // word twice — keep just the text.
                Text(
                  'SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Tap to send · press and hold to arm discreetly',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _HoldingIndicator extends StatelessWidget {
  const _HoldingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(color: AppColors.sosRed),
        ),
        SizedBox(height: 16),
        Text(
          'Keep holding… release to start the countdown',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({
    required this.seconds,
    required this.onCancel,
    this.label = 'Sending SOS…',
  });

  final int seconds;
  final VoidCallback onCancel;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$seconds',
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w800,
            color: AppColors.sosRed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 16, color: AppColors.textMuted),
        ),
        const SizedBox(height: 32),
        _SlideToCancel(onCancel: onCancel),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

/// A "slide to cancel" control: drag the thumb **left** to cancel.
class _SlideToCancel extends StatefulWidget {
  const _SlideToCancel({required this.onCancel});

  final VoidCallback onCancel;

  @override
  State<_SlideToCancel> createState() => _SlideToCancelState();
}

class _SlideToCancelState extends State<_SlideToCancel> {
  static const double _trackWidth = 280;
  static const double _thumbSize = 48;

  double _drag = 0; // 0..1 (0 = right, 1 = fully slid left)

  @override
  Widget build(BuildContext context) {
    const double maxTravel = _trackWidth - _thumbSize - 8;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          // Swipe LEFT (negative dx) advances the slider.
          _drag = (_drag - details.delta.dx / maxTravel).clamp(0.0, 1.0);
        });
        if (_drag >= 1.0) {
          widget.onCancel();
        }
      },
      child: Container(
        width: _trackWidth,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0x11000000),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                'Slide to Cancel',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted.withValues(alpha: 0.7),
                ),
              ),
            ),
            Positioned(
              // Thumb starts on the right and moves left as _drag grows.
              left: 4 + maxTravel * (1 - _drag),
              top: 4,
              child: Container(
                width: _thumbSize,
                height: _thumbSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Color(0x33000000), blurRadius: 6),
                  ],
                ),
                child: const Icon(
                  Icons.chevron_left,
                  color: AppColors.sosRed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
