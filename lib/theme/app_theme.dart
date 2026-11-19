import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_typography.dart';
import 'radii.dart';
import 'ring_input_border.dart';
import 'tones.dart';

class AppColorScheme extends ThemeExtension<AppColorScheme> {
  /// The page.
  final Color background;

  /// A *raised* ground: sheets, dialogs, menus and the few cards that lift off
  /// the page. Lighter than [background] in both modes, so elevation always
  /// reads as light coming forward. In light mode that makes it white, and the
  /// step is small, so a raised card also casts [shadow].
  final Color surface;

  /// The ground of a control: text fields, steppers, chips, keypad keys,
  /// segment tracks. A step *away* from both [background] and [surface], so it
  /// reads on either: darker than the page in light mode, lighter than a sheet
  /// in dark mode. That also makes it the hardest ground for ink in both
  /// modes, which is why the ink roles are solved against it.
  final Color controlFill;

  /// A quiet line: dividers, ledger rules, the edge of a card. Visible, never
  /// loud — it separates, it doesn't frame.
  final Color hairline;

  /// The edge of a control that has no fill of its own — an unselected radio,
  /// a switch track, an outlined icon button. Solved to 3:1 against the page
  /// and the surface (WCAG 1.4.11). Not for containers: use [hairline].
  final Color border;

  /// Opaque near-black that [raisedShadow] fades out. Only light mode casts
  /// shadows; in dark mode a raised surface is told apart by its lighter fill.
  final Color shadow;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color success;

  /// The accent as text and icons — solved to ≥4.5:1 against whichever of
  /// [background]/[surface] it fares worse on, so an accent word is legible on
  /// either ground. This is the accent to *write with*.
  final Color accent;

