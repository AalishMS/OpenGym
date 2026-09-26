import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// Monday to Sunday of the current week, one dot per day.
///
/// A day with a workout is filled with that plan's colour, so the strip shows
/// what was trained as well as how often. Today carries an accent ring until
/// something is logged. Days still to come have no outline, which keeps them
/// quieter than the days that were missed.
class WeekStrip extends StatelessWidget {
  final List<WorkoutPlan> plans;
  final List<WorkoutSession> sessions;

  /// Now, for placing today. Tests pin it.
  final DateTime? now;

  const WeekStrip({
    required this.plans,
    required this.sessions,
    this.now,
    super.key,
  });

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final today = now ?? DateTime.now();
    final weekStart = startOfWeek(today);
    final todayOffset = calendarDaysBetween(weekStart, today);

    final byDay = List.generate(7, (_) => <WorkoutSession>[]);
    for (final session in sessions) {
      final offset = calendarDaysBetween(weekStart, session.date);
      if (offset >= 0 && offset < 7) byDay[offset].add(session);
    }
    final count = byDay.fold<int>(0, (sum, day) => sum + day.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'This week',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: textPrimaryColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                switch (count) {
                  0 => 'No workouts yet',
                  1 => '1 workout',
                  _ => '$count workouts',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            for (var day = 0; day < 7; day++)
              Expanded(
                child: Semantics(
                  label: _dayLabel(day, day == todayOffset, byDay[day]),
                  child: ExcludeSemantics(
                    child: Center(
                      child: _DayDot(
                        letter: _letters[day],
                        fill:
                            byDay[day].isEmpty
                                ? null
                                : _planColorFor(byDay[day].first, context),
                        isToday: day == todayOffset,
                        isFuture: day > todayOffset,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _dayLabel(int day, bool isToday, List<WorkoutSession> sessions) {
    final name = isToday ? '${_dayNames[day]}, today' : _dayNames[day];
    if (sessions.isEmpty) return '$name: no workout';
    return '$name: ${sessions.map((s) => titleCase(s.planName)).join(', ')}';
  }

  /// A session names its plan by id when it has one and by name otherwise,
  /// the same way `PlanStat` matches them. A session whose plan has since been
  /// deleted falls back to the accent, like a plan with no colour of its own.
  Color _planColorFor(WorkoutSession session, BuildContext context) {
    final name = session.planName.toLowerCase();
    for (final plan in plans) {
      final sameId = session.planId != null && session.planId == plan.id;
      if (sameId || plan.name.toLowerCase() == name) {
        return planColorOf(plan.planColor, context);
      }
    }
    return planColorOf(null, context);
  }
}

class _DayDot extends StatelessWidget {
  final String letter;

  /// The trained plan's colour, or null for a day with no workout.
  final Color? fill;
  final bool isToday;
  final bool isFuture;

  const _DayDot({
    required this.letter,
    required this.fill,
    required this.isToday,
    required this.isFuture,
  });

  @override
  Widget build(BuildContext context) {
    final fill = this.fill;
    final side = math.min(MediaQuery.textScalerOf(context).scale(32), 40.0);
    final Color foreground;
    if (fill != null) {
      foreground = onColor(fill);
    } else if (isToday) {
      foreground = accentColor(context);
    } else {
      foreground = textSecondaryColor(context);
    }

    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border:
            fill != null || isFuture
                ? null
                : Border.all(
                  color: isToday ? accentColor(context) : borderColor(context),
                  width: isToday ? 2 : 1,
                ),
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight:
              fill != null || isToday ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}
