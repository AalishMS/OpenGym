import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'radii.dart';
import 'tones.dart';

class AppColorScheme extends ThemeExtension<AppColorScheme> {
  final Color background;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;

  /// The accent as text and icons — solved to ≥4.5:1 against whichever of
  /// [background]/[surface] it fares worse on, so an accent word is legible on
  /// either ground. This is the accent to *write with*.
  final Color accent;

  /// The accent as a ground — a filled button, a selected chip, the FAB. Solved
  /// to ≥3:1 against [background] so its edge reads, and it is what [onAccent] is
  /// legible against. Not the same colour as [accent]: text wants more contrast
  /// than a fill does, so on a light theme the fill stays brighter than the word.
  final Color accentFill;

  /// The two opaque wash tones behind [accentFill], at even perceptual steps
  /// from the background up to the fill. These replace `accent.withAlpha(...)`,
  /// which composited differently against every ground; see [toneBetween].
  final Color accentDim;
  final Color accentMuted;

  /// Foreground for anything drawn *on top of* [accentFill] — label text on a
  /// filled button, a snackbar message, a selected chip. Whichever of black or
  /// white is actually more legible on the fill, by [bestForeground].
  final Color onAccent;

  const AppColorScheme({
    required this.background,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.accent,
    required this.accentFill,
    required this.accentDim,
    required this.accentMuted,
    required this.onAccent,
  });

  @override
  ThemeExtension<AppColorScheme> copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? error,
    Color? success,
    Color? accent,
    Color? accentFill,
    Color? accentDim,
    Color? accentMuted,
    Color? onAccent,
  }) {
    return AppColorScheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      error: error ?? this.error,
      success: success ?? this.success,
      accent: accent ?? this.accent,
      accentFill: accentFill ?? this.accentFill,
      accentDim: accentDim ?? this.accentDim,
      accentMuted: accentMuted ?? this.accentMuted,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  ThemeExtension<AppColorScheme> lerp(
    ThemeExtension<AppColorScheme>? other,
    double t,
  ) {
    if (other is! AppColorScheme) return this;
    return AppColorScheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentFill: Color.lerp(accentFill, other.accentFill, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      // Stepped, not interpolated: a foreground whose only job is to stay
      // legible must never pass through mid-grey on its way across.
      onAccent: t < 0.5 ? onAccent : other.onAccent,
    );
  }
}

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

Color successColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.success ??
      const Color(0xFF4CAF50);
}

/// The active accent for the current theme. Prefer this over reading
/// `SettingsProvider.accentColor` directly in widgets — it already reflects
/// the resolved light/dark brightness through [Theme].
Color accentColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.accent ??
      Theme.of(context).colorScheme.primary;
}

/// The accent as a *ground* — a filled button, a selected chip, the FAB. Draw
/// [onAccentColor] on top of it. Distinct from [accentColor], which is tuned
/// for text and so carries more contrast than a fill needs.
Color accentFillColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.accentFill ??
      accentColor(context);
}

/// The stronger of the two opaque accent washes — a selected-cell fill, the
/// mid step of the frequency heatmap. Opaque, so it reads the same on every
/// ground; replaces `accent.withAlpha(160)`.
Color accentDimColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.accentDim ??
      accentColor(context);
}

/// The quieter of the two opaque accent washes — a hover tint, the low step of
/// the frequency heatmap. Replaces `accent.withAlpha(90)` and the dead
/// `accentMuted` alpha.
Color accentMutedColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.accentMuted ??
      accentColor(context);
}

/// Foreground for text and icons drawn on top of an arbitrary coloured
/// [ground] — a plan's own colour, an RPE swatch, the error red.
///
/// This is the *only* place in the app that names pure black or white: every
/// other site asks this function, so picking a dark accent can never leave
/// black text on a dark ground. Prefer [onAccentColor] when the ground is the
/// theme accent — it reads the value the theme already computed.
///
/// Delegates to [bestForeground], which compares the two candidates outright
/// rather than thresholding luminance at a magic number — the old `> 0.5` test
/// crossed over at the wrong point and handed white to grounds where black was
/// the readable choice.
Color onColor(Color ground) => bestForeground(ground);

