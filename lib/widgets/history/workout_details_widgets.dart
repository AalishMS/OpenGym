import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/exercise.dart';
import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/statistics_format.dart';
import '../readable_table_viewport.dart';

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
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${formatStatisticsDate(session.date)} · Week ${session.weekNumber}',
          style: Theme.of(context).textTheme.bodySmall,
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
    return Container(
      key: const ValueKey('workout-details-readout'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
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
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: textPrimaryColor(context),
              fontFeatures: const [FontFeature.tabularFigures()],
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

/// A saved exercise in the same continuous log layout as an active workout.
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: exerciseNumber == null ? null : 'Exercise $exerciseNumber',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                exercise.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${performed.length} performed set${performed.length == 1 ? '' : 's'} · $totalReps reps',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (note != null && note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _WorkoutNote(note: note, label: 'Exercise note'),
            ),
          if (exercise.sets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No sets recorded',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ReadableTableViewport(
              minimumWidth: _minimumSavedTableWidth(
                context,
                exercise,
                weightUnit,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _SetHeader(weightUnit: weightUnit),
                  ),
                  for (final entry in exercise.sets.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SetValues(
                            index: entry.$1,
                            weightUnit: weightUnit,
                            weight: displayWeight(entry.$2.weight, weightUnit),
                            reps: entry.$2.reps,
                            rpe: entry.$2.rpe,
                            isPrAttempt: _isPrMarker(entry.$2.note),
                          ),
                          if ((entry.$2.note?.trim().isNotEmpty ?? false) &&
                              !_isPrMarker(entry.$2.note))
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 40,
                                top: AppSpacing.xs,
                                bottom: AppSpacing.xs,
                              ),
                              child: _WorkoutNote(
                                note: entry.$2.note!.trim(),
                                label: 'Set ${entry.$1 + 1} note',
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (performed.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
    );
  }
}

class _WorkoutNote extends StatelessWidget {
  final String note;
  final String label;

  const _WorkoutNote({required this.note, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Text(note, style: Theme.of(context).textTheme.bodySmall),
  );
}

// Saved logs omit the live screen's Previous column. The other columns retain
// its fixed set-number gutter, spacing, and weight/reps/RPE proportions.
double _savedSetNumberWidth(BuildContext context) => [
  32.0,
  readableTextWidth(context, 'Set', Theme.of(context).textTheme.labelMedium!),
  readableTextWidth(
    context,
    '999',
    Theme.of(context).textTheme.labelLarge!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  ),
].reduce(math.max);

double _minimumSavedTableWidth(
  BuildContext context,
  Exercise exercise,
  String unit,
) {
  final style = Theme.of(context).textTheme.titleLarge!.copyWith(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  final weightWidth = exercise.sets.fold<double>(
    48,
    (width, set) => math.max(
      width,
      readableTextWidth(
            context,
            formatWeight(displayWeight(set.weight, unit)),
            style,
          ) +
          16 +
          (_isPrMarker(set.note)
              ? readableTextWidth(
                    context,
                    'PR',
                    Theme.of(context).textTheme.labelSmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ) +
                  12
              : 0),
    ),
  );
  final repsWidth = exercise.sets.fold<double>(
    48,
    (width, set) =>
        math.max(width, readableTextWidth(context, '${set.reps}', style) + 16),
  );
  final rpeWidth = math.max(
    48.0,
    readableTextWidth(
          context,
          'RPE',
          Theme.of(context).textTheme.labelMedium!,
        ) +
        8,
  );
  final flexibleUnit = [
    weightWidth / 5,
    repsWidth / 4,
    rpeWidth / 4,
  ].reduce(math.max);
  return _savedSetNumberWidth(context) + 3 * AppSpacing.sm + flexibleUnit * 13;
}

Widget _setColumns(BuildContext context, List<Widget> cells) => Row(
  children: [
    SizedBox(width: _savedSetNumberWidth(context), child: cells[0]),
    const SizedBox(width: AppSpacing.sm),
    Expanded(flex: 5, child: cells[1]),
    const SizedBox(width: AppSpacing.sm),
    Expanded(flex: 4, child: cells[2]),
    const SizedBox(width: AppSpacing.sm),
    Expanded(flex: 4, child: cells[3]),
  ],
);

class _SetHeader extends StatelessWidget {
  final String weightUnit;

  const _SetHeader({required this.weightUnit});

  @override
  Widget build(BuildContext context) => _setColumns(context, [
    for (final label in ['Set', 'Weight ($weightUnit)', 'Reps', 'RPE'])
      Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w400,
          color: textSecondaryColor(context),
        ),
      ),
  ]);
}

class _SetValues extends StatelessWidget {
  final int index;
  final String weightUnit;
  final double weight;
  final int reps;
  final int? rpe;
  final bool isPrAttempt;

  const _SetValues({
    required this.index,
    required this.weightUnit,
    required this.weight,
    required this.reps,
    required this.rpe,
    required this.isPrAttempt,
  });

  Widget _value(
    BuildContext context,
    Widget child, {
    required String label,
    required String value,
  }) => Semantics(
    label: label,
    value: value,
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.all(AppSpacing.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: surfaceColor(context),
        borderRadius: AppRadius.field,
      ),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: textPrimaryColor(context),
    );
    final quiet = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w400,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: textSecondaryColor(context),
    );
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: _setColumns(context, [
          ExcludeSemantics(
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: quiet,
            ),
          ),
          _value(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatWeight(weight), style: style),
                if (isPrAttempt) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Semantics(
                    label: 'Personal record',
                    excludeSemantics: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: accentFillColor(context),
                        borderRadius: AppRadius.badge,
                      ),
                      child: Text(
                        'PR',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: onAccentColor(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            label: 'Set ${index + 1} weight',
            value:
                '${formatWeight(weight)} ${weightUnit == 'lbs' ? 'pounds' : 'kilograms'}${isPrAttempt ? ', Personal record' : ''}',
          ),
          _value(
            context,
            Text('$reps', style: style),
            label: 'Set ${index + 1} reps',
            value: '$reps',
          ),
          Semantics(
            label: 'Set ${index + 1} RPE',
            value: rpe?.toString() ?? 'Not recorded',
            excludeSemantics: true,
            child: Text(
              rpe?.toString() ?? '—',
              textAlign: TextAlign.center,
              style: quiet,
            ),
          ),
        ]),
      ),
    );
  }
}
