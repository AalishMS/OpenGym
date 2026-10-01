import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/workout_plan.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// Completed sets by calendar day, with an outline identifying today.
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
    final todayColor = textPrimaryColor(context);
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

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: onOpenWeeklyTraining != null,
            label: 'View weekly training statistics',
            child: InkWell(
              key: const ValueKey('weekly-training-link'),
              onTap: onOpenWeeklyTraining,
              borderRadius: AppRadius.control,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Text(
                        'This week',
                        style: textTheme.bodyMedium?.copyWith(color: secondary),
                      ),
                      Text(
                        '$workouts ${workouts == 1 ? 'workout' : 'workouts'} · '
                        '$sets ${sets == 1 ? 'set' : 'sets'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: textPrimaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            label: 'Completed sets by day. The outlined day is today.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < 7; index++) ...[
                  if (index > 0) const SizedBox(width: AppSpacing.sm),
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
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 52,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      height:
                                          dailyWorkouts[index] > 0
                                              ? 14 +
                                                  (maxSets == 0
                                                      ? 0
                                                      : 38 *
                                                          dailySets[index] /
                                                          maxSets)
                                              : index == todayIndex
                                              ? 40
                                              : 5,
                                      decoration: BoxDecoration(
                                        color:
                                            index == todayIndex
                                                ? backgroundColor(context)
                                                : dailyWorkouts[index] > 0
                                                ? accentFillColor(context)
                                                : borderColor(context),
                                        borderRadius: AppRadius.control,
                                      ),
                                      child:
                                          index == todayIndex
                                              ? CustomPaint(
                                                painter: _TodayOutline(
                                                  color: todayColor,
                                                ),
                                                // Leave a neutral gap between the outline and
                                                // the bar so every accent keeps today legible.
                                                child:
                                                    dailyWorkouts[index] > 0
                                                        ? Padding(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                3,
                                                              ),
                                                          child: DecoratedBox(
                                                            decoration:
                                                                BoxDecoration(
                                                                  color:
                                                                      accentFillColor(
                                                                        context,
                                                                      ),
                                                                  borderRadius:
                                                                      AppRadius
                                                                          .micro,
                                                                ),
                                                          ),
                                                        )
                                                        : null,
                                              )
                                              : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  letters[index],
                                  style: textTheme.labelSmall?.copyWith(
                                    color:
                                        index == todayIndex
                                            ? todayColor
                                            : secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayOutline extends CustomPainter {
  final Color color;
  const _TodayOutline({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    final rect = AppRadius.control.toRRect(Offset.zero & size).deflate(0.75);
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 7) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 4, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TodayOutline oldDelegate) => oldDelegate.color != color;
}
