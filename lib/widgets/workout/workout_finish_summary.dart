import 'package:flutter/material.dart';

import '../../data/exercise_library.dart';
import '../../models/statistics.dart';
import '../../models/workout_session.dart';
import '../../services/statistics_analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';

/// Performed work only: seconds never become reps or weight-based volume.
class WorkoutFinishWork {
  final double volume;
  final int sets;
  final int bodyweightReps;
  final int timedSeconds;

  const WorkoutFinishWork(
    this.volume,
    this.sets,
    this.bodyweightReps,
    this.timedSeconds,
  );

  factory WorkoutFinishWork.fromSession(WorkoutSession session) {
    final stats = const StatisticsAnalyticsService().sessionStatistics(session);
    var bodyweight = 0;
    var seconds = 0;
    for (final exercise in session.exercises) {
      for (final set in exercise.sets.where((set) => set.reps > 0)) {
        if (ExerciseLibrary.isTimed(exercise.name)) {
          seconds += set.reps;
        } else if (set.weight == 0) {
          bodyweight += set.reps;
        }
      }
    }
    return WorkoutFinishWork(
      stats.volumeLoad,
      stats.totalSets,
      bodyweight,
      seconds,
    );
  }

  /// Identity, scope and chronology must all agree before comparing workouts.
  static WorkoutSession? previous(
    WorkoutSession session,
    Iterable<WorkoutSession> history,
  ) {
    if (session.planId == null) return null;
    final candidates =
        history
            .where(
              (row) =>
                  row.isCompleted &&
                  row.deletedAt == null &&
                  row.id != session.id &&
                  row.planId == session.planId &&
                  row.splitId == session.splitId &&
                  row.userId == session.userId &&
                  row.date.isBefore(session.date),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return candidates.firstOrNull;
  }
}

class WorkoutFinishSummary extends StatelessWidget {
  final WorkoutSession session;
  final WorkoutSession? previous;
  final List<RecordEvent> records;
  final String weightUnit;

  const WorkoutFinishSummary({
    super.key,
    required this.session,
    required this.records,
    required this.weightUnit,
    this.previous,
  });

  @override
  Widget build(BuildContext context) {
    final work = WorkoutFinishWork.fromSession(session);
    final before =
        previous == null ? null : WorkoutFinishWork.fromSession(previous!);
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textSecondaryColor(context),
              ),
            ),
            Text(
              value,
              style: AppTypography.figures(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: textPrimaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
    String change(double value) =>
        '${value > 0
            ? '+'
            : value < 0
            ? '-'
            : ''}${formatVolumeLoad(value.abs(), weightUnit)}';
    return AlertDialog(
      title: const Text('Workout logged'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.planName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (session.durationSeconds case final seconds?)
            line(
              'Duration',
              seconds < 60 ? '$seconds s' : formatStatisticsDuration(seconds),
            ),
          if (work.sets == 0)
            const Text('No sets logged')
          else
            line('Sets', '${work.sets}'),
          if (work.volume > 0)
            line('Volume load', formatVolumeLoad(work.volume, weightUnit)),
          if (work.bodyweightReps > 0)
            line('Bodyweight work', formatRepCount(work.bodyweightReps)),
          if (work.timedSeconds > 0)
            line('Timed work', formatHoldTimeSpoken(work.timedSeconds)),
          if (before != null) ...[
            const Divider(),
            Text(
              'Compared with your previous ${session.planName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            line(
              'Sets',
              '${work.sets - before.sets >= 0 ? '+' : ''}${work.sets - before.sets}',
            ),
            if (work.volume > 0 || before.volume > 0)
              line('Volume load', change(work.volume - before.volume)),
            if (work.bodyweightReps > 0 || before.bodyweightReps > 0)
              line(
                'Bodyweight reps',
                '${work.bodyweightReps - before.bodyweightReps >= 0 ? '+' : ''}${work.bodyweightReps - before.bodyweightReps}',
              ),
            if (work.timedSeconds > 0 || before.timedSeconds > 0)
              line(
                'Timed work',
                formatHoldTimeSpoken(work.timedSeconds - before.timedSeconds),
              ),
          ],
          if (records.isNotEmpty) ...[
            const Divider(),
            Text(
              'Personal records',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: accentColor(context)),
            ),
            for (final record in records) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                record.exerciseName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final achievement in record.achievements)
                Text(
                  '${formatRecordTitle(achievement)}: ${formatRecordValue(achievement, weightUnit)}'
                  '${formatRecordPreviousValue(achievement, weightUnit) == null ? '' : ' (previous ${formatRecordPreviousValue(achievement, weightUnit)})'}',
                ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
