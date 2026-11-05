import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/workout_plan.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../readable_table_viewport.dart';

/// Completed sets by calendar day, with a dot under today's letter.
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
            : '$workouts ${workouts == 1 ? 'workout' : 'workouts'} · '
                '$sets ${sets == 1 ? 'set' : 'sets'}';
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
                      Text(
                        'This week',
                        style: textTheme.labelLarge?.copyWith(
                          color: textPrimaryColor(context),
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
    if (workouts == 0) {
      return Material(type: MaterialType.transparency, child: summaryLink);
    }

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summaryLink,
          const SizedBox(height: AppSpacing.md),
          Semantics(
            label: 'Completed sets by day. Today is marked with a dot.',
            // Seven 48dp targets fit a 390dp phone without gaps between them;
            // the bars are inset inside their targets instead. Only narrower
            // screens scroll.
            child: ReadableTableViewport(
              minimumWidth: 7 * 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < 7; index++)
                    Expanded(
                      child: Semantics(
                        label:
                            '${names[index]}: ${dailyWorkouts[index]} workouts, '
                            '${dailySets[index]} sets${index == todayIndex ? ', today' : ''}',
                        button:
                            latestByDay[index] != null &&
                            onOpenLastWorkout != null,
                        child: Tooltip(
                          message:
                              '${names[index]} · ${dailyWorkouts[index]} workouts · ${dailySets[index]} sets',
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
                                share:
                                    maxSets == 0
                                        ? 0
                                        : dailySets[index] / maxSets,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
class _DayColumn extends StatelessWidget {
  final String letter;
  final bool trained;
  final bool today;
  final double share;

  const _DayColumn({
    required this.letter,
    required this.trained,
    required this.today,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: trained ? 14 + 38 * share : 5),
                duration:
                    reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder:
                    (context, height, _) => Container(
                      width: double.infinity,
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
          const SizedBox(height: AppSpacing.sm),
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
      ),
    );
  }
}
