import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The smallest step × 10ⁿ at or above [value], on a scale fine enough that
/// the tallest mark still fills most of the plot, so a chart's top guide
/// carries a round label instead of an arbitrary padded maximum.
double niceAxisCeiling(double value) {
  if (value <= 0 || !value.isFinite) return 1;
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor());
  for (final step in const [
    1.0,
    1.5,
    2.0,
    2.5,
    3.0,
    4.0,
    5.0,
    6.0,
    8.0,
    10.0,
  ]) {
    // A relative tolerance absorbs float error such as 3 × 0.1.
    if (step * magnitude >= value * (1 - 1e-9)) {
      return (step * magnitude).toDouble();
    }
  }
  return (10 * magnitude).toDouble();
}

/// The shared line, wash and selection marker of the Strength and Blocks trends.
/// [points] are already laid out in the painter's coordinate space.
class TrendLinePainter extends CustomPainter {
  final List<Offset> points;
  final int selected;
  final Color ink;
  final Color wash;
  final Color ground;
  final Color guide;

  const TrendLinePainter({
    required this.points,
    required this.selected,
    required this.ink,
    required this.wash,
    required this.ground,
    required this.guide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = guide,
      );
    }
    if (points.isEmpty) return;
    if (points.length > 1) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        line.lineTo(point.dx, point.dy);
      }
      final area =
          Path.from(line)
            ..lineTo(points.last.dx, size.height)
            ..lineTo(points.first.dx, size.height)
            ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [wash, ground],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = ink
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    final marker = points[selected.clamp(0, points.length - 1)];
    canvas.drawLine(
      Offset(marker.dx, marker.dy + 8),
      Offset(marker.dx, size.height),
      Paint()..color = guide,
    );
    for (final point in points) {
      canvas.drawCircle(point, 2.5, Paint()..color = ink);
    }
    canvas.drawCircle(marker, 7, Paint()..color = ground);
    canvas.drawCircle(marker, 5, Paint()..color = ink);
    canvas.drawCircle(marker, 2, Paint()..color = ground);
  }

  @override
  bool shouldRepaint(TrendLinePainter old) =>
      !listEquals(old.points, points) ||
      old.selected != selected ||
      old.ink != ink ||
      old.wash != wash ||
      old.ground != ground ||
      old.guide != guide;
}
