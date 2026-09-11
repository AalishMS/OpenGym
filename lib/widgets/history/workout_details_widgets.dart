import 'package:flutter/material.dart';

import '../../models/exercise.dart';
import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/statistics_format.dart';

class WorkoutDetailsSummary extends StatelessWidget {
  final SessionStatistics statistics;
  final String weightUnit;

  const WorkoutDetailsSummary({
    required this.statistics,
    required this.weightUnit,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final session = statistics.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          session.planName,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${formatStatisticsDate(session.date)} · Week ${session.weekNumber}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: textSecondaryColor(context)),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _SummaryItem(
              label: 'Exercises',
              value: session.exercises.length.toString(),
            ),
            _SummaryItem(
              label: 'Performed sets',
              value: statistics.totalSets.toString(),
            ),
            _SummaryItem(
              label: 'Duration',
              value:
                  session.durationSeconds == null
                      ? 'Not recorded'
                      : formatStatisticsDuration(session.durationSeconds!),
            ),
            _SummaryItem(
              label: 'Volume load',
              value: formatVolumeLoad(statistics.volumeLoad, weightUnit),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor(context),
          border: Border.all(color: borderColor(context)),
          borderRadius: AppRadius.card,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutExerciseDetails extends StatelessWidget {
  final Exercise exercise;
  final String weightUnit;

  const WorkoutExerciseDetails({
    required this.exercise,
    required this.weightUnit,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final note = exercise.note?.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exercise.name, style: Theme.of(context).textTheme.titleMedium),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(note, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.lg),
            _SetHeader(weightUnit: weightUnit),
            const SizedBox(height: AppSpacing.sm),
            for (final entry in exercise.sets.indexed) ...[
              _SetValues(
                index: entry.$1,
                weight: displayWeight(entry.$2.weight, weightUnit),
                reps: entry.$2.reps,
                rpe: entry.$2.rpe,
              ),
              if (entry.$2.note?.trim().isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xs,
                    bottom: AppSpacing.sm,
                    left: AppSpacing.xxl,
                  ),
                  child: Text(
                    entry.$2.note!.trim(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetHeader extends StatelessWidget {
  final String weightUnit;

  const _SetHeader({required this.weightUnit});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      children: [
        Expanded(flex: 2, child: Text('Set', style: style)),
        Expanded(flex: 4, child: Text('Weight ($weightUnit)', style: style)),
        Expanded(flex: 3, child: Text('Reps', style: style)),
        Expanded(flex: 2, child: Text('RPE', style: style)),
      ],
    );
  }
}

class _SetValues extends StatelessWidget {
  final int index;
  final double weight;
  final int reps;
  final int? rpe;

  const _SetValues({
    required this.index,
    required this.weight,
    required this.reps,
    required this.rpe,
  });

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.trainingData(
      fontSize: 12,
      color: textPrimaryColor(context),
    );
    return Row(
      children: [
        Expanded(flex: 2, child: Text('${index + 1}', style: style)),
        Expanded(flex: 4, child: Text(formatWeight(weight), style: style)),
        Expanded(flex: 3, child: Text('$reps', style: style)),
        Expanded(flex: 2, child: Text(rpe?.toString() ?? '—', style: style)),
      ],
    );
  }
}
