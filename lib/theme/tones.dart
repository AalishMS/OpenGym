/// The app's colour maths: OKLab/OKLCh conversion, WCAG contrast, and a solver
/// that finds a *tone* meeting a contrast target.
///
/// The point of this file is a change of approach. Colours used to be picked as
/// finished endpoints — fourteen accent hexes, ten plan hexes, six RPE hexes —
/// and every one of them had to be independently lucky against four different
/// grounds. Most weren't: CYAN's filled-button label scored 1.95:1, and in light
/// mode the accent was drawn from the dark palette at 1.79:1.
///
/// So nothing here picks a colour. A colour is a *seed* carrying hue and chroma,
/// and the role it plays decides its lightness by [solveForContrast] — bisecting
/// OKLab lightness until the WCAG ratio against the real ground is met. Hue and
/// chroma survive untouched, so an accent keeps its character; only lightness
/// moves, and only as far as legibility demands. A failing combination stops
/// being a bug to notice and becomes a state the system cannot express.
///
/// OKLab rather than HSL because it is perceptually uniform: equal lightness
/// steps look equal, which is what lets the heatmap's three intensity steps read
/// as even for every accent. The ~50 lines of conversion are hand-written on
/// purpose — the package that supplies HCT (`material_color_utilities`) is only
/// a transitive dependency here, and this pubspec already records two
/// dependency-resolution fights we don't want a third of.
///
/// Constants are Björn Ottosson's published sRGB↔OKLab matrices.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

// ---------------------------------------------------------------------------
// sRGB transfer function
// ---------------------------------------------------------------------------

/// Gamma-encoded sRGB channel (0..1) → linear light.
double _toLinear(double c) => c <= 0.04045
    ? c / 12.92
    : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Linear light → gamma-encoded sRGB channel (0..1).
///
/// Clamps into gamut *before* encoding. OKLab spans colours sRGB cannot show, so
/// a solved tone can land outside the cube; clamping here means every colour the
/// solver measures is one the screen can actually produce. Measuring an
/// unclamped value would let out-of-gamut chroma fake a passing contrast that
/// disappears the moment it is painted.
double _toGamma(double c) {
  final v = c.clamp(0.0, 1.0);
  return v <= 0.0031308
      ? 12.92 * v
      : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
}

/// `dart:math` has no cube root, and the sign guard matters: linear channels are
/// non-negative, but the LMS intermediates can go slightly negative for colours
/// near the gamut edge, and `pow(negative, 1/3)` is NaN.
double _cbrt(double x) => x < 0
    ? -math.pow(-x, 1 / 3).toDouble()
    : math.pow(x, 1 / 3).toDouble();

// ---------------------------------------------------------------------------
// OKLCh
// ---------------------------------------------------------------------------

/// A colour taken apart in OKLCh — the cylindrical form of OKLab.
///
/// [l] is perceptual lightness (0 black, 1 white), [c] is chroma (0 is a true
/// neutral, ~0.37 is about as saturated as sRGB reaches), [h] is hue in radians.
/// Roles move [l] and leave [c] and [h] alone; that split is the whole design.
class Oklch {
  final double l;
  final double c;
  final double h;

  const Oklch(this.l, this.c, this.h);
}

/// Decomposes [color] into OKLCh. Alpha is not part of the model — every colour
/// this file produces is opaque, which is deliberate: the ramps it replaces were
/// built from `withAlpha`, and an alpha wash composites differently against
/// every ground, so the same token drifted between screens.
Oklch oklchOf(Color color) {
  final r = _toLinear(color.r);
  final g = _toLinear(color.g);
  final b = _toLinear(color.b);

  final lCone = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  final mCone = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  final sCone = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

  final l_ = _cbrt(lCone);
  final m_ = _cbrt(mCone);
  final s_ = _cbrt(sCone);

  final lab0 = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
  final lab1 = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
  final lab2 = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

  return Oklch(lab0, math.sqrt(lab1 * lab1 + lab2 * lab2), math.atan2(lab2, lab1));
}

/// Builds an opaque [Color] from OKLCh, clamped into sRGB. See [_toGamma].
Color colorFromOklch(double l, double c, double h) {
  final a = c * math.cos(h);
  final b = c * math.sin(h);

  final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = l - 0.0894841775 * a - 1.2914855480 * b;

  final lCone = l_ * l_ * l_;
  final mCone = m_ * m_ * m_;
  final sCone = s_ * s_ * s_;

  return Color.from(
    alpha: 1.0,
    red: _toGamma(
        4.0767416621 * lCone - 3.3077115913 * mCone + 0.2309699292 * sCone),
    green: _toGamma(
        -1.2684380046 * lCone + 2.6097574011 * mCone - 0.3413193965 * sCone),
    blue: _toGamma(
        -0.0041960863 * lCone - 0.7034186147 * mCone + 1.7076147010 * sCone),
  );
}

// ---------------------------------------------------------------------------
// Contrast
// ---------------------------------------------------------------------------

