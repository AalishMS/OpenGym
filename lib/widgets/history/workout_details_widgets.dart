import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
          '${formatStatisticsDate(session.date)} · Week ${session.weekNumber}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: textSecondaryColor(context)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          session.planName,
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        _SessionReadout(
          items: [
            _SummaryData(
              label: 'Exercises',
              icon: LucideIcons.dumbbell,
              value: session.exercises.length.toString(),
            ),
            _SummaryData(
              label: 'Performed sets',
              icon: LucideIcons.layers,
              value: statistics.totalSets.toString(),
            ),
            _SummaryData(
              label: 'Duration',
              icon: LucideIcons.timer,
              value:
                  session.durationSeconds == null
                      ? 'Not recorded'
                      : formatStatisticsDuration(session.durationSeconds!),
            ),
            _SummaryData(
              label: 'Volume load',
              icon: LucideIcons.weight,
              value: formatVolumeLoad(statistics.volumeLoad, weightUnit),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryData {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryData({
    required this.icon,
    required this.label,
    required this.value,
  });
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
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final columnCount = constraints.maxWidth >= 640 * textScale ? 4 : 2;
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
          Icon(data.icon, size: 18, color: accentColor(context)),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: textPrimaryColor(context),
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
  final int? exerciseNumber;

  const WorkoutExerciseDetails({
    required this.exercise,
    required this.weightUnit,
    this.exerciseNumber,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final note = exercise.note?.trim();
    final performed = exercise.sets.where((set) => set.reps > 0);
    final totalReps = performed.fold<int>(0, (sum, set) => sum + set.reps);
    final volume = performed.fold<double>(
      0,
      (sum, set) => sum + set.weight * set.reps,
    );
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        borderRadius: AppRadius.card,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (exerciseNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: accentFillColor(context),
                        borderRadius: AppRadius.control,
                      ),
                      child: Text(
                        '$exerciseNumber',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: onAccentColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${performed.length} performed set${performed.length == 1 ? '' : 's'} · $totalReps reps',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (note != null && note.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: _WorkoutNote(note: note, label: 'Exercise note'),
              ),
            ],
            Container(
              color: backgroundColor(context),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: _SetHeader(weightUnit: weightUnit),
            ),
            if (exercise.sets.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No sets recorded',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            for (final entry in exercise.sets.indexed)
              Container(
                decoration: BoxDecoration(
                  border:
                      entry.$1 == 0
                          ? null
                          : Border(
                            top: BorderSide(color: borderColor(context)),
                          ),
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: _WorkoutNote(
                          note: entry.$2.note!.trim(),
                          label: 'Set ${entry.$1 + 1} note',
                        ),
                      ),
                  ],
                ),
              ),
            if (performed.length > 1)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: borderColor(context))),
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.weight,
                      size: 16,
                      color: textSecondaryColor(context),
                    ),
                    Text(
                      'Volume load',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      formatVolumeLoad(volume, weightUnit),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutNote extends StatelessWidget {
  final String note;
  final String label;

  const _WorkoutNote({required this.note, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: backgroundColor(context),
          borderRadius: AppRadius.field,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.messageSquare,
              size: 16,
              color: textSecondaryColor(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(note, style: Theme.of(context).textTheme.bodySmall),
            ),
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
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: textPrimaryColor(context),
    );
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: backgroundColor(context),
                borderRadius: AppRadius.badge,
              ),
              child: Text(
                '${index + 1}',
                style: style.copyWith(color: textSecondaryColor(context)),
              ),
            ),
          ),
        ),
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
