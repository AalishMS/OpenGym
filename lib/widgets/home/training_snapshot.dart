import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// A compact readout of completed training, with the latest plan as its anchor.
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
    final completed = sessions.where((session) => session.isCompleted);
    final thisWeek =
        completed.where((session) {
          final day = calendarDaysBetween(weekStart, session.date);
          return day >= 0 && day < 7;
        }).toList();
    final setCount = thisWeek.fold<int>(
      0,
      (total, session) =>
          total +
          session.exercises.fold<int>(
            0,
            (sum, exercise) =>
                sum + exercise.sets.where((set) => set.reps > 0).length,
          ),
    );
    WorkoutSession? latest;
    for (final session in completed) {
      if (latest == null || session.date.isAfter(latest.date)) latest = session;
    }

    final textTheme = Theme.of(context).textTheme;
    final primary = textPrimaryColor(context);
    final secondary = textSecondaryColor(context);

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.activity, size: 14, color: accentColor(context)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This week',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _SnapshotMetric(
                  value: thisWeek.length,
                  singular: 'workout',
                  plural: 'workouts',
                  onTap: onOpenWeeklyTraining,
                ),
              ),
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                color: borderColor(context),
              ),
              Expanded(
                child: _SnapshotMetric(
                  value: setCount,
                  singular: 'set',
                  plural: 'sets',
                  onTap: onOpenWeeklyTraining,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Divider(height: 1, thickness: 1, color: borderColor(context)),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: latest != null && onOpenLastWorkout != null,
            label:
                latest == null
                    ? 'Last workout: no workouts logged yet'
                    : 'Last workout: ${titleCase(latest.planName)}, ${formatDaysAgo(latest.date, now: today)}',
            child: InkWell(
              onTap:
                  latest == null || onOpenLastWorkout == null
                      ? null
                      : () => onOpenLastWorkout!(latest!),
              borderRadius: AppRadius.control,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              latest == null
                                  ? borderColor(context)
                                  : _planColorFor(latest, context),
                          borderRadius: AppRadius.micro,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last workout',
                                style: textTheme.labelSmall?.copyWith(
                                  color: secondary,
                                ),
                              ),
                              Text(
                                latest == null
                                    ? 'No workouts logged yet'
                                    : '${titleCase(latest.planName)} · ${formatDaysAgo(latest.date, now: today)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelMedium?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (latest != null && onOpenLastWorkout != null)
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: secondary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _planColorFor(WorkoutSession session, BuildContext context) {
    final name = session.planName.toLowerCase();
    for (final plan in plans) {
      final matches =
          session.planId != null && plan.id != null
              ? session.planId == plan.id
              : plan.name.toLowerCase() == name;
      if (matches) return planColorOf(plan.planColor, context);
    }
    return planColorOf(null, context);
  }
}

class _SnapshotMetric extends StatelessWidget {
  final int value;
  final String singular;
  final String plural;
  final VoidCallback? onTap;

  const _SnapshotMetric({
    required this.value,
    required this.singular,
    required this.plural,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = value == 1 ? singular : plural;
    return Semantics(
      button: onTap != null,
      label: '$value $label this week',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Text(
                    '$value',
                    maxLines: 1,
                    style: AppTypography.trainingData(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: textSecondaryColor(context),
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      LucideIcons.arrowUpRight,
                      size: 12,
                      color: textSecondaryColor(context),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
