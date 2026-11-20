import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tones.dart';

/// Plan stripe colours: ten hues spaced evenly around the OKLCh wheel.
///
/// The ten hand-picked hexes this replaces had two defects. They clustered —
/// two purples, two pinks, two blues — because they were chosen by eye, so
/// neighbouring plans were hard to tell apart. And none had a light-mode
/// variant: every one scored between 1.53:1 and 3.44:1 on the light background,
/// which is why a plan's colour all but vanished there. Even spacing removes
/// the clustering by construction, and the tone is solved per mode instead of
/// stored, so a stripe is legible on whichever ground it lands on.

/// Where a seed sits before solving. The lightness is a starting point, not a
/// promise — [planColorOf] moves it as far as contrast demands.
const double _seedLightness = 0.70;
const double _seedChroma = 0.16;
const int _slots = 10;
const double _step = 2 * math.pi / _slots;

/// Hue-and-chroma seed for plan slot [index].
Color planSeed(int index) =>
    colorFromOklch(_seedLightness, _seedChroma, (index % _slots) * _step);

/// What each slot is called aloud, so a screen reader names the colour a
/// swatch paints rather than its place in the palette. Slot hues step 36°
/// around OKLCh from 0°, which is where these names fall.
const List<String> kPlanColorNames = [
  'Rose',
  'Red',
  'Orange',
  'Olive',
  'Green',
  'Teal',
  'Cyan',
  'Blue',
  'Violet',
  'Purple',
];

/// The ten seeds as ARGB ints — the values a plan persists.
///
/// A plan stores a colour *value*, not a slot index (`WorkoutPlan.planColor`),
/// which is why [planColorOf] resolves by nearest hue: a plan saved before this
/// change still lands on the closest of these ten, with no Hive migration.
final List<int> kPlanColors =
    List.unmodifiable(List.generate(_slots, (i) => planSeed(i).toARGB32()));

/// Solves slot [slot] against the hardest ground it can be drawn on.
///
/// A plan colour labels rows on the page, cards and sheets, and sits beside
/// controls, so it is solved against whichever of those it reads worst on
/// ([hardestGroundFor]). One tone therefore serves as both a label colour
/// (needs 4.5:1) and a 2px stripe (needs 3:1) everywhere.
Color _resolve(int slot, BuildContext context) => solveForContrast(
      seed: planSeed(slot),
      against: hardestGroundFor(planSeed(slot), context),
      target: 4.5,
      preferLighter: Theme.of(context).brightness == Brightness.dark,
      anchor: ToneAnchor.seed,
    );

/// The colour to paint a plan's stripe, label, or chart series, resolved for the
/// current mode. [stored] is `WorkoutPlan.planColor`; `null` means the plan has
/// no colour of its own and inherits the accent.
Color planColorOf(int? stored, BuildContext context) => stored == null
    ? accentColor(context)
    : _resolve(planSlotOf(stored), context);

/// The swatch for slot [index] as it will actually be painted — for the
/// pickers, so the chip a user taps is the colour they get.
Color planSwatch(int index, BuildContext context) => _resolve(index, context);

/// The slot a [stored] value belongs to.
///
/// Hue is compared around the circle, so 350° matches 0°. This is what lets a
/// plan created before this change keep its identity — the old hand-picked
/// purple lands on the new purple slot — and what lets a picker still mark that
/// plan's current choice.
int planSlotOf(int stored) {
  final h = oklchOf(Color(stored)).h;
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < _slots; i++) {
    var d = (h - i * _step).abs() % (2 * math.pi);
    if (d > math.pi) d = 2 * math.pi - d;
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}
