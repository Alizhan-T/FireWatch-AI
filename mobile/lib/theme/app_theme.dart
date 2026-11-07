import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppColors {
  // Calm, professional emergency monitoring dark slate palette
  static const background = Color(0xFF101318);
  static const secondaryBackground = Color(0xFF151A22);
  static const card = Color(0xFF1C2330);
  static const cardElevated = Color(0xFF232C3B);
  static const cardBorder = Color(0x18F5F7FA);
  static const separator = Color(0x14F5F7FA);
  static const surfaceElevated = Color(0xFF202836);

  // iOS System Semantic Accents (Blue primary accent, Red critical, Orange warning)
  static const primaryAccent = Color(0xFF5B9BFF);
  // Alias kept for compatibility across screens — maps to Blue accent (#5B9BFF)
  static const primaryGreen = Color(0xFF5B9BFF);
  static const statusOk = Color(0xFF32D74B);
  static const dangerRed = Color(0xFFFF453A);
  static const warningOrange = Color(0xFFFF9F0A);
  static const mediumYellow = Color(0xFFFFD60A);
  static const lowBlue = Color(0xFF5B9BFF);
  static const systemBlue = Color(0xFF5B9BFF);

  // Typography colors
  static const textPrimary = Color(0xFFF5F7FA);
  static const textSecondary = Color(0xFF8993A3);
  static const textTertiary = Color(0xFF5E6775);

  static Color forSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return dangerRed;
      case 'high':
        return warningOrange;
      case 'medium':
        return mediumYellow;
      case 'low':
      default:
        return lowBlue;
    }
  }

  static String severityLabel(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 'CRITICAL';
      case 'high':
        return 'HIGH';
      case 'medium':
        return 'MEDIUM';
      case 'low':
      default:
        return 'LOW';
    }
  }

  static String statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'new':
        return 'New';
      case 'acknowledged':
        return 'Acknowledged';
      case 'resolved':
        return 'Resolved';
      case 'false_alarm':
        return 'False Alarm';
      default:
        return status;
    }
  }

  static String detectionModeLabel(String mode) {
    switch (mode.toLowerCase()) {
      case 'real_model':
        return 'REAL MODEL';
      case 'demo_heuristic':
        return 'DEMO HEURISTIC';
      case 'simulated':
        return 'DEMO SIMULATION';
      case 'manual':
      default:
        return 'MANUAL REPORT';
    }
  }
}

class AppTheme {
  static const String iosFontFamily = '.SF Pro Text';
  static const String iosDisplayFamily = '.SF Pro Display';

  static CupertinoThemeData get cupertinoTheme {
    return const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primaryAccent,
      primaryContrastingColor: Color(0xFFFFFFFF),
      scaffoldBackgroundColor: AppColors.background,
      barBackgroundColor: Color(0xE6101318),
      textTheme: CupertinoTextThemeData(
        primaryColor: AppColors.textPrimary,
        textStyle: TextStyle(
          fontFamily: iosFontFamily,
          color: AppColors.textPrimary,
          fontSize: 16,
          letterSpacing: -0.24,
        ),
        navTitleTextStyle: TextStyle(
          fontFamily: iosFontFamily,
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        navLargeTitleTextStyle: TextStyle(
          fontFamily: iosDisplayFamily,
          color: AppColors.textPrimary,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      surface: AppColors.background,
      primary: AppColors.primaryAccent,
      secondary: AppColors.primaryAccent,
      error: AppColors.dangerRed,
      onPrimary: Color(0xFFFFFFFF),
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: iosFontFamily,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.secondaryBackground,
      colorScheme: scheme,
      cupertinoOverrideTheme: cupertinoTheme,
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 20,
      ),
      primaryIconTheme: const IconThemeData(
        color: AppColors.primaryGreen,
        size: 20,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.primaryGreen, size: 20),
        titleTextStyle: TextStyle(
          fontFamily: iosFontFamily,
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.secondaryBackground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13.5,
        ),
        hintStyle: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 13.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryGreen, width: 1.0),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryAccent,
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: iosFontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.cardBorder, width: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.separator,
        thickness: 0.5,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.cardElevated,
        contentTextStyle: const TextStyle(
          fontFamily: iosFontFamily,
          color: AppColors.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
      ),
    );
  }
}
