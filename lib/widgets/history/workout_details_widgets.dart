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

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

String _longDate(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return '${weekdays[date.weekday - 1]}, ${formatStatisticsDate(date)}';
}

/// The top of Workout details: when and what, then a readout of the session.
class WorkoutDetailsSummary extends StatelessWidget {
  final SessionStatistics statistics;
  final String weightUnit;

  /// How many exercises set a personal record in this workout.
  final int recordCount;

  const WorkoutDetailsSummary({
    required this.statistics,
    required this.weightUnit,
    this.recordCount = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final session = statistics.session;
    final duration = knownDurationSeconds(session.durationSeconds);
    final secondary = textSecondaryColor(context);
    final accent = accentColor(context);
    final meta = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _longDate(session.date),
          style: meta?.copyWith(color: secondary, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          header: true,
          child: Text(
            session.planName,
            style: Theme.of(context).textTheme.displaySmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          children: [
            _MetaLabel(
              icon: LucideIcons.layers,
              text: workoutContext(session),
              color: secondary,
            ),
            if (recordCount > 0)
              _MetaLabel(
                icon: LucideIcons.trophy,
                text:
                    recordCount == 1
                        ? '1 personal record'
                        : '$recordCount personal records',
                color: accent,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        DecoratedBox(
          key: const ValueKey('workout-details-readout'),
          decoration: BoxDecoration(
            color: surfaceColor(context),
            border: Border.all(color: borderColor(context)),
            borderRadius: AppRadius.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (statistics.totalSets > 0)
                _RuledRow(
                  children: [
                    _ReadoutFigure(
                      label: 'Volume load',
                      value: formatVolumeLoad(
                        statistics.volumeLoad,
                        weightUnit,
                      ),
                      prominent: true,
                    ),
                    if (duration != null)
                      _ReadoutFigure(
                        label: 'Duration',
                        value: formatStatisticsDuration(duration),
                        prominent: true,
                      ),
                  ],
                )
              else
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.circleDashed,
                        size: 18,
                        color: secondary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          duration == null
                              ? 'No sets logged in this workout'
                              : 'No sets logged in '
                                  '${formatStatisticsDuration(duration)}',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: secondary),
                        ),
                      ),
                    ],
                  ),
                ),
              Divider(height: 1, thickness: 1, color: borderColor(context)),
              _RuledRow(
                children: [
                  _ReadoutFigure(
                    label: 'Exercises',
                    value: '${session.exercises.length}',
                  ),
                  _ReadoutFigure(
                    label: 'Sets',
                    value: '${statistics.totalSets}',
                  ),
                  _ReadoutFigure(
                    label: 'Reps',
                    value: formatAnalyticsNumber(
                      statistics.totalReps.toDouble(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MetaLabel({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
      Flexible(
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ),
    ],
  );
}

/// Equal columns separated by square vertical hairlines.
class _RuledRow extends StatelessWidget {
  final List<Widget> children;

  const _RuledRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: borderColor(context),
              ),
            Expanded(child: child),
          ],
        ],
      ),
    );
  }
}

class _ReadoutFigure extends StatelessWidget {
  final String label;
  final String value;
  final bool prominent;

