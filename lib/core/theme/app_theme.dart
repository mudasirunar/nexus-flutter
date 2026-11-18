import 'package:flutter/material.dart';

/// Semantic colors and design tokens for NEXUS (Light & Dark).
class AppColors {
  AppColors._();

  // Light Palette
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightMuted = Color(0xFF64748B);
  static const Color lightPrimary = Color(0xFF2563EB);

  // Dark Palette
  static const Color darkBg = Color(0xFF0B1120);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkMuted = Color(0xFF94A3B8);
  static const Color darkPrimary = Color(0xFF3B82F6);

  // Semantic Status Colors
  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFDBEAFE);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEE2E2);
}

/// Consistent spacing scale (8px base grid).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppTheme {
  AppTheme._();

  static const TextStyle tabularNumberStyle = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.lightPrimary,
      onPrimary: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightText,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.lightBorder,
    );

    return _baseTheme(
      colorScheme: colorScheme,
      scaffoldBg: AppColors.lightBg,
      surface: AppColors.lightSurface,
      border: AppColors.lightBorder,
      textColor: AppColors.lightText,
      mutedColor: AppColors.lightMuted,
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: Colors.white,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.darkBorder,
    );

    return _baseTheme(
      colorScheme: colorScheme,
      scaffoldBg: AppColors.darkBg,
      surface: AppColors.darkSurface,
      border: AppColors.darkBorder,
      textColor: AppColors.darkText,
      mutedColor: AppColors.darkMuted,
    );
  }

  static ThemeData _baseTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    required Color surface,
    required Color border,
    required Color textColor,
    required Color mutedColor,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: TextStyle(color: mutedColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    );
  }
}
