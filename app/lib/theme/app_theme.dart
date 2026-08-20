import 'package:flutter/material.dart';

/// Brand palette for Whereabouts.
///
/// The signature color is purple, paired with a warm pink accent. No source
/// pins an exact hex, so we use a confident violet as the primary and a warm
/// pink as the accent.
abstract final class AppColors {
  /// Signature brand purple — buttons, pins, accents.
  static const Color purple = Color(0xFF6C2BD9);

  /// Deeper purple for pressed/gradient states.
  static const Color purpleDark = Color(0xFF4C1D95);

  /// Pink accent (echoes the pink-and-purple app icon).
  static const Color pink = Color(0xFFE91E8C);

  /// Member status — normal / real-time / accurate.
  static const Color statusGreen = Color(0xFF2ECC71);

  /// Member status — low battery or accuracy warning.
  static const Color statusOrange = Color(0xFFFF9500);

  /// Member status — GPS accuracy issue (broader zone).
  static const Color statusPurple = Color(0xFFAF52DE);

  /// Accuracy / uncertainty range drawn around a member whose GPS fix is only
  /// approximate. Blue so it reads as a range rather than the purple
  /// brand/status accent.
  static const Color accuracyBlue = Color(0xFF3B82F6);

  /// Member status — updates stopped (phone off / no signal).
  static const Color statusGrey = Color(0xFF8E8E93);

  /// Member status — location error.
  static const Color statusRed = Color(0xFFFF3B30);

  /// SOS button fill — emergency red. Used at rest on the map (flat, no glow)
  /// and as the base emergency color on the SOS screen.
  static const Color sosRed = Color(0xFFE53935);

  /// SOS button fill — the escalated "intense" red used only during an active
  /// SOS countdown (paired with a red glow). Distinct from [sosRed] so the
  /// escalation is unmistakable.
  static const Color sosIntenseRed = Color(0xFFD50000);

  /// "Most-visited place" star.
  static const Color starYellow = Color(0xFFFFC107);

  /// Soft surface used by the bottom sheet and floating controls.
  static const Color surface = Color(0xFFFFFFFF);

  /// Very light purple tint for soft gradient surfaces.
  static const Color surfaceTint = Color(0xFFF6F1FD);

  /// Muted text on light surfaces.
  static const Color textMuted = Color(0xFF6E6E73);
}

/// Soft gradient surfaces used across the map screen for the "soft,
/// glanceable, reassuring" brand feel.
abstract final class AppGradients {
  /// Soft lavender wash for the bottom sheet and floating surfaces.
  static const LinearGradient softPurple = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF7F2FD), Color(0xFFEDE3FB)],
  );

  /// Brand purple→pink gradient for primary accents (FAB, cluster bubbles).
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.purple, AppColors.pink],
  );
}

/// Builds the app-wide purple theme.
ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.purple,
    primary: AppColors.purple,
    secondary: AppColors.pink,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.purple,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.purple,
      foregroundColor: Colors.white,
    ),
  );
}
