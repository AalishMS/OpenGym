import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';

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
          _BlockChips(
            blocks: blocks,
            selectedId: selected.block.id,
            currentBlockId: currentBlockId,
            onSelect: onSelect,
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
        _BlockTiles(block: selected, previous: previous, unit: weightUnit),
        if (previous != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Arrows compare an average week with ${previous.block.name}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text('Sets each week', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        _WeekBars(block: selected),
        const SizedBox(height: AppSpacing.xl),
        Text('Strength gains', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Estimated 1RM, first to latest workout in this block',
          style: theme.textTheme.bodySmall?.copyWith(
            color: textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Gains(gains: selected.gains, unit: weightUnit),
      ],
    );
  }
}

class _BlockChips extends StatelessWidget {
  final List<BlockStatistics> blocks;
  final String selectedId;
  final String? currentBlockId;
  final ValueChanged<String> onSelect;

  const _BlockChips({
    required this.blocks,
    required this.selectedId,
    required this.currentBlockId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // Blocks run oldest to newest, so the current one starts in view.
    reverse: true,
    child: Row(
      children: [
        for (final stats in blocks)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: StatisticsChip(
              key: ValueKey('block-chip-${stats.block.id}'),
              label:
                  stats.block.id == currentBlockId
                      ? '${stats.block.name} · Now'
                      : stats.block.name,
              selected: stats.block.id == selectedId,
              onSelected: () => onSelect(stats.block.id),
            ),
          ),
      ],
    ),
  );
}

/// A single-choice chip on the solved accent ground, shared by every
/// selector on the statistics screen.
class StatisticsChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const StatisticsChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: (_) => onSelected(),
    labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: selected ? onAccentColor(context) : textPrimaryColor(context),
    ),
    side: BorderSide(
      color: selected ? accentFillColor(context) : borderColor(context),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xs,
    ),
  );
}

class _BlockTiles extends StatelessWidget {
  final BlockStatistics block;
  final BlockStatistics? previous;
  final String unit;

  const _BlockTiles({
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

    // Without an earlier block to compare with, the weekly rate fills in.
    final tiles = [
      _Tile(
        label: 'Workouts',
        value: '${block.workouts}',
        change: change(BlockMeasure.workouts),
        note:
            '≈ ${formatAnalyticsNumber(block.perWeek(BlockMeasure.workouts), decimals: 1).replaceFirst('.0', '')} a week',
      ),
      _Tile(
        label: 'Sets',
        value: formatAnalyticsNumber(block.sets.toDouble()),
        change: change(BlockMeasure.sets),
        note:
            '≈ ${formatAnalyticsNumber(block.perWeek(BlockMeasure.sets))} a week',
      ),
      _Tile(
        label: 'Volume',
        value: formatVolumeLoad(block.volumeLoad, unit),
        change: change(BlockMeasure.volume),
        note:
            '≈ ${formatVolumeLoad(block.perWeek(BlockMeasure.volume), unit)} a week',
      ),
      _Tile(
        label: 'Records',
        value: '${block.records}',
        note: block.records == 1 ? 'personal best' : 'personal bests',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 520 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.3
                ? 4
                : 2;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.md,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
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

  const _Tile({
    required this.label,
    required this.value,
    this.change,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = textSecondaryColor(context);
    final change = this.change;
    final rounded = change?.round();
    final (IconData icon, String text, String spoken) = switch (rounded) {
      null => (LucideIcons.minus, note ?? '', note ?? ''),
      0 => (LucideIcons.minus, 'Same', 'about the same per week'),
      > 0 => (
        LucideIcons.trendingUp,
        '$rounded% more',
        '$rounded% more per week',
      ),
      _ => (
        LucideIcons.trendingDown,
        '${-rounded}% less',
        '${-rounded}% less per week',
      ),
    };
    return Semantics(
      container: true,
      label: '$label, $value${spoken.isEmpty ? '' : ', $spoken'}',
      child: ExcludeSemantics(
        // No ground: these are read-only figures, and a ground means tappable.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(color: secondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: AppTypography.figures(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: textPrimaryColor(context),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  if (rounded != null) ...[
                    Icon(icon, size: 14, color: textPrimaryColor(context)),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.figures(
                        fontSize: 12,
                        fontWeight:
                            rounded == null ? FontWeight.w400 : FontWeight.w600,
                        color:
                            rounded == null
                                ? secondary
                                : textPrimaryColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One column per week of the block. Weeks ahead of the plan show as an
/// empty stub, so the block's length reads at a glance.
class _WeekBars extends StatelessWidget {
  static const double _plotHeight = 88;

  final BlockStatistics block;

  const _WeekBars({required this.block});

  @override
  Widget build(BuildContext context) {
    final weeks = block.weeks;
    final maximum = math.max(
      1,
      weeks.fold<int>(0, (max, week) => math.max(max, week.sets)),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final slot = 40.0 * math.max(1, scale);
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    Widget column(BlockWeekStatistics week) {
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
                week.reached ? '${week.sets}' : '',
                style: AppTypography.figures(fontSize: 11, color: ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: _plotHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child:
                      week.reached
                          ? Container(
                            key: ValueKey('block-week-bar-${week.number}'),
                            width: 22,
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
                            width: 22,
                            height: _plotHeight,
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
        if (weeks.length * slot <= constraints.maxWidth) {
          return Row(
            children: [for (final week in weeks) Expanded(child: column(week))],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              for (final week in weeks)
                SizedBox(width: slot, child: column(week)),
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
    final best = gains.first.percent;
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
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            gain.exerciseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '+${gain.percent.round()}%',
                          style: AppTypography.figures(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: successColor(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor:
                                  best <= 0
                                      ? 0
                                      : (gain.percent / best).clamp(0.04, 1),
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: accentDimColor(context),
                                  borderRadius: AppRadius.micro,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          '${_bareWeight(gain.start, unit)} → '
                          '${formatAnalyticsWeight(gain.end, unit)}',
                          style: AppTypography.figures(
                            fontSize: 12,
                            color: textSecondaryColor(context),
                          ),
                        ),
                      ],
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
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in BlockMeasure.values)
              StatisticsChip(
                key: ValueKey('block-measure-${option.name}'),
                label: option.label,
                selected: option == measure,
                onSelected: () => onMeasure(option),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
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
