import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import 'statistics_controls.dart';

/// The selected block at a glance: what was done, how it compares with the
/// block before it, how each week went, and which lifts got stronger.
class BlockOverview extends StatelessWidget {
  /// Blocks with at least one workout, in block order.
  final List<BlockStatistics> blocks;
  final BlockStatistics selected;
  final String? currentBlockId;
  final ValueChanged<String> onSelect;
  final String weightUnit;

  const BlockOverview({
    super.key,
    required this.blocks,
    required this.selected,
    required this.currentBlockId,
    required this.onSelect,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = blocks.indexOf(selected);
    final previous = index > 0 ? blocks[index - 1] : null;
    final latest = selected.latestWeek;
    final isCurrent = selected.block.id == currentBlockId;
    final dates =
        selected.firstDate == null
            ? null
            : formatDateSpan(selected.firstDate!, selected.lastDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blocks.length > 1) ...[
          // Blocks run oldest to newest, so the current one starts in view.
          ScrollingPills<String>(
            keyPrefix: 'block-chip',
            startAtEnd: true,
            values: [for (final stats in blocks) stats.block.id],
            selected: selected.block.id,
            labelFor: (id) {
              final name =
                  blocks.firstWhere((stats) => stats.block.id == id).block.name;
              return id == currentBlockId ? '$name · Now' : name;
            },
            onSelected: onSelect,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Semantics(
          header: true,
          child: Text(
            selected.block.name,
            key: const ValueKey('block-overview-name'),
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            if (latest != null)
              isCurrent
                  ? 'Week ${latest.number} of ${selected.plannedWeeks}'
                  : '${selected.trainedWeeks} '
                      '${selected.trainedWeeks == 1 ? 'week' : 'weeks'}',
            if (dates != null) dates,
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _BlockFigures(block: selected, previous: previous, unit: weightUnit),
        if (previous != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Arrows compare an average week with ${previous.block.name}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ],
        const _Rule(),
        Text('Sets each week', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        _WeekBars(block: selected),
        const _Rule(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text('Strength gains', style: theme.textTheme.titleSmall),
            ),
            Text(
              'Estimated 1RM',
              style: theme.textTheme.bodySmall?.copyWith(
                color: textSecondaryColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _Gains(gains: selected.gains, unit: weightUnit),
      ],
    );
  }
}

/// A hairline between the overview's sections, so they can sit close
/// together without running into each other.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Container(height: 1, color: borderColor(context)),
  );
}

class _BlockFigures extends StatelessWidget {
  final BlockStatistics block;
  final BlockStatistics? previous;
  final String unit;

  const _BlockFigures({
    required this.block,
    required this.previous,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    double? change(BlockMeasure measure) {
      final before = previous?.perWeek(measure);
      if (before == null || before == 0) return null;
      return (block.perWeek(measure) - before) / before * 100;
    }

    final workoutRate = formatAnalyticsNumber(
      block.perWeek(BlockMeasure.workouts),
      decimals: 1,
    ).replaceFirst('.0', '');
    final setRate = formatAnalyticsNumber(block.perWeek(BlockMeasure.sets));
    final volumeRate = formatVolumeLoad(
      block.perWeek(BlockMeasure.volume),
      unit,
    );
    // Without an earlier block to compare with, the weekly rate fills in.
    final tiles = [
      _Tile(
        label: 'Workouts',
        value: '${block.workouts}',
        change: change(BlockMeasure.workouts),
        note: '$workoutRate/wk',
        spokenNote: 'about $workoutRate a week',
      ),
      _Tile(
        label: 'Sets',
        value: formatAnalyticsNumber(block.sets.toDouble()),
        change: change(BlockMeasure.sets),
        note: '$setRate/wk',
        spokenNote: 'about $setRate a week',
      ),
      _Tile(
        label: 'Volume',
        value: formatVolumeLoad(block.volumeLoad, unit),
        change: change(BlockMeasure.volume),
        note: '$volumeRate/wk',
        spokenNote: 'about $volumeRate a week',
      ),
      _Tile(
        label: 'Records',
        value: '${block.records}',
        note: block.records == 1 ? 'new best' : 'new bests',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // One strip of four reads at a glance; it only splits into two rows
        // when the figures would get too cramped to read.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final strip = constraints.maxWidth / 4 >= 72 * scale && scale <= 1.3;
        if (!strip) {
          final width = (constraints.maxWidth - AppSpacing.lg) / 2;
          return Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              for (final tile in tiles) SizedBox(width: width, child: tile),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, tile) in tiles.indexed) ...[
                if (index > 0) ...[
                  Container(width: 1, color: borderColor(context)),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(child: tile),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final double? change;
  final String? note;

  /// How [note] reads aloud, when its short form doesn't.
  final String? spokenNote;

  const _Tile({
    required this.label,
    required this.value,
    this.change,
    this.note,
    this.spokenNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = textSecondaryColor(context);
    final primary = textPrimaryColor(context);
    final change = this.change;
    final rounded = change?.round();
    final quiet = spokenNote ?? note ?? '';
    final (IconData icon, String text, String spoken) = switch (rounded) {
      null => (LucideIcons.minus, note ?? '', quiet),
      0 => (LucideIcons.minus, 'Same', 'about the same per week'),
      > 0 => (LucideIcons.trendingUp, '$rounded%', '$rounded% more per week'),
      _ => (
        LucideIcons.trendingDown,
        '${-rounded}%',
        '${-rounded}% less per week',
      ),
    };
    return Semantics(
      container: true,
      label: '$label, $value${spoken.isEmpty ? '' : ', $spoken'}',
      child: ExcludeSemantics(
        // No ground: these are read-only figures, and a ground means tappable.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: secondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppTypography.figures(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rounded != null) ...[
                    Icon(icon, size: 13, color: primary),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Text(
                    text,
                    maxLines: 1,
                    style: AppTypography.figures(
                      fontSize: 12,
                      fontWeight:
                          rounded == null ? FontWeight.w400 : FontWeight.w600,
                      color: rounded == null ? secondary : primary,
                    ),
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

/// One column per week of the block. Weeks ahead of the plan show as a
/// short stub, so a block's length reads at a glance. A long run of unused
/// weeks after the latest workout is left out instead: forty empty columns
/// say nothing, and they would push the trained weeks out of view.
class _WeekBars extends StatelessWidget {
  static const double _plotHeight = 56;

  /// Up to this many weeks, the whole planned block is drawn.
  static const int _wholeBlockWeeks = 12;

  final BlockStatistics block;

  const _WeekBars({required this.block});

  List<BlockWeekStatistics> get _visibleWeeks {
    final weeks = block.weeks;
    if (weeks.length <= _wholeBlockWeeks) return weeks;
    final lastTrained = weeks.lastIndexWhere((week) => week.workouts > 0);
    return weeks.sublist(0, math.max(1, lastTrained + 1));
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _visibleWeeks;
    final maximum = math.max(
      1,
      weeks.fold<int>(0, (max, week) => math.max(max, week.sets)),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final slot = 36.0 * math.max(1, scale);
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    Widget column(BlockWeekStatistics week, double barWidth) {
      final latest = week.weekId != null && week.weekId == block.latestWeekId;
      final ink =
          latest ? textPrimaryColor(context) : textSecondaryColor(context);
      final height =
          week.sets == 0
              ? 0.0
              : math.max(4.0, week.sets / maximum * _plotHeight);
      return Semantics(
        label:
            !week.reached
                ? 'Week ${week.number}, not started'
                : 'Week ${week.number}, ${week.workouts} '
                    '${week.workouts == 1 ? 'workout' : 'workouts'}, '
                    '${week.sets} sets',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Text(
                week.sets > 0 ? '${week.sets}' : '',
                style: AppTypography.figures(
                  fontSize: 11,
                  fontWeight: latest ? FontWeight.w700 : FontWeight.w400,
                  color: ink,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              SizedBox(
                height: _plotHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child:
                      week.reached
                          ? Container(
                            key: ValueKey('block-week-bar-${week.number}'),
                            width: barWidth,
                            height: height,
                            decoration: BoxDecoration(
                              color:
                                  latest
                                      ? accentFillColor(context)
                                      : accentDimColor(context),
                              borderRadius: AppRadius.barCap,
                            ),
                          )
                          : Container(
                            width: barWidth,
                            height: AppSpacing.sm,
                            decoration: BoxDecoration(
                              border: Border.all(color: borderColor(context)),
                              borderRadius: AppRadius.barCap,
                            ),
                          ),
                ),
              ),
              Container(height: 1, color: borderColor(context)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'W${week.number}',
                style: labelStyle?.copyWith(
                  color: ink,
                  fontWeight: latest ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Bars widen with their column, so a short block doesn't look sparse.
        double barWidth(double column) => (column * 0.45).clamp(14, 32);
        if (weeks.length * slot <= constraints.maxWidth) {
          final width = barWidth(constraints.maxWidth / weeks.length);
          return Row(
            children: [
              for (final week in weeks) Expanded(child: column(week, width)),
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              for (final week in weeks)
                SizedBox(width: slot, child: column(week, barWidth(slot))),
            ],
          ),
        );
      },
    );
  }
}

class _Gains extends StatelessWidget {
  final List<LiftGain> gains;
  final String unit;

  const _Gains({required this.gains, required this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (gains.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'Log a lift in two workouts of this block to see it improve.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: textSecondaryColor(context),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final gain in gains.take(3))
          Semantics(
            container: true,
            label:
                '${gain.exerciseName}, from ${formatAnalyticsWeight(gain.start, unit)} '
                'to ${formatAnalyticsWeight(gain.end, unit)}, '
                'up ${gain.percent.round()}%',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        gain.exerciseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${_bareWeight(gain.start, unit)} → '
                      '${formatAnalyticsWeight(gain.end, unit)}',
                      style: AppTypography.figures(
                        fontSize: 12,
                        color: textSecondaryColor(context),
                      ),
                    ),
                    // A fixed column keeps the percentages lined up.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 52),
                      child: Text(
                        '+${gain.percent.round()}%',
                        textAlign: TextAlign.end,
                        style: AppTypography.figures(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: successColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Compares blocks side by side as an average per trained week, so blocks of
/// different lengths, and one still in progress, stay comparable.
class BlockComparison extends StatelessWidget {
  final List<BlockStatistics> blocks;
  final String selectedId;
  final String? currentBlockId;
  final BlockMeasure measure;
  final ValueChanged<BlockMeasure> onMeasure;
  final ValueChanged<String> onSelect;
  final String weightUnit;

  const BlockComparison({
    super.key,
    required this.blocks,
    required this.selectedId,
    required this.currentBlockId,
    required this.measure,
    required this.onMeasure,
    required this.onSelect,
    required this.weightUnit,
  });

  String _format(double value) => switch (measure) {
    BlockMeasure.sets => '${formatAnalyticsNumber(value)} sets',
    BlockMeasure.volume => formatVolumeLoad(value, weightUnit),
    BlockMeasure.workouts =>
      '${formatAnalyticsNumber(value, decimals: 1)} workouts',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximum = blocks.fold<double>(
      0,
      (max, block) => math.max(max, block.perWeek(measure)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Compare blocks', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Average per week trained',
          style: theme.textTheme.bodySmall?.copyWith(
            color: textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentedPills<BlockMeasure>(
          keyPrefix: 'block-measure',
          values: BlockMeasure.values,
          selected: measure,
          labelFor: (option) => option.label,
          onSelected: onMeasure,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final stats in blocks)
          _ComparisonRow(
            key: ValueKey('block-compare-${stats.block.id}'),
            name: stats.block.name,
            detail:
                '${stats.trainedWeeks} ${stats.trainedWeeks == 1 ? 'week' : 'weeks'}'
                '${stats.block.id == currentBlockId ? ' · In progress' : ''}',
            value: _format(stats.perWeek(measure)),
            fraction: maximum == 0 ? 0 : stats.perWeek(measure) / maximum,
            selected: stats.block.id == selectedId,
            onTap: () => onSelect(stats.block.id),
          ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final String name;
  final String detail;
  final String value;
  final double fraction;
  final bool selected;
  final VoidCallback onTap;

  const _ComparisonRow({
    super.key,
    required this.name,
    required this.detail,
    required this.value,
    required this.fraction,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$name, $detail, $value a week',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.control,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight:
                                      selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                ),
                              ),
                              TextSpan(
                                text: '  $detail',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: textSecondaryColor(context),
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        value,
                        style: AppTypography.figures(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: textPrimaryColor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: AppRadius.micro,
                    child: Stack(
                      children: [
                        Container(height: 10, color: backgroundColor(context)),
                        FractionallySizedBox(
                          widthFactor: fraction.clamp(0.02, 1),
                          child: Container(
                            height: 10,
                            color:
                                selected
                                    ? accentFillColor(context)
                                    : accentDimColor(context),
                          ),
                        ),
                      ],
                    ),
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

/// The start of a range drops its unit; the end carries it.
String _bareWeight(double kilograms, String unit) =>
    formatAnalyticsWeight(kilograms, unit).replaceFirst(' $unit', '');