  /// A more vivid accent reserved for the wordmark, with readable text contrast.
  final Color brandAccent;

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
    required this.controlFill,
    required this.hairline,
    required this.border,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.accent,
    required this.brandAccent,
    required this.accentFill,
    required this.accentDim,
    required this.accentMuted,
    required this.onAccent,
  });

  @override
  ThemeExtension<AppColorScheme> copyWith({
    Color? background,
    Color? surface,
    Color? controlFill,
    Color? hairline,
    Color? border,
    Color? shadow,
    Color? textPrimary,
    Color? textSecondary,
    Color? error,
    Color? success,
    Color? accent,
    Color? brandAccent,
    Color? accentFill,
    Color? accentDim,
    Color? accentMuted,
    Color? onAccent,
  }) {
    return AppColorScheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      controlFill: controlFill ?? this.controlFill,
      hairline: hairline ?? this.hairline,
      border: border ?? this.border,
      shadow: shadow ?? this.shadow,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      error: error ?? this.error,
      success: success ?? this.success,
      accent: accent ?? this.accent,
      brandAccent: brandAccent ?? this.brandAccent,
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
      controlFill: Color.lerp(controlFill, other.controlFill, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
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

/// The ground of a control — a text field, stepper, chip or key. See
/// [AppColorScheme.controlFill].
Color controlFillColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.controlFill ??
      surfaceColor(context);
}

/// A quiet separating line — dividers, ledger rules, card edges. Use
/// [borderColor] only for the edge of an unfilled control.
Color hairlineColor(BuildContext context) {
  return Theme.of(context).extension<AppColorScheme>()?.hairline ??
      borderColor(context);
}

/// Whichever of the page, the raised surface and the control fill [ink] reads
/// worst on. Tones that are drawn as text or marks anywhere — plan colours, the
/// RPE ramp — solve against this so they hold on every ground.
Color hardestGroundFor(Color ink, BuildContext context) {
  final grounds = [
    backgroundColor(context),
    surfaceColor(context),
    controlFillColor(context),
  ];
  return grounds.reduce(
    (a, b) => contrastRatio(ink, a) <= contrastRatio(ink, b) ? a : b,
  );
}

/// The ground of a chosen option among filled ones — a selected tile or row.
/// Pair it with an accent edge. Dark mode takes the accent's wash; in light
/// mode that wash reads as a heavy slab, so the choice rises to white instead,
/// lifted out of the control fill around it.
Color selectedGroundColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? accentMutedColor(context)
        : surfaceColor(context);

/// The edge a raised surface gets on the page. Light mode casts a soft
/// two-layer shadow. Dark mode has nothing for a shadow to fall on, so the
/// card's top edge catches the light instead: a hard 1px "shadow" in the
/// hairline tone, lifted 1px above the card. The card covers all of it except
/// a band along the top, which tapers away round the top corners, so the card
/// reads as a lit surface rather than an outlined box.
///
/// Put it on cards that sit on the page, not on sheets or dialogs, which the
/// scrim separates.
List<BoxShadow> raisedShadow(BuildContext context) {
  final scheme = Theme.of(context).extension<AppColorScheme>();
  if (scheme == null) return const [];
  if (Theme.of(context).brightness == Brightness.dark) {
    return [BoxShadow(color: scheme.hairline, offset: const Offset(0, -1))];
  }
  return [
    BoxShadow(
      color: scheme.shadow.withAlpha(13),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: scheme.shadow.withAlpha(16),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
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

/// The vivid wordmark tone; ordinary controls use the softer accent roles.
Color brandAccentColor(BuildContext context) =>
    Theme.of(context).extension<AppColorScheme>()?.brandAccent ??
    accentColor(context);

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

/// The accent as ink on its own quiet wash ([accentMutedColor]) — the label of
/// a tonal button. The plain accent is solved against the neutral grounds and
/// can fall short on the wash, so this re-solves it there for 4.5:1, keeping
/// the accent's hue.
Color accentOnMutedColor(BuildContext context) {
  final wash = accentMutedColor(context);
  return solveForContrast(
    seed: accentColor(context),
    against: wash,
    target: 4.5,
    preferLighter: Theme.of(context).brightness == Brightness.dark,
    anchor: ToneAnchor.seed,
  );
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

/// The reviewed palette's fixed inputs are checked by the tone and contrast
/// golden tests. Neutrals grow from one pure-grey seed so both modes share a
/// temperature (the old light mode tinted its background 60° against a neutral
/// surface, which read as dirty), and the seed stays achromatic on purpose: dark
/// mode is meant to read as black, so the accent is the only thing in the app
/// carrying a hue.
const Color _neutralSeed = Color(0xFF8A8A8A);
const Color _bgDark = Color(0xFF0D0D0D);
const Color _bgLight = Color(0xFFF2F2F1);

/// Elevation reads as light, in both modes: a raised surface is *lighter* than
/// the page it sits on, never darker.
///
/// Light mode used to step its cards *down* from the page, to `#E3E3E3`, and
/// draw a 1.9:1 outline round them. Every sheet, dialog, field and tile came out
/// as a grey slab sunk into the page. Raised is now white, and the page sits a
/// small step below it. That step alone is only ~1.12:1, so a raised card on the
/// page also casts [raisedShadow]: the shadow, not a darker fill or a heavy
/// outline, is what lifts it.
///
/// In dark mode a shadow has nothing to fall on, so the fill carries most of
/// the separation, as a perceptual step in OKLab lightness, and the card's top
/// edge catches the light ([raisedShadow]). It is stated perceptually rather
/// than as a WCAG ratio because near black the ratio's `+0.05` term dominates:
/// the same 1.45:1 that is a quiet step in light mode is a 0.146 step in dark
/// mode, which is how a card once landed on `#2F2F2F`, a grey box on a black
/// page.
///
/// Dark mode lifts about 1.5x as far as light mode's 0.042. At 0.045, with a
/// hairline drawn all round, a raised card read as an outlined box rather than
/// a surface. Light mode has a shadow to finish the job; dark mode has only
/// the fill and a lit top edge, so the fill steps further.
const double _raisedLiftDark = 0.065;

/// How far a control's fill steps away from what it sits on: above the sheet in
/// dark mode, below the page in light mode. See [AppColorScheme.controlFill].
const double _controlStepDark = 0.045;
const double _controlStepLight = 0.028;

/// Hairlines are solved as a ratio against the raised surface: a line has to be
/// *seen*, but this one only has to separate, so it stays far under the 3:1 of
/// [AppColorScheme.border].
const double _hairlineTarget = 1.25;

/// A control edge, per WCAG 1.4.11.
const double _borderTarget = 3.0;

/// Seed lightness for `error` and `success`. Must match `_seedLightness` in
/// `semantic_colors.dart` — they are steps of the same ramp.
const double _semanticLightness = 0.62;

/// Absolute chroma ceilings for the accent roles. Vividness alone would let a
/// gamut-edge seed reach ~0.21 on a pink fill, which is the neon the original
/// palette had; these hold every accent inside "clearly coloured, not glowing".
const double _accentChromaCapLight = 0.15;
const double _accentChromaCapDark = 0.15;

/// Dark mode's accent is one tone, shared by the wordmark, filled controls and
/// accent ink. It used to be the seed itself (L 0.72) beside a wordmark solved
/// separately at L 0.80+ with 1.8x the chroma. Side by side they read as two
/// different colours, and the seed looked washed out next to the wordmark: a
/// dusty teal button under an electric cyan logo.
///
/// The tone sits a little lighter than the seed and spends a little more of the
/// chroma sRGB allows there ([vividnessOf]). That keeps each accent's
/// character, and slate stays restrained, while a filled button holds its own
/// on near-black.
const double _accentLightnessDark = 0.78;
const double _accentVividnessBoostDark = 1.15;

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

  // Neutrals. The raised surface and the control fill are perceptual steps
  // (see `_raisedLiftDark`); everything that has to be *read* or *found* against
  // them is still a contrast target, solved with `ToneAnchor.ground` so it lands
  // at its target rather than past it — a hairline that overshoots is a frame.
  final surface =
      isDark
          ? toneOf(_neutralSeed, oklchOf(background).l + _raisedLiftDark)
          : toneOf(_neutralSeed, 1.0);
  final controlFill = toneOf(
    _neutralSeed,
    isDark
        ? oklchOf(surface).l + _controlStepDark
        : oklchOf(background).l - _controlStepLight,
  );
  // Ink is solved against the hardest of the three grounds, so it reads on all
  // of them. The control fill is the extreme in both modes — the lightest ground
  // in dark mode, the darkest in light mode — but the comparison is spelled out
  // rather than assumed.
  final grounds = [background, surface, controlFill];
  Color hardestFor(Color ink) => grounds.reduce(
    (a, b) => contrastRatio(ink, a) <= contrastRatio(ink, b) ? a : b,
  );
  final hairline = solveForContrast(
    seed: _neutralSeed,
    against: surface,
    target: _hairlineTarget,
    preferLighter: preferLighter,
  );
  final border = solveForContrast(
    seed: _neutralSeed,
    // A control edge sits on the page or on a sheet, not on another control.
    against:
        contrastRatio(_neutralSeed, background) <
                contrastRatio(_neutralSeed, surface)
            ? background
            : surface,
    target: _borderTarget,
    preferLighter: preferLighter,
  );
  final textPrimary = solveForContrast(
    seed: _neutralSeed,
    against: hardestFor(_neutralSeed),
    target: 13.0,
    preferLighter: preferLighter,
  );
  final textSecondary = solveForContrast(
    seed: _neutralSeed,
    against: hardestFor(_neutralSeed),
    target: 4.5,
    preferLighter: preferLighter,
  );
  final shadow = toneOf(_neutralSeed, 0.12);

  // Accent roles. `ToneAnchor.seed`: the seed *is* the intended accent, so it is
  // kept whenever it already reads and moved only when it doesn't — that single
  // rule is the fix for both the illegible dark-mode label and the dead light
  // mode, which used to draw dark hexes on a light page.
  //
  // Chroma follows the seed's *vividness*, not its absolute chroma: a role that
  // darkens the seed keeps the same share of what sRGB allows at the new
  // lightness. With fixed chroma, the light-mode text tones came out dusty on
  // violet and pink, where the gamut is wide, and brown on amber, where it is
  // narrow. The cap keeps a saturated seed from turning back into neon.
  final seedTone = oklchOf(seed);
  final vividness = math.min(
    1.0,
    vividnessOf(seed) * (isDark ? _accentVividnessBoostDark : 1.0),
  );
  final chromaCap = isDark ? _accentChromaCapDark : _accentChromaCapLight;
  double accentChroma(double l) =>
      math.min(chromaCap, vividness * maxChroma(l, seedTone.h));
  // Light mode solves its roles from the seed. Dark mode solves them from one
  // richer tone (see `_accentLightnessDark`), which already clears every
  // target, so ink, fill and wordmark all come out as that tone.
  final darkLightness = math.max(seedTone.l, _accentLightnessDark);
  final roleSeed =
      isDark
          ? colorFromOklch(
            darkLightness,
            accentChroma(darkLightness),
            seedTone.h,
          )
          : seed;
  final accent = solveForContrast(
    seed: roleSeed,
    against: hardestFor(roleSeed),
    target: 4.5,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
    chromaAt: accentChroma,
  );
  final accentFill = solveForContrast(
    seed: roleSeed,
    against: background,
    target: 3.0,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
    chromaAt: accentChroma,
  );
  final onAccent = bestForeground(accentFill);
  // Light mode gives the wordmark more chroma than the controls: the light
  // accent is darkened for text contrast, which mutes it, and the signature
  // shouldn't be. Slate retains its deliberately restrained chroma. Dark mode's
  // accent is already the signature tone, so the wordmark is simply the accent.
  final Color brandAccent;
  if (isDark) {
    brandAccent = accent;
  } else {
    final brandSeed = colorFromOklch(
      seedTone.l,
      math.min(seedTone.c * 1.8, 0.18),
      seedTone.h,
    );
    final brandGround =
        contrastRatio(brandSeed, background) < contrastRatio(brandSeed, surface)
            ? background
            : surface;
    brandAccent = solveForContrast(
      seed: brandSeed,
      against: brandGround,
      target: 4.5,
      preferLighter: preferLighter,
      anchor: ToneAnchor.seed,
    );
  }
  // The two washes are even perceptual steps from the background up to the fill,
  // opaque — not `accent.withAlpha(...)`, which composited differently on every
  // ground and drifted the token between screens.
  //
  // Chroma climbs from the neutral page to the fill too, eased by √fraction.
  // Holding the seed's full chroma near white or black, where cyan and green
  // have the most gamut, turned the selected-state wash neon in light mode and
  // a heavy wine or forest green in dark mode.
  final fillTone = oklchOf(accentFill);
  final backgroundL = oklchOf(background).l;
  Color wash(double fraction) => colorFromOklch(
    backgroundL + (fillTone.l - backgroundL) * fraction,
    fillTone.c * math.sqrt(fraction),
    seedTone.h,
  );
  final accentMuted = wash(1 / 3);
  final accentDim = wash(2 / 3);

  // Error and success are the two ends of the same traffic-light ramp the RPE
  // badges use — same hue, same chroma, same lightness seed (see
  // `semantic_colors.dart`), so "bad" and "good" mean one colour each across the
  // whole app instead of a Material red here and a hand-picked red there. Both
  // are solved on the hardest ground, and both are used as grounds in places;
  // `onColor` supplies their foreground.
  final errorSeed = colorFromOklch(
    _semanticLightness,
    0.17,
    29 * math.pi / 180,
  );
  final error = solveForContrast(
    seed: errorSeed,
    against: hardestFor(errorSeed),
    target: 4.5,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
  );
  final successSeed = colorFromOklch(
    _semanticLightness,
    0.15,
    150 * math.pi / 180,
  );
  final success = solveForContrast(
    seed: successSeed,
    against: hardestFor(successSeed),
    target: 4.5,
    preferLighter: preferLighter,
    anchor: ToneAnchor.seed,
  );

  return AppColorScheme(
    background: background,
    surface: surface,
    controlFill: controlFill,
    hairline: hairline,
    border: border,
    shadow: shadow,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    error: error,
    success: success,
    accent: accent,
    brandAccent: brandAccent,
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

/// Page transitions follow the platform. They are stated here rather than left
/// to Material's defaults, so a Flutter upgrade can't change them unnoticed:
///
/// - Android: [PredictiveBackPageTransitionsBuilder]. On Android 13+ a back
///   swipe previews the page underneath and can be cancelled; a push, or Back
///   from a button, plays Android's fade-forwards slide (450ms).
/// - iOS and macOS: [CupertinoPageTransitionsBuilder], the platform slide with
///   edge-swipe back.
/// - Windows, Linux and Fuchsia: [ZoomPageTransitionsBuilder], Material's
///   zoom, which reads well on a wide window where a slide would travel far.
///
/// Each of these carries the platform's back gesture, which is why the app
/// keeps them instead of drawing its own. Pages guarding unsaved work still
/// intercept both gestures through `PopScope`, and `PlanTitleHero` flies the
/// same under all three. The fade-forwards and zoom transitions show a
/// backdrop between the two pages that Material fills with
/// `ColorScheme.surface`: here the *raised* ground, which in dark mode
/// flashes grey between two black pages, so the page colour is passed
/// instead. Under reduced motion a push or pop is immediate; a back swipe
/// still follows the finger.
PageTransitionsTheme _pageTransitions(Color page) {
  final android = _ReducedMotionPageTransitions(
    PredictiveBackPageTransitionsBuilder(fallbackColor: page),
  );
  const cupertino = _ReducedMotionPageTransitions(
    CupertinoPageTransitionsBuilder(),
  );
  final zoom = _ReducedMotionPageTransitions(
    ZoomPageTransitionsBuilder(backgroundColor: page),
  );
  return PageTransitionsTheme(
    builders: {
      TargetPlatform.android: android,
      TargetPlatform.iOS: cupertino,
      TargetPlatform.macOS: cupertino,
      TargetPlatform.windows: zoom,
      TargetPlatform.linux: zoom,
      TargetPlatform.fuchsia: zoom,
    },
  );
}

/// [platform]'s transition, made immediate when the system asks for reduced
/// motion.
///
/// A route reads its duration once, without a [BuildContext], so this reads
/// the platform's setting directly: the same one `MediaQuery` reports in the
/// app. The transition itself is left alone, because it also carries the back
/// gesture; with no time to play, a push or pop simply lands.
class _ReducedMotionPageTransitions extends PageTransitionsBuilder {
  final PageTransitionsBuilder platform;

  const _ReducedMotionPageTransitions(this.platform);

  static bool get _reduced =>
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;

  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : platform.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : platform.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      platform.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => platform.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    child,
  );
}

ThemeData buildTheme(Color seed, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = _deriveScheme(seed, isDark);

  final background = c.background;
  final surface = c.surface;
  final controlFill = c.controlFill;
  final hairline = c.hairline;
  final border = c.border;
  final textPrimary = c.textPrimary;
  final textSecondary = c.textSecondary;
  final error = c.error;
  final accent = c.accent;
  final accentFill = c.accentFill;
  final onAccent = c.onAccent;
  final textTheme = AppTypography.textTheme(textPrimary, textSecondary);
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
      onSurfaceVariant: textSecondary,
      // Material's container ladder, mapped onto the app's three grounds so
      // menus, dropdowns and search bars pick the same fills as our own widgets.
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: controlFill,
      surfaceContainerHighest: controlFill,
      outline: border,
      outlineVariant: hairline,
      shadow: c.shadow,
    ),
    extensions: [c],
    pageTransitionsTheme: _pageTransitions(background),
    fontFamily: GoogleFonts.manrope().fontFamily,
    textTheme: textTheme,
    // One header everywhere: flat on the page colour with a permanent hairline,
    // so scrolling content never tints it. Back is neutral; actions keep the
    // accent.
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: hairline)),
      centerTitle: false,
      // Screen titles carry the page: a size up from section titles, heavy
      // and tightly set.
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: textPrimary),
      actionsIconTheme: IconThemeData(color: accent),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const Icon(LucideIcons.arrowLeft),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: hairline, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentFill,
        foregroundColor: onAccent,
        disabledBackgroundColor: controlFill,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: textTheme.labelLarge,
      ).copyWith(overlayColor: interactionOverlay(onAccent)),
    ),
    // The secondary button is a filled neutral, not an outline: a ground means
    // tappable, and a box drawn round nothing reads as a disabled field.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: controlFill,
        foregroundColor: textPrimary,
        disabledBackgroundColor: controlFill,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: textTheme.labelLarge,
      ).copyWith(overlayColor: interactionOverlay(textPrimary)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        textStyle: textTheme.labelLarge,
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
    // Filled fields: the fill is the field, so a ring only appears for focus or
    // an error. The label floats inside the fill, never onto an edge.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: controlFill,
      border: const RingInputBorder(borderRadius: AppRadius.field),
      enabledBorder: const RingInputBorder(borderRadius: AppRadius.field),
      disabledBorder: const RingInputBorder(borderRadius: AppRadius.field),
      focusedBorder: RingInputBorder(
        borderRadius: AppRadius.field,
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: RingInputBorder(
        borderRadius: AppRadius.field,
        borderSide: BorderSide(color: error, width: 1.5),
      ),
      focusedErrorBorder: RingInputBorder(
        borderRadius: AppRadius.field,
        borderSide: BorderSide(color: error, width: 2),
      ),
      floatingLabelStyle: textTheme.bodyMedium?.copyWith(
        color: textSecondary,
        fontWeight: FontWeight.w600,
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: controlFill,
      // A selected chip is a ground with a label on it, so it takes the fill
      // tone and the foreground solved against that fill.
      selectedColor: accentFill,
      labelStyle: textTheme.labelMedium?.copyWith(color: textPrimary),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: onAccent),
      side: BorderSide.none,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.chip,
        side: BorderSide.none,
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
        return controlFill;
      }),
      // An off switch is an unfilled control, so its edge is the 3:1 border.
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.transparent : border,
      ),
    ),
    // Rows sit on whatever ground holds them; a list is not a stack of tiles.
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: textPrimary,
      iconColor: accent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      // The scrim separates a dialog from the page; an outline would only frame
      // it. Dark mode keeps a hairline, since its lift off the scrim is small.
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.dialog,
        side: isDark ? BorderSide(color: hairline) : BorderSide.none,
      ),
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(height: 1.5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: textPrimary),
      elevation: isDark ? 0 : 6,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.button,
        side: isDark ? BorderSide(color: hairline) : BorderSide.none,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: textSecondary,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelLarge,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: isDark ? BorderSide(color: hairline) : BorderSide.none,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      circularTrackColor: controlFill,
      linearTrackColor: controlFill,
    ),
    iconTheme: IconThemeData(color: accent),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: hairline, width: 1),
        borderRadius: AppRadius.chip,
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: textPrimary),
    ),
  );
}
