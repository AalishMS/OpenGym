import 'package:flutter/material.dart';

import '../../models/exercise.dart';
import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/statistics_format.dart';

bool _isPrMarker(String? note) {
  final normalized = note?.trim().toLowerCase().replaceAll(
    RegExp(r'[.!]+$'),
    '',
  );
  return normalized == 'pr' ||
      normalized == 'new pr' ||
      normalized == 'pr attempt';
}

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
        _SessionReadout(
          items: [
            _SummaryData(
              label: 'Exercises',
              value: session.exercises.length.toString(),
            ),
            _SummaryData(
              label: 'Performed sets',
              value: statistics.totalSets.toString(),
            ),
            _SummaryData(
              label: 'Duration',
              value:
                  session.durationSeconds == null
                      ? 'Not recorded'
                      : formatStatisticsDuration(session.durationSeconds!),
            ),
            _SummaryData(
              label: 'Volume load',
              value: formatVolumeLoad(statistics.volumeLoad, weightUnit),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryData {
  final String label;
  final String value;

  const _SummaryData({required this.label, required this.value});
}

class _SessionReadout extends StatelessWidget {
  final List<_SummaryData> items;

  const _SessionReadout({required this.items});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('workout-details-readout'),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.card,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = constraints.maxWidth >= 560 ? 4 : 2;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var start = 0; start < items.length; start += columnCount)
                  _SummaryRow(
                    items: items.sublist(
                      start,
                      (start + columnCount).clamp(0, items.length),
                    ),
                    columnCount: columnCount,
                    showTopRule: start > 0,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<_SummaryData> items;
  final int columnCount;
  final bool showTopRule;

  const _SummaryRow({
    required this.items,
    required this.columnCount,
    required this.showTopRule,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              showTopRule
                  ? Border(top: BorderSide(color: borderColor(context)))
                  : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in items.indexed)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border:
                        entry.$1 == 0
                            ? null
                            : Border(
                              left: BorderSide(color: borderColor(context)),
                            ),
                  ),
                  child: _SummaryItem(data: entry.$2),
                ),
              ),
            for (var index = items.length; index < columnCount; index++)
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final _SummaryData data;

  const _SummaryItem({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.value,
            style: AppTypography.trainingData(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimaryColor(context),
              height: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ],
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
                isPrAttempt: _isPrMarker(entry.$2.note),
              ),
              if ((entry.$2.note?.trim().isNotEmpty ?? false) &&
                  !_isPrMarker(entry.$2.note))
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
  final bool isPrAttempt;

  const _SetValues({
    required this.index,
    required this.weight,
    required this.reps,
    required this.rpe,
    required this.isPrAttempt,
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
        Expanded(
          flex: 4,
          child: Row(
            children: [
              Flexible(child: Text(formatWeight(weight), style: style)),
              if (isPrAttempt) ...[
                const SizedBox(width: AppSpacing.xs),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: accentColor(context)),
                    borderRadius: AppRadius.badge,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      'PR',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accentColor(context),
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(flex: 3, child: Text('$reps', style: style)),
        Expanded(flex: 2, child: Text(rpe?.toString() ?? '—', style: style)),
      ],
    );
  }
}
