import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tones.dart';

/// RPE (Rate of Perceived Exertion) → colour ramp.
///
/// An intentional traffic-light scale: calm/grey when easy, hot/red when
/// maximal. Centralised here so every RPE readout in the app stays identical.
///
/// These used to be Material colour constants (`Colors.green`, `Colors.amber`
/// …), picked against dark mode and never revisited. All six scored between
/// 1.49:1 and 3.37:1 on the light background, so in light mode the ramp read as
/// six shades of pale. The hues below are the same traffic-light progression;
/// only the tone is now solved per mode, against the card the badge sits on.
class _RpeStep {
  /// Hue in degrees. `null` is the neutral bottom of the ramp, which carries no
  /// hue at all — "so easy it isn't worth colouring".
  final double? hue;
  final double chroma;

  const _RpeStep(this.hue, this.chroma);
}

/// Where the seeds sit before solving. One lightness for all six so the ramp
/// reads as a progression of *hue*, not of brightness.
const double _seedLightness = 0.62;

/// Ordered easy → maximal, matching the thresholds in [rpeColor].
const List<_RpeStep> _steps = [
  _RpeStep(null, 0), // ≤2  neutral
  _RpeStep(245, 0.13), // 3-4  blue
  _RpeStep(150, 0.15), // 5-6  green
  _RpeStep(85, 0.15), // 7-8  amber
  _RpeStep(55, 0.16), // 9    orange
  _RpeStep(29, 0.17), // 10   red
];

/// The colour for an RPE value, resolved for the current mode.
///
/// Solved against the surface, which is the harder of the two grounds in either
/// mode, so the badge stays legible on a card *and* on the page behind it.
Color rpeColor(int rpe, BuildContext context) {
  final step = _steps[_indexFor(rpe)];
  final seed = step.hue == null
      ? colorFromOklch(_seedLightness, 0, 0)
      : colorFromOklch(
          _seedLightness, step.chroma, step.hue! * math.pi / 180);
  return solveForContrast(
    seed: seed,
    against: surfaceColor(context),
    target: 4.5,
    preferLighter: Theme.of(context).brightness == Brightness.dark,
    anchor: ToneAnchor.seed,
  );
}

int _indexFor(int rpe) {
  if (rpe <= 2) return 0;
  if (rpe <= 4) return 1;
  if (rpe <= 6) return 2;
  if (rpe <= 8) return 3;
  if (rpe == 9) return 4;
  return 5;
}
