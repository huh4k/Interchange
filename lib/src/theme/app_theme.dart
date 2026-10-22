import 'package:flutter/material.dart';

class AppColors {
  static const Color darkBackground = Color(0xFF0A0E1A);
  static const Color darkSurface = Color(0xFF121A2E);
  static const Color darkCard = Color(0xFF1A2440);
  static const Color darkBorder = Color(0xFF243150);

  static const Color lightBackground = Color(0xFFF4F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFEDF1F7);
  static const Color lightBorder = Color(0xFFE1E7F0);

  static const Color primaryCyan = Color(0xFF00B4D8);
  static const Color secondaryIndigo = Color(0xFF6366F1);
  static const Color accentViolet = Color(0xFF8B5CF6);

  static const Color statusGreen = Color(0xFF10B981);
  static const Color statusAmber = Color(0xFFF59E0B);
  static const Color statusRose = Color(0xFFEF4444);
  static const Color statusDelayed = Color(0xFFFF6B6B);
  static const Color statusDisrupted = Color(0xFFFF5252);

  static const Color melbourneMetro = Color(0xFF0072CE);
  static const Color melbourneTram = Color(0xFF78BE20);
  static const Color melbourneVLine = Color(0xFF8F1A95);
  static const Color melbourneBus = Color(0xFFFF8200);
  static const Color melbourneFerry = Color(0xFF00A3A6);
}

class AppTheme {
  static ThemeData get darkTheme => darkThemeFor(AppColors.primaryCyan);
  static ThemeData get lightTheme => lightThemeFor(AppColors.primaryCyan);

  static ThemeData darkThemeFor(Color accent) => _build(
    accent: accent,
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceHigh: AppColors.darkCard,
    border: AppColors.darkBorder,
    onSurface: const Color(0xFFF1F5F9),
    muted: const Color(0xFF94A3B8),
  );

  static ThemeData lightThemeFor(Color accent) => _build(
    accent: accent,
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceHigh: AppColors.lightCard,
    border: AppColors.lightBorder,
    onSurface: const Color(0xFF0F172A),
    muted: const Color(0xFF64748B),
  );

  /// One builder for both brightnesses. Widgets read these roles
  /// (`surfaceContainerHigh`, `outlineVariant`, `onSurfaceVariant`) instead of
  /// hard-coding per-theme colours.
  static ThemeData _build({
    required Color accent,
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color border,
    required Color onSurface,
    required Color muted,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: AppColors.secondaryIndigo,
      onSecondary: Colors.white,
      error: AppColors.statusRose,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: muted.withAlpha(120),
      outlineVariant: border,
    );
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final textTheme = base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: background,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withAlpha(isDark ? 55 : 40),
        secondarySelectedColor: accent,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: border),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        prefixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withAlpha(isDark ? 50 : 36),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 68,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent, size: 24);
          }
          return IconThemeData(color: muted, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? onSurface : muted,
          );
        }),
      ),
    );
  }
}
