import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central type roles for OpenGym.
///
/// Manrope carries the interface. Numbers that sit in columns, change in place
/// or get compared at a glance (Stats figures, chart axes, record rows, the
/// app version) use [figures]: the same Manrope with tabular figures, so every
/// digit takes the same width without switching typeface. JetBrains Mono is
/// kept out of the theme-wide text styles and is only requested through
/// [trainingData] for the remaining compact training data.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color primary, Color secondary) {
    final base = TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineLarge: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: primary),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: primary),
      bodySmall: TextStyle(fontSize: 12, height: 1.45, color: secondary),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelSmall: TextStyle(fontSize: 11, height: 1.25, color: secondary),
    );
    return GoogleFonts.manropeTextTheme(base);
  }

  static TextStyle trainingData({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Manrope with tabular figures, for numbers that must line up or hold their
  /// width as they change. Same signature as [trainingData], so a call site
  /// can swap one for the other.
  static TextStyle figures({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.manrope(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
