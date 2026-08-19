import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact "Step X of Y" progress indicator shown across the whole
/// onboarding journey (sign-up → permissions → circle → invite → locations),
/// not just inside the permissions step.
///
/// Use it as an [AppBar.bottom] so it sits consistently at the top of every
/// onboarding screen.
class OnboardingStepIndicator extends StatelessWidget
    implements PreferredSizeWidget {
  const OnboardingStepIndicator({
    super.key,
    required this.currentStep,
    this.totalSteps,
  });

  final int currentStep;

  /// Total steps in the journey. Null at a branch point (create vs. join)
  /// where the total depends on the path the user takes next, so we show
  /// "Step X" without a total rather than a total that will be contradicted
  /// on the very next screen.
  final int? totalSteps;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final int? total = totalSteps;
    final double? progress =
        total == null ? null : (currentStep / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            total == null ? 'Step $currentStep' : 'Step $currentStep of $total',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.purple,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.purple.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.purple),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
