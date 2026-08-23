import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand tokens for Whereabouts.
///
/// Light is Ice (lime on blue-grey paper). Dark is Night (brighter lime on
/// charcoal). Lime is the action color — buttons and pins — not a wash.
abstract final class AppColors {
  /// Ice / light lime fill.
  static const Color accent = Color(0xFF8FD400);

  /// Night lime fill — a step brighter so it holds on charcoal.
  static const Color accentBright = Color(0xFFA3E635);

  /// Pressed / dark stop on the brand gradient.
  static const Color accentPressed = Color(0xFF78B400);

  /// Ink on a lime fill. White on lime fails AA.
  static const Color onAccent = Color(0xFF111827);

  /// Second stop on brand washes (login, marks).
  static const Color spark = Color(0xFFC6E86A);

  /// Secondary / link / second-person pin on Ice.
  static const Color sky = Color(0xFF0284C7);

  /// Compat aliases — existing call sites keep compiling.
  static const Color purple = accent;
  static const Color purpleDark = accentPressed;
  static const Color pink = spark;

  static const Color statusGreen = Color(0xFF2ECC71);
  static const Color statusOrange = Color(0xFFFF9500);
  static const Color statusPurple = Color(0xFFAF52DE);
  static const Color accuracyBlue = Color(0xFF3B82F6);
  static const Color statusGrey = Color(0xFF8E8E93);
  static const Color statusRed = Color(0xFFFF3B30);
  static const Color sosRed = Color(0xFFE53935);
  static const Color sosIntenseRed = Color(0xFFD50000);
  static const Color starYellow = Color(0xFFFFC107);

  static const Color icePaper = Color(0xFFEEF2F6);
  static const Color iceSurface = Color(0xFFF8FAFC);
  static const Color iceInk = Color(0xFF111827);
  static const Color iceMuted = Color(0xFF54707C);
  static const Color iceBorder = Color(0xFFC9D4DF);
  static const Color iceDot = Color(0x1F0F172A);

  static const Color nightPaper = Color(0xFF1C1E22);
  static const Color nightSurface = Color(0xFF2A2D33);
  static const Color nightInk = Color(0xFFF4F5F7);
  static const Color nightMuted = Color(0xFF9CA3AF);
  static const Color nightBorder = Color(0xFF3F444C);
  static const Color nightDot = Color(0x29FFFFFF);

  /// Light-only fallbacks for older hardcoded surfaces.
  static const Color surface = iceSurface;
  static const Color surfaceTint = icePaper;
  static const Color textMuted = iceMuted;
}

/// Extra brand colors that change with [ThemeData.brightness].
@immutable
class BrandTheme extends ThemeExtension<BrandTheme> {
  const BrandTheme({
    required this.paper,
    required this.sheet,
    required this.dot,
    required this.accent,
    required this.onAccent,
    required this.spark,
  });

  static const BrandTheme ice = BrandTheme(
    paper: AppColors.icePaper,
    sheet: AppColors.iceSurface,
    dot: AppColors.iceDot,
    accent: AppColors.accent,
    onAccent: AppColors.onAccent,
    spark: AppColors.spark,
  );

  static const BrandTheme night = BrandTheme(
    paper: AppColors.nightPaper,
    sheet: AppColors.nightSurface,
    dot: AppColors.nightDot,
    accent: AppColors.accentBright,
    onAccent: AppColors.onAccent,
    spark: Color(0xFFD9F99D),
  );

  final Color paper;
  final Color sheet;
  final Color dot;
  final Color accent;
  final Color onAccent;
  final Color spark;

  static BrandTheme of(BuildContext context) {
    return Theme.of(context).extension<BrandTheme>() ?? BrandTheme.ice;
  }

  @override
  BrandTheme copyWith({
    Color? paper,
    Color? sheet,
    Color? dot,
    Color? accent,
    Color? onAccent,
    Color? spark,
  }) {
    return BrandTheme(
      paper: paper ?? this.paper,
      sheet: sheet ?? this.sheet,
      dot: dot ?? this.dot,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      spark: spark ?? this.spark,
    );
  }

  @override
  BrandTheme lerp(ThemeExtension<BrandTheme>? other, double t) {
    if (other is! BrandTheme) return this;
    return BrandTheme(
      paper: Color.lerp(paper, other.paper, t) ?? paper,
      sheet: Color.lerp(sheet, other.sheet, t) ?? sheet,
      dot: Color.lerp(dot, other.dot, t) ?? dot,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      onAccent: Color.lerp(onAccent, other.onAccent, t) ?? onAccent,
      spark: Color.lerp(spark, other.spark, t) ?? spark,
    );
  }
}

/// Brand lime gradient. Stops follow the active [BrandTheme] when a context
/// is available; otherwise Ice.
abstract final class AppGradients {
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.accentPressed, AppColors.accent, AppColors.spark],
  );

  static const LinearGradient softPurple = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.icePaper, AppColors.iceSurface],
  );

  static LinearGradient brandOf(BuildContext context) {
    final BrandTheme brand = BrandTheme.of(context);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.accentPressed, brand.accent, brand.spark],
    );
  }
}

ThemeData buildAppTheme() => buildLightTheme();

ThemeData buildLightTheme() {
  return _buildTheme(
    brightness: Brightness.light,
    brand: BrandTheme.ice,
    primary: AppColors.accent,
    surface: AppColors.iceSurface,
    paper: AppColors.icePaper,
    onSurface: AppColors.iceInk,
    muted: AppColors.iceMuted,
    overlay: SystemUiOverlayStyle.dark,
  );
}

ThemeData buildDarkTheme() {
  return _buildTheme(
    brightness: Brightness.dark,
    brand: BrandTheme.night,
    primary: AppColors.accentBright,
    surface: AppColors.nightSurface,
    paper: AppColors.nightPaper,
    onSurface: AppColors.nightInk,
    muted: AppColors.nightMuted,
    overlay: SystemUiOverlayStyle.light,
  );
}

ThemeData _buildTheme({
  required Brightness brightness,
  required BrandTheme brand,
  required Color primary,
  required Color surface,
  required Color paper,
  required Color onSurface,
  required Color muted,
  required SystemUiOverlayStyle overlay,
}) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: brightness,
    primary: primary,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.sky,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: muted,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    extensions: <ThemeExtension<dynamic>>[brand],
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: onSurface,
      elevation: 0,
      systemOverlayStyle: overlay,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: AppColors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: AppColors.onAccent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.onAccent
            : null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? primary : null;
      }),
    ),
  );
}