  const _ReadoutFigure({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: prominent ? AppSpacing.lg : AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: AppTypography.figures(
                fontSize: prominent ? 26 : 17,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: textPrimaryColor(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// The heading over the exercise cards.
class WorkoutDetailsSectionHeader extends StatelessWidget {
  final String title;

  const WorkoutDetailsSectionHeader({required this.title, super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
  );
}

/// A saved exercise: a numbered card holding its totals, notes and set log.
class WorkoutExerciseDetails extends StatelessWidget {
  final Exercise exercise;
  final String weightUnit;
  final int? exerciseNumber;

  /// Whether this exercise set a personal record in the workout.
  final bool isRecord;

  const WorkoutExerciseDetails({
    required this.exercise,
    required this.weightUnit,
    this.exerciseNumber,
    this.isRecord = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final note = exercise.note?.trim();
    final performed = exercise.sets.where((set) => set.reps > 0).toList();
    final totalReps = performed.fold<int>(0, (sum, set) => sum + set.reps);
    final volume = performed.fold<double>(
      0,
      (sum, set) => sum + set.weight * set.reps,
    );
    final secondary = textSecondaryColor(context);
    final gutter = _savedSetNumberWidth(context);
    final summary =
        exercise.sets.isEmpty
            ? null
            : performed.isEmpty
            ? 'Not performed'
            : '${_plural(performed.length, 'set')} · '
                '${_plural(totalReps, 'rep')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor(context),
          border: Border.all(color: borderColor(context)),
          borderRadius: AppRadius.card,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Volume sits beside the name when there is room, and
                  // joins the summary line under it when there isn't.
                  final volumeBeside =
                      volume > 0 &&
                      constraints.maxWidth >= 300 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.3;
                  final volumeInline = volume > 0 && !volumeBeside;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: gutter,
                        child:
                            exerciseNumber == null
                                ? null
                                : ExcludeSemantics(
                                  child: Text(
                                    '$exerciseNumber'.padLeft(2, '0'),
                                    textAlign: TextAlign.center,
                                    style: AppTypography.figures(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      height: 1.75,
                                      color: accentColor(context),
                                    ),
                                  ),
                                ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              label:
                                  exerciseNumber == null
                                      ? null
                                      : 'Exercise $exerciseNumber',
                              child: Text(
                                exercise.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (summary != null ||
                                isRecord ||
                                volumeInline) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              Wrap(
                                spacing: AppSpacing.md,
                                runSpacing: AppSpacing.xxs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (summary != null)
                                    Text(
                                      summary,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  if (isRecord)
                                    _MetaLabel(
                                      icon: LucideIcons.trophy,
                                      text: 'Personal record',
                                      color: accentColor(context),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (volumeBeside) ...[
                        const SizedBox(width: AppSpacing.md),
                        Semantics(
                          label:
                              'Volume load: ${formatVolumeLoad(volume, weightUnit)}',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatVolumeLoad(volume, weightUnit),
                                style: AppTypography.figures(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.5,
                                  color: textPrimaryColor(context),
                                ),
                              ),
                              Text(
                                'Volume',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              if (note != null && note.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    left: gutter + AppSpacing.sm,
                    top: AppSpacing.md,
                  ),
                  child: _WorkoutNote(
                    note: note,
                    label: 'Exercise note',
                    rule: accentColor(context),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              if (exercise.sets.isEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    left: gutter + AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    'No sets recorded',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: secondary),
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
                      for (final (index, set) in exercise.sets.indexed)
                        Container(
                          key: ValueKey('saved-set-row-$index'),
                          // Ruled rows: a square hairline over each set, so
                          // the header and every set are separated by one rule.
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: borderColor(context)),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SetValues(
                                index: index,
                                weightUnit: weightUnit,
                                weight: displayWeight(set.weight, weightUnit),
                                reps: set.reps,
                                rpe: set.rpe,
                                isPrAttempt: _isPrMarker(set.note),
                              ),
                              if ((set.note?.trim().isNotEmpty ?? false) &&
                                  !_isPrMarker(set.note))
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: gutter + AppSpacing.sm,
                                    top: AppSpacing.xxs,
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: _WorkoutNote(
                                    note: set.note!.trim(),
                                    label: 'Set ${index + 1} note',
                                    rule: borderColor(context),
                                  ),
                                ),
                            ],
                          ),
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

/// A note set off by a single leading rule, so it reads as an aside.
class _WorkoutNote extends StatelessWidget {
  final String note;
  final String label;
  final Color rule;

  const _WorkoutNote({
    required this.note,
    required this.label,
    required this.rule,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: rule, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        child: Text(
          note,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ),
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
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
    // A set saved at zero reps was planned but not lifted: keep it on the
    // record, in the secondary ink, so it doesn't read like a performed set.
    final skipped = reps <= 0;
    final quiet = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: textSecondaryColor(context),
    );
    return Semantics(
      container: true,
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
          muted: skipped,
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
        ReadOnlyValue(
          '$reps',
          muted: skipped,
          semanticsLabel: 'Set ${index + 1} reps',
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
    );
  }
}
