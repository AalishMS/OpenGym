import 'dart:math' as math;

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
import '../../utils/workout_context.dart';
import '../read_only_value.dart';
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
    final duration = knownDurationSeconds(session.durationSeconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          session.planName,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Icon(
              LucideIcons.calendarDays,
              size: 15,
              color: textSecondaryColor(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                formatStatisticsDate(session.date),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          workoutContext(session),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        _SessionReadout(
          items: [
            _SummaryData(
              label: 'Volume load',
              value: formatVolumeLoad(statistics.volumeLoad, weightUnit),
              icon: LucideIcons.weight,
            ),
            if (duration != null)
              _SummaryData(
                label: 'Duration',
                value: formatStatisticsDuration(duration),
                icon: LucideIcons.timer,
              ),
            _SummaryData(
              label: 'Exercises',
              value: session.exercises.length.toString(),
              icon: LucideIcons.dumbbell,
            ),
            _SummaryData(
              label: 'Performed sets',
              value: statistics.totalSets.toString(),
              icon: LucideIcons.layers,
            ),
          ],
        ),
        if (statistics.totalSets == 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'No performed sets in this workout.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _SummaryData {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryData({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _SessionReadout extends StatelessWidget {
  final List<_SummaryData> items;

  const _SessionReadout({required this.items});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('workout-details-readout'),
      color: surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final columns =
                constraints.maxWidth >= 560 * scale
                    ? items.length
                    : constraints.maxWidth < 240 * scale
                    ? 1
                    : 2;
            final width =
                (constraints.maxWidth - (columns - 1) * AppSpacing.lg) /
                columns;
            return Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              children: [
                for (final data in items)
                  SizedBox(width: width, child: _SummaryItem(data: data)),
              ],
            );
          },
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(data.icon, size: 13, color: textSecondaryColor(context)),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                data.label,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          data.value,
          style: AppTypography.figures(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: textPrimaryColor(context),
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// A bounded exercise record with a numbered heading and read-only set table.
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Material(
        color: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: borderColor(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                label:
                    exerciseNumber == null ? null : 'Exercise $exerciseNumber',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (exerciseNumber != null) ...[
                      ExcludeSemantics(
                        child: Text(
                          exerciseNumber.toString().padLeft(2, '0'),
                          style: AppTypography.figures(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: accentColor(context),
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: Text(
                        exercise.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${performed.length} performed set${performed.length == 1 ? '' : 's'} · $totalReps reps',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
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
                        Container(
                          key: ValueKey('saved-set-row-${entry.$1}'),
                          // Ruled rows: a square hairline over each set, so the
                          // header and every set are separated by one rule.
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: borderColor(context)),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SetValues(
                                index: entry.$1,
                                weightUnit: weightUnit,
                                weight: displayWeight(
                                  entry.$2.weight,
                                  weightUnit,
                                ),
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
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          LucideIcons.messageSquare,
          size: 13,
          color: textSecondaryColor(context),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(note, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
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
  final style = ReadOnlyValue.style(context);
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

  @override
  Widget build(BuildContext context) {
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
          ReadOnlyValue(
            formatWeight(weight),
            semanticsLabel: 'Set ${index + 1} weight',
            semanticsValue:
                '${formatWeight(weight)} ${weightUnit == 'lbs' ? 'pounds' : 'kilograms'}${isPrAttempt ? ', Personal record' : ''}',
            trailing:
                isPrAttempt
                    ? Container(
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
                    )
                    : null,
          ),
          ReadOnlyValue('$reps', semanticsLabel: 'Set ${index + 1} reps'),
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