/// WCAG contrast ratio between two opaque colours, from 1.0 (identical) to 21.0
/// (black on white). AA asks 4.5 for body text and 3.0 for icons and UI edges.
///
/// `Color.computeLuminance` is already WCAG relative luminance, so it is used
/// rather than reimplemented.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Whichever of black or white is actually more legible on [ground].
///
/// This replaces a `luminance > 0.5` test, which sounds right and is not: the
/// luminance where black and white are equally legible is **0.179**, from
/// solving `(L + 0.05)² = 0.0525`. Everything between 0.179 and 0.5 — most of
/// the accent set — was being handed a white label where black was the readable
/// choice, which is how CYAN's `[NEXT]` ended up at 1.95:1 instead of 10.75:1.
///
/// Comparing the two candidates outright means there is no threshold left to get
/// wrong, so the constant is gone rather than corrected.
///
/// This is the one function in the app allowed to name black or white; see the
/// `onColor` contract in AGENTS.md.
Color bestForeground(Color ground) {
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);
  return contrastRatio(black, ground) >= contrastRatio(white, ground)
      ? black
      : white;
}

// ---------------------------------------------------------------------------
// Solving
// ---------------------------------------------------------------------------

/// How far a solved tone may sit from the seed it came from.
///
/// A foreground and a ground want opposite things from the same solver, and
/// conflating them was a real bug in the first draft of this system: a mid-grey
/// neutral seed already clears a 1.45:1 surface target, so "keep the seed when
/// it passes" produced mid-grey cards.
enum ToneAnchor {
  /// Keep the seed untouched when it already meets the target, and move only
  /// when it fails. For foregrounds — accent text, plan labels, RPE — where the
  /// seed *is* the intended colour and exceeding the target is not a fault.
  seed,

  /// Always land *at* the target: the tone nearest the ground that still passes.
  /// For grounds and washes — surface, border, secondary text — where the target
  /// describes the separation wanted, so overshooting is as wrong as undershooting.
  ground,
}

/// The number of bisection steps. 22 halvings resolve lightness to ~2.4e-7,
/// far finer than the 1/255 the result quantises to — deliberately more than
/// needed so this reproduces the verified comparison harness in
/// `docs/color-study.html` exactly, rather than approximately. It runs a couple
/// of dozen times per theme build, so the cost is nil.
const int _bisectionSteps = 22;

/// Moves [seed]'s lightness until it meets [target] contrast against [against],
/// keeping its hue and chroma.
///
/// [preferLighter] picks which side of the ground to solve on — a mid-tone seed
/// can usually reach the target by going either lighter or darker, and the theme
/// decides: lighter in dark mode, darker in light mode. Without it a dark-mode
/// accent could legally resolve to a near-black that technically passes against
/// the card but abandons the palette.
///
/// Returns the nearest in-gamut extreme when the target is unreachable (a
/// high-chroma yellow cannot reach 4.5:1 against white however dark it goes),
/// which is a best effort rather than a lie — the accompanying test asserts the
/// targets that must actually hold.
Color solveForContrast({
  required Color seed,
  required Color against,
  required double target,
  required bool preferLighter,
  ToneAnchor anchor = ToneAnchor.ground,
}) {
  if (anchor == ToneAnchor.seed && contrastRatio(seed, against) >= target) {
    return seed;
  }

  final s = oklchOf(seed);

  final extreme = colorFromOklch(preferLighter ? 1.0 : 0.0, s.c, s.h);
  if (contrastRatio(extreme, against) < target) return extreme;

  // Bracket between the ground itself (contrast 1.0, always failing) and the
  // extreme (known to pass), so the invariant holds from the first iteration.
  final groundL = oklchOf(against).l;
  var lo = preferLighter ? groundL : 0.0;
  var hi = preferLighter ? 1.0 : groundL;

  for (var i = 0; i < _bisectionSteps; i++) {
    final mid = (lo + hi) / 2;
    final passes =
        contrastRatio(colorFromOklch(mid, s.c, s.h), against) >= target;
    if (preferLighter) {
      // Converge downward onto the dimmest passing tone.
      if (passes) {
        hi = mid;
      } else {
        lo = mid;
      }
    } else {
      // Mirror image: upward onto the lightest passing tone.
      if (passes) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
  }

  return colorFromOklch(preferLighter ? hi : lo, s.c, s.h);
}

/// [seed]'s hue and chroma at an explicit [lightness]. The primitive behind
/// [toneBetween] and the plan/RPE hue construction.
Color toneOf(Color seed, double lightness) {
  final s = oklchOf(seed);
  return colorFromOklch(lightness, s.c, s.h);
}

/// The tone [fraction] of the way from [from]'s lightness to [to]'s, wearing
/// [seed]'s hue and chroma.
///
/// This is how the heatmap's intensity steps are built. Solving them to fixed
/// contrast targets instead looks reasonable and isn't: because `accentFill`
/// itself moves per accent and per mode, fixed targets of 1.3 and 2.1 produced
/// a dark-mode ramp of 1.33 → 2.11 → 7.45, three "steps" whose last is a cliff.
/// Even fractions of the lightness *span* are even by construction; the tones
/// they realise are even too for a low-chroma accent, and drift by a few
/// hundredths for a saturated one, whose darkest step leaves sRGB and gets
/// clamped back up. Either way the ramp lands within ~0.2 of the
/// `withAlpha(90/160)` ramp it replaces, so the existing look survives becoming
/// correct.
Color toneBetween({
  required Color seed,
  required Color from,
  required Color to,
  required double fraction,
}) {
  final fromL = oklchOf(from).l;
  final toL = oklchOf(to).l;
  return toneOf(seed, fromL + (toL - fromL) * fraction);
}
