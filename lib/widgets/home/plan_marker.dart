import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';

/// A plan's colour as a rounded square holding its place in the rotation.
///
/// Home's rows and Manage's cards draw the same mark, in the plan's own
/// resolved colour, so the colour picked for a plan is the colour seen for
/// it, and entering Manage doesn't repaint every badge. Screen readers hear
/// its place (`Workout 2 of 5`); the plan's name is read once, from the row.
class PlanMarker extends StatelessWidget {
  final WorkoutPlan plan;

  /// One-based place in the split's rotation.
  final int number;

  /// How many plans the rotation holds, for the spoken `of N`.
  final int? count;

  const PlanMarker({
    required this.plan,
    required this.number,
    this.count,
    super.key,
  });

  static const double _side = 40;

  @override
  Widget build(BuildContext context) {
    final color = planColorOf(plan.planColor, context);
    // Grows with the text inside it, but only so far: past 1.5x the marker
    // would crowd the name it sits beside.
    final side = math.min(
      MediaQuery.textScalerOf(context).scale(_side),
      _side * 1.5,
    );

    return Semantics(
      label: count == null ? 'Workout $number' : 'Workout $number of $count',
      child: ExcludeSemantics(
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadius.button,
          ),
          child: Text(
            '$number',
            style: AppTypography.figures(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: onColor(color),
            ),
          ),
        ),
      ),
    );
  }
}