/// Foreground for anything sitting on [accentColor] — filled buttons, selected
/// chips and tabs, snackbars tinted with the accent.
Color onAccentColor(BuildContext context) {
  final scheme = Theme.of(context).extension<AppColorScheme>();
  return scheme?.onAccent ?? onColor(accentColor(context));
}

const double _meshHueSpread = 40 * math.pi / 180;
const double _meshPeakDark = 0.85;
const double _meshPeakLight = 0.14;

List<Color> headerMeshTones(BuildContext context) {
  final muted = accentMutedColor(context);
  final o = oklchOf(muted);
  return [
    muted,
    colorFromOklch(o.l, o.c, o.h + _meshHueSpread),
    colorFromOklch(o.l, o.c, o.h - _meshHueSpread),
  ];
}

Widget headerFlexibleSpace(BuildContext context, {double bottomInset = 0}) {
  return Padding(
    padding: EdgeInsets.only(bottom: bottomInset),
    child: headerMesh(context),
  );
}

Widget headerMesh(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return ClipRect(
    child: ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: 18,
        sigmaY: 18,
        tileMode: TileMode.decal,
      ),
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _HeaderMeshPainter(
            tones: headerMeshTones(context),
            peak: isDark ? _meshPeakDark : _meshPeakLight,
          ),
        ),
      ),
    ),
  );
}

class _HeaderMeshPainter extends CustomPainter {
  _HeaderMeshPainter({required this.tones, required this.peak});

  final List<Color> tones;
  final double peak;

