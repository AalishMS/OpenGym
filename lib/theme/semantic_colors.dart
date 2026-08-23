import 'package:flutter/material.dart';

/// RPE (Rate of Perceived Exertion) → colour ramp.
///
/// An intentional traffic-light scale: calm/grey when easy, hot/red when
/// maximal. Centralised here so every RPE readout in the app stays identical.
/// (Kept as Material colour constants to preserve the exact existing look.)
Color rpeColor(int rpe) {
  if (rpe <= 2) return Colors.grey;
  if (rpe <= 4) return Colors.lightBlue;
  if (rpe <= 6) return Colors.green;
  if (rpe <= 8) return Colors.amber;
  if (rpe == 9) return Colors.orange;
  return Colors.red;
}
