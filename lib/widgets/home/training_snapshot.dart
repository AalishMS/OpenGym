import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/workout_plan.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// Completed sets by calendar day, with a dot under today's letter.
///
/// The seven days are always drawn, so the week keeps its frame and today
/// stays marked before anything is logged. An empty week is just the day
/// letters; the bars' slot opens once a day has training, so a week not yet
/// started costs the plans below no more than a line.
class TrainingSnapshot extends StatelessWidget {
  final List<WorkoutPlan> plans;
  final List<WorkoutSession> sessions;
  final VoidCallback? onOpenWeeklyTraining;
  final ValueChanged<WorkoutSession>? onOpenLastWorkout;
  final DateTime? now;

  const TrainingSnapshot({
    required this.plans,
    required this.sessions,
    this.onOpenWeeklyTraining,
    this.onOpenLastWorkout,
    this.now,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final weekStart = startOfWeek(today);
    final todayIndex = calendarDaysBetween(weekStart, today);
    final dailySets = List<int>.filled(7, 0);
    final dailyWorkouts = List<int>.filled(7, 0);
    final latestByDay = List<WorkoutSession?>.filled(7, null);
    for (final session in sessions) {
      if (!session.isCompleted) continue;
      final index = calendarDaysBetween(weekStart, session.date);
      if (index < 0 || index > todayIndex) continue;
      dailyWorkouts[index]++;
      dailySets[index] += session.exercises.fold<int>(
        0,
        (sum, exercise) =>
            sum + exercise.sets.where((set) => set.reps > 0).length,
      );
      final latest = latestByDay[index];
      if (latest == null || session.date.isAfter(latest.date)) {
        latestByDay[index] = session;
      }
    }
    final workouts = dailyWorkouts.fold<int>(0, (sum, value) => sum + value);
    final sets = dailySets.fold<int>(0, (sum, value) => sum + value);
    final maxSets = dailySets.reduce(math.max);
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    // Keep the same summary and navigation affordance before the first log.
    final summary =
        workouts == 0
            ? '0 workouts'
            : '${countOf(workouts, 'workout')} · ${countOf(sets, 'set')}';
    final summaryLink = Semantics(
      button: onOpenWeeklyTraining != null,
      label: 'This week: $summary. View weekly training statistics',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('weekly-training-link'),
        onTap: onOpenWeeklyTraining,
        borderRadius: AppRadius.control,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      // Set like its sibling heading, *Your plans*.
                      Text(
                        'This week',
                        style: textTheme.titleMedium?.copyWith(
                          color: textPrimaryColor(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        summary,
                        style: textTheme.bodySmall?.copyWith(color: secondary),
                      ),
                    ],
                  ),
                ),
                if (onOpenWeeklyTraining != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(LucideIcons.chevronRight, size: 16, color: secondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summaryLink,
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: 'Completed sets by day. Today is marked with a dot.',
            // Seven contiguous, equal targets always share the card width, so
            // Sunday never scrolls off a phone: 48dp each from a 390dp phone,
            // about 47dp at 360dp, never under the 24dp minimum. The bars are
            // inset inside their targets instead of gapped between them.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < 7; index++)
                  Expanded(
                    child: Semantics(
                      label:
                          '${names[index]}: '
                          '${countOf(dailyWorkouts[index], 'workout')}, '
                          '${countOf(dailySets[index], 'set')}'
                          '${index == todayIndex ? ', today' : ''}',
                      button:
                          latestByDay[index] != null &&
                          onOpenLastWorkout != null,
                      child: Tooltip(
                        message:
                            '${names[index]} · '
                            '${countOf(dailyWorkouts[index], 'workout')} · '
                            '${countOf(dailySets[index], 'set')}',
                        child: InkWell(
                          key: ValueKey('training-day-$index'),
                          onTap:
                              latestByDay[index] == null ||
                                      onOpenLastWorkout == null
                                  ? null
                                  : () =>
                                      onOpenLastWorkout!(latestByDay[index]!),
                          borderRadius: AppRadius.control,
                          child: ExcludeSemantics(
                            child: _DayColumn(
                              letter: letters[index],
                              trained: dailyWorkouts[index] > 0,
                              today: index == todayIndex,
                              emptyWeek: workouts == 0,
                              share:
                                  maxSets == 0 ? 0 : dailySets[index] / maxSets,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One day: a bar that grows with the day's sets, then its letter. Today
/// reads apart through its letter and a small accent dot under it, the same
/// mark the workout uses for the week being trained now.
///
/// A bar first appears at its height. It grows or shrinks over
/// [AppMotion.long] only when its day changes while Home can be seen, such
/// as a workout synced in. A change made while a page covers Home, such as
/// the workout just finished, has no tickers to run on and would play as
/// that page leaves, so it lands at once: coming back replays no growth.
class _DayColumn extends StatelessWidget {
  final String letter;
  final bool trained;
  final bool today;
  final double share;

  /// Nothing logged this week: the bars' slot is closed, leaving the letter
  /// and today's dot, and opens (as the bars grow) once a day has training.
  final bool emptyWeek;

  const _DayColumn({
    required this.letter,
    required this.trained,
    required this.today,
    required this.share,
    required this.emptyWeek,
  });

  static const double _barWidth = 16;
  static const double _baseline = 5;

  /// The bars' height, and the gap between them and the letter.
  static const double _slot = 52 + AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Read here so the bar also rebuilds as Home is covered and uncovered.
    final seen = TickerMode.valuesOf(context).enabled;
    final duration =
        seen ? AppMotion.of(context, AppMotion.long) : Duration.zero;
    // A narrow bar centred in its 48dp target, so the strip reads as a
    // chart rather than a row of tiles.
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: emptyWeek ? 0 : _slot),
          duration: duration,
          curve: AppMotion.curve,
          builder:
              (context, slot, child) =>
                  ClipRect(child: SizedBox(height: slot, child: child)),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: trained ? 14 + 38 * share : _baseline),
                duration: duration,
                curve: AppMotion.curve,
                builder:
                    (context, height, _) => Container(
                      width: _barWidth,
                      height: height,
                      decoration: BoxDecoration(
                        color:
                            trained
                                ? accentFillColor(context)
                                : today
                                ? textSecondaryColor(context)
                                : borderColor(context),
                        borderRadius: AppRadius.control,
                      ),
                    ),
              ),
            ),
          ),
        ),
        Text(
          letter,
          style: textTheme.labelSmall?.copyWith(
            color:
                today ? textPrimaryColor(context) : textSecondaryColor(context),
            fontWeight: today ? FontWeight.w700 : null,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          height: 4,
          child:
              today
                  ? DecoratedBox(
                    key: const ValueKey('training-day-today-dot'),
                    decoration: BoxDecoration(
                      color: accentColor(context),
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 4, height: 4),
                  )
                  : null,
        ),
      ],
    );
  }
}