  static const List<(double, double, double)> _blobs = [
    (0.86, 0.08, 0.62),
    (1.05, 0.90, 0.52),
    (0.58, -0.12, 0.42),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (var i = 0; i < _blobs.length; i++) {
      final (fx, fy, fr) = _blobs[i];
      final center = Offset(fx * size.width, fy * size.height);
      final radius = fr * size.width;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              tones[i % tones.length].withValues(alpha: peak),
              tones[i % tones.length].withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_HeaderMeshPainter old) =>
      old.peak != peak || !_sameTones(old.tones, tones);

  static bool _sameTones(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Derivation (direction A)
// ---------------------------------------------------------------------------

/// The reviewed palette's fixed inputs — see `docs/color-study.html`. Neutrals
/// grow from one pure-grey seed so both modes share a temperature (the old light
/// mode tinted its background 60° against a neutral surface, which read as
/// dirty), and the seed stays achromatic on purpose: dark mode is meant to read
/// as black, so the accent is the only thing in the app carrying a hue.
const Color _neutralSeed = Color(0xFF8A8A8A);
const Color _bgDark = Color(0xFF0D0D0D);
const Color _bgLight = Color(0xFFF7F7F6);

/// How far a card's fill sits above (dark) or below (light) the page, as a step
/// in OKLab lightness rather than a WCAG ratio — the one separation in this file
/// that is deliberately *not* a contrast target.
///
/// WCAG's ratio is `(L + 0.05) / (L + 0.05)`, and against a near-black page the
/// `+0.05` dominates: at `_bgDark`'s luminance of 0.004, a 1.45:1 card needs
/// **seven times** the page's linear luminance — a lightness step of 0.146,
/// where that same 1.45 costs only 0.061 in light mode. Asking both modes for
/// the same *number* therefore hands dark mode a 2.4× bigger step, which is how
/// a card meant to be quiet came out at `#2F2F2F`: a grey box on a black page,
/// with the whole workout screen tiled in it.
///
/// So separation between two neutral *grounds* is stated perceptually, which is
/// what the eye is judging. Contrast ratios stay the metric for everything that
/// has to be **read** — text, borders, accents — because that is the question
/// WCAG answers. The floor to respect is the bug this replaced: cards at 1.10:1
/// were invisible, a step of 0.046. Both values below clear it with room, and
/// `theme_contrast_test.dart` pins the floor so it cannot creep back.
const double _surfLiftDark = 0.075;
const double _surfLiftLight = 0.061;

const double _borderTargetDark = 3.00;
const double _borderTargetLight = 1.90;

/// Seed lightness for `error` and `success`. Must match `_seedLightness` in
/// `semantic_colors.dart` — they are steps of the same ramp.
const double _semanticLightness = 0.62;

/// Solves the full token set for [seed] in one brightness. The accent roles are
/// solved *against these neutrals*, not against constants, so the accent and the
/// card it sits on are one coupled computation — which is why this lives here
/// and not split across two build passes.
///
/// Public so `test/theme_contrast_test.dart` can assert the role table without
/// building a [ThemeData] — which would pull in a [TextTheme] and, with it, a
/// google_fonts network fetch that a test runner cannot serve. Widgets have no
/// business calling this: they read the solved values through the accessors
/// above, which pick up the theme the app was actually built with.
AppColorScheme deriveColorScheme(Color seed, Brightness brightness) =>
    _deriveScheme(seed, brightness == Brightness.dark);

AppColorScheme _deriveScheme(Color seed, bool isDark) {
  // In dark mode every tone is found by moving *lighter* than its ground; in
  // light mode, darker.
  final preferLighter = isDark;
  final background = isDark ? _bgDark : _bgLight;

  // Neutrals. The card's fill is a perceptual step off the page — see
  // `_surfLiftDark` for why this one is not a ratio. Everything solved *against*
  // that fill is still a contrast target, so darkening the card pulls the
  // hairline and the secondary text down with it automatically: the border holds
  // at exactly 3:1, which is what keeps an unfilled text field findable.
  //
  // Those solves pass `ToneAnchor.ground` (the default), so each lands *at* its
  // target rather than past it — a border that overshoots 3:1 is a bright rule
  // around a dark card, not an edge.
  final surface = toneOf(
    _neutralSeed,
    oklchOf(background).l + (isDark ? _surfLiftDark : -_surfLiftLight),
  );
  final border = solveForContrast(
    seed: _neutralSeed,
    against: surface,
    target: isDark ? _borderTargetDark : _borderTargetLight,
    preferLighter: preferLighter,
  );
  final textPrimary = solveForContrast(
    seed: _neutralSeed,
    against: background,
    target: 13.0,
    preferLighter: preferLighter,
  );
  final textSecondary = solveForContrast(
    seed: _neutralSeed,
    against: surface,
    target: 4.5,
    preferLighter: preferLighter,
  );

  // Accent roles. `ToneAnchor.seed`: the seed *is* the intended accent, so it is
  // kept whenever it already reads and moved only when it doesn't — that single
  // rule is the fix for both the illegible dark-mode label and the dead light
  // mode, which used to draw dark hexes on a light page.
  final worse =
      contrastRatio(seed, background) < contrastRatio(seed, surface)
          ? background
          : surface;
  final accent = solveForContrast(
    seed: seed,
    against: worse,
    target: 4.5,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
  );
  final accentFill = solveForContrast(
    seed: seed,
    against: background,
    target: 3.0,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
  );
  final onAccent = bestForeground(accentFill);
  // The two washes are even perceptual steps from the background up to the fill,
  // opaque — not `accent.withAlpha(...)`, which composited differently on every
  // ground and drifted the token between screens.
  final accentMuted = toneBetween(
    seed: seed,
    from: background,
    to: accentFill,
    fraction: 1 / 3,
  );
  final accentDim = toneBetween(
    seed: seed,
    from: background,
    to: accentFill,
    fraction: 2 / 3,
  );

  // Error and success are the two ends of the same traffic-light ramp the RPE
  // badges use — same hue, same chroma, same lightness seed (see
  // `semantic_colors.dart`), so "bad" and "good" mean one colour each across the
  // whole app instead of a Material red here and a hand-picked red there. Both
  // are solved on the surface, the harder ground, and both are used as grounds
  // in places; `onColor` supplies their foreground.
  final error = solveForContrast(
    seed: colorFromOklch(_semanticLightness, 0.17, 29 * math.pi / 180),
    against: surface,
    target: 4.5,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
  );
  final success = solveForContrast(
    seed: colorFromOklch(_semanticLightness, 0.15, 150 * math.pi / 180),
    against: surface,
    target: 4.5,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
  );

  return AppColorScheme(
    background: background,
    surface: surface,
    border: border,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    error: error,
    success: success,
    accent: accent,
    accentFill: accentFill,
    accentDim: accentDim,
    accentMuted: accentMuted,
    onAccent: onAccent,
  );
}

/// The `accent` tone [seed] resolves to in [brightness] — the same value
/// `accentColor(context)` returns for the *active* accent, exposed so the
/// settings picker can preview the accents that aren't selected. Widgets that
/// want the current accent must still use `accentColor(context)`; this is only
/// for showing a seed that isn't the one the theme was built from.
Color accentToneFor(Color seed, Brightness brightness) =>
    _deriveScheme(seed, brightness == Brightness.dark).accent;

ThemeData buildTheme(Color seed, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = _deriveScheme(seed, isDark);

  final background = c.background;
  final surface = c.surface;
  final border = c.border;
  final textPrimary = c.textPrimary;
  final textSecondary = c.textSecondary;
  final error = c.error;
  final accent = c.accent;
  final accentFill = c.accentFill;
  final onAccent = c.onAccent;
  WidgetStateProperty<Color?> interactionOverlay(Color color) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return color.withAlpha(31);
        if (states.contains(WidgetState.focused)) return color.withAlpha(26);
        if (states.contains(WidgetState.hovered)) return color.withAlpha(20);
        return null;
      });

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme(
      brightness: brightness,
      // `accent` is the text/line accent; `onColor(accent)` is correct for the
      // Material internals that fill with `primary`. Elements that fill with the
      // accent as a *ground* below use `accentFill` + `onAccent` instead.
      primary: accent,
      onPrimary: onColor(accent),
      secondary: accent,
      onSecondary: onColor(accent),
      error: error,
      onError: onColor(error),
      surface: surface,
      onSurface: textPrimary,
    ),
    extensions: [c],
    textTheme: _buildTextTheme(textPrimary, textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
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
        borderRadius: AppRadius.card,
        side: BorderSide(color: border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentFill,
        foregroundColor: onAccent,
        disabledBackgroundColor: surface,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold),
      ).copyWith(overlayColor: interactionOverlay(onAccent)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
        side: BorderSide(color: border, width: 1),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold),
      ).copyWith(overlayColor: interactionOverlay(textPrimary)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        textStyle: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold),
      ).copyWith(overlayColor: interactionOverlay(accent)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: accent,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
      ).copyWith(overlayColor: interactionOverlay(accent)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: background,
      foregroundColor: accent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: accent, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(
        borderRadius: AppRadius.field,
        borderSide: BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.field,
        borderSide: BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.field,
        borderSide: BorderSide(color: accent, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.field,
        borderSide: BorderSide(color: error, width: 1),
      ),
      labelStyle: TextStyle(color: textSecondary),
      hintStyle: TextStyle(color: textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      // A selected chip is a ground with a label on it, so it takes the fill
      // tone and the foreground solved against that fill.
      selectedColor: accentFill,
      labelStyle: TextStyle(color: textPrimary),
      secondaryLabelStyle: TextStyle(color: onAccent),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.chip,
        side: BorderSide(color: border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentFill;
        }
        return textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          // An opaque step short of the fill, not `accent.withAlpha(128)`: the
          // alpha version composited against whatever was behind the switch, so
          // the same "on" track was a different colour on a card than on a page.
          return c.accentDim;
        }
        return border;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: surface,
      textColor: textPrimary,
      iconColor: accent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: border, width: 1),
      ),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      contentTextStyle: TextStyle(color: textPrimary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.button,
        side: BorderSide(color: border, width: 1),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: textSecondary,
      labelStyle: const TextStyle(fontWeight: FontWeight.bold),
      unselectedLabelStyle: const TextStyle(),
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
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
        borderRadius: AppRadius.chip,
      ),
      textStyle: TextStyle(color: textPrimary),
    ),
  );
}

TextTheme _buildTextTheme(Color textPrimary, Color textSecondary) {
  return TextTheme(
    displayLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    displaySmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    headlineLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    headlineMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    headlineSmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    titleLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    titleSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
    bodyMedium: TextStyle(fontSize: 14, color: textPrimary),
    bodySmall: TextStyle(fontSize: 12, color: textSecondary),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    labelSmall: TextStyle(fontSize: 10, color: textSecondary),
  );
}
