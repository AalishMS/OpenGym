import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColorScheme extends ThemeExtension<AppColorScheme> {
  final Color background;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color accent;
  final Color accentMuted;

  const AppColorScheme({
    required this.background,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.accent,
    required this.accentMuted,
  });

  @override
  ThemeExtension<AppColorScheme> copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? error,
    Color? accent,
    Color? accentMuted,
  }) {
    return AppColorScheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      error: error ?? this.error,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
    );
  }

  @override
  ThemeExtension<AppColorScheme> lerp(
      ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    return AppColorScheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
    );
  }

  static const dark = AppColorScheme(
    background: Color(0xFF0F0F0F),
    surface: Color(0xFF1A1A1A),
    border: Color(0xFF2A2A2A),
    textPrimary: Color(0xFFF0F0F0),
    textSecondary: Color(0xFF888888),
    error: Color(0xFFFF4444),
    accent: Color(0xFF00A8FF),
    accentMuted: Color(0x3300A8FF),
  );

  static const light = AppColorScheme(
    background: Color(0xFFF5F5F0),
    surface: Color(0xFFECECEC),
    border: Color(0xFFD0D0D0),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF666666),
    error: Color(0xFFCC3333),
    accent: Color(0xFF0077CC),
    accentMuted: Color(0x260077CC),
  );
}

const Color terminalBackground = Color(0xFF0F0F0F);
const Color terminalSurface = Color(0xFF1A1A1A);
const Color terminalBorder = Color(0xFF2A2A2A);
const Color terminalTextPrimary = Color(0xFFF0F0F0);
const Color terminalTextSecondary = Color(0xFF888888);
const Color terminalError = Color(0xFFFF4444);

Color backgroundColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.background ??
      const Color(0xFF0F0F0F);
}

Color surfaceColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.surface ??
      const Color(0xFF1A1A1A);
}

Color borderColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.border ??
      const Color(0xFF2A2A2A);
}

Color textPrimaryColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.textPrimary ??
      const Color(0xFFF0F0F0);
}

Color textSecondaryColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.textSecondary ??
      const Color(0xFF888888);
}

Color errorColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.error ??
      const Color(0xFFFF4444);
}

ThemeData buildTheme(Color accent, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final isLightAccent = accent.computeLuminance() > 0.5;
  final onAccent = isLightAccent ? Colors.black : Colors.white;

  final background = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F0);
  final surface = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFECECEC);
  final border = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFD0D0D0);
  final textPrimary =
      isDark ? const Color(0xFFF0F0F0) : const Color(0xFF111111);
  final textSecondary =
      isDark ? const Color(0xFF888888) : const Color(0xFF666666);
  final error = isDark ? const Color(0xFFFF4444) : const Color(0xFFCC3333);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: error,
      onError: isDark ? Colors.white : Colors.white,
      surface: surface,
      onSurface: textPrimary,
    ),
    extensions: [
      AppColorScheme(
        background: background,
        surface: surface,
        border: border,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        error: error,
        accent: accent,
        accentMuted: accent.withAlpha(isDark ? 51 : 38),
      ),
    ],
    textTheme: _buildTextTheme(textPrimary, textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.jetBrainsMono(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      iconTheme: IconThemeData(color: accent),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: accent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: accent, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent, width: 1),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Colors.black,
      foregroundColor: accent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: accent, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: accent, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: error, width: 1),
      ),
      labelStyle: GoogleFonts.jetBrainsMono(color: textSecondary),
      hintStyle: GoogleFonts.jetBrainsMono(color: textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: accent,
      labelStyle: GoogleFonts.jetBrainsMono(color: textPrimary),
      secondaryLabelStyle: GoogleFonts.jetBrainsMono(color: onAccent),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent;
        }
        return textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent.withAlpha(128);
        }
        return border;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: surface,
      textColor: textPrimary,
      iconColor: accent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: border, width: 1),
      ),
      titleTextStyle: GoogleFonts.jetBrainsMono(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      contentTextStyle: GoogleFonts.jetBrainsMono(color: textPrimary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: GoogleFonts.jetBrainsMono(color: textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: border, width: 1),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: textSecondary,
      labelStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold),
      unselectedLabelStyle: GoogleFonts.jetBrainsMono(),
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      circularTrackColor: border,
      linearTrackColor: border,
    ),
    iconTheme: IconThemeData(color: accent),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border, width: 1),
      ),
      textStyle: GoogleFonts.jetBrainsMono(color: textPrimary),
    ),
  );
}

TextTheme _buildTextTheme(Color textPrimary, Color textSecondary) {
  return TextTheme(
    displayLarge: GoogleFonts.jetBrainsMono(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    displayMedium: GoogleFonts.jetBrainsMono(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    displaySmall: GoogleFonts.jetBrainsMono(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    headlineLarge: GoogleFonts.jetBrainsMono(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    headlineMedium: GoogleFonts.jetBrainsMono(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    headlineSmall: GoogleFonts.jetBrainsMono(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    titleLarge: GoogleFonts.jetBrainsMono(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    titleMedium: GoogleFonts.jetBrainsMono(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    titleSmall: GoogleFonts.jetBrainsMono(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    bodyLarge: GoogleFonts.jetBrainsMono(
      fontSize: 16,
      color: textPrimary,
    ),
    bodyMedium: GoogleFonts.jetBrainsMono(
      fontSize: 14,
      color: textPrimary,
    ),
    bodySmall: GoogleFonts.jetBrainsMono(
      fontSize: 12,
      color: textSecondary,
    ),
    labelLarge: GoogleFonts.jetBrainsMono(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    labelMedium: GoogleFonts.jetBrainsMono(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    labelSmall: GoogleFonts.jetBrainsMono(
      fontSize: 10,
      color: textSecondary,
    ),
  );
}
