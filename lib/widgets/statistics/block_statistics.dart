import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import 'block_trend.dart';
import 'statistics_controls.dart';
import 'statistics_widgets.dart';

/// Block-to-block progression leads; roomy totals and detail follow below.
class BlockOverview extends StatefulWidget {
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
  State<BlockOverview> createState() => _BlockOverviewState();
}

class _BlockOverviewState extends State<BlockOverview> {
  BlockTrendMeasure _measure = BlockTrendMeasure.volume;
  bool _perWeek = true;

  @override
  Widget build(BuildContext context) {
    final block = widget.selected;
    final index = widget.blocks.indexOf(block);
    final previous = index > 0 ? widget.blocks[index - 1] : null;
    final value = _measure.valueFor(block, perWeek: _perWeek);
    final before =
        previous == null
            ? null
            : _measure.valueFor(previous, perWeek: _perWeek);
    final change =
        before == null || before == 0 ? null : (value / before - 1) * 100;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: 'Block measure',
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return ScrollingPills<BlockTrendMeasure>(
                  values: BlockTrendMeasure.values,
                  selected: _measure,
                  labelFor: (measure) => measure.label,
                  onSelected: (measure) => setState(() => _measure = measure),
                  keyPrefix: 'block-measure',
                );
              }
              return SegmentedPills<BlockTrendMeasure>(
                quiet: true,
                values: BlockTrendMeasure.values,
                selected: _measure,
                labelFor: (measure) => measure.label,
                onSelected: (measure) => setState(() => _measure = measure),
                keyPrefix: 'block-measure',
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  block.block.name,
                  key: const ValueKey('block-overview-name'),
                  style: theme.textTheme.displaySmall,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PopupMenuButton<bool>(
              key: const ValueKey('block-basis'),
              tooltip: 'Calculation',
              initialValue: _perWeek,
              onSelected: (perWeek) => setState(() => _perWeek = perWeek),
              itemBuilder:
                  (context) => const [
                    PopupMenuItem(value: true, child: Text('Per trained week')),
                    PopupMenuItem(value: false, child: Text('Block total')),
                  ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _perWeek ? 'Per week' : 'Total',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accentColor(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      LucideIcons.chevronDown,
                      size: 14,
                      color: accentColor(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _measure.format(value, widget.weightUnit),
                key: const ValueKey('block-trend-value'),
                style: AppTypography.figures(
                  fontSize: 40,
                  height: 1.15,
                  letterSpacing: -1.5,
                  fontWeight: FontWeight.w600,
                  color: textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${_measure.label} ${_perWeek ? 'per trained week' : 'in this block'}',
                style: theme.textTheme.bodySmall,
              ),
              if (change != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${change > 0 ? '+' : ''}${change.round()}% vs ${previous!.block.name}',
                  style: AppTypography.figures(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textPrimaryColor(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        BlockTrendChart(
          blocks: widget.blocks,
          selectedId: block.block.id,
          measure: _measure,
          perWeek: _perWeek,
          weightUnit: widget.weightUnit,
          onSelect: widget.onSelect,
        ),
        const SizedBox(height: AppSpacing.xxl),
        const StatisticsSectionHeader(title: 'In this block'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          [
            if (block.block.id == widget.currentBlockId &&
                block.latestWeek != null)
              'Week ${block.latestWeek!.number} of ${block.plannedWeeks}',
            if (block.firstDate != null)
              formatDateSpan(block.firstDate!, block.lastDate!),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        _BlockTotals(block: block, unit: widget.weightUnit),
        const SizedBox(height: AppSpacing.xxl),
        const StatisticsSectionHeader(title: 'Weekly workload'),
        const SizedBox(height: AppSpacing.lg),
        _WeekBars(key: ValueKey('block-weeks-${block.block.id}'), block: block),
        const SizedBox(height: AppSpacing.xxl),
        Row(
          children: [
            const Expanded(
              child: StatisticsSectionHeader(title: 'Strength gains'),
            ),
            IconButton(
              tooltip: 'About strength gains',
              icon: Icon(
                LucideIcons.info,
                size: 16,
                color: textSecondaryColor(context),
              ),
              onPressed:
                  () => showDialog<void>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('Strength gains'),
                          content: const Text(
                            'The change in your best estimated one-rep max, from your first workout to your latest workout in this block. Tap a lift to see both values.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _Gains(
          key: ValueKey('block-gains-${block.block.id}'),
          gains: block.gains,
          unit: widget.weightUnit,
        ),
      ],
    );
  }
}

class _BlockTotals extends StatelessWidget {
  final BlockStatistics block;
  final String unit;

  const _BlockTotals({required this.block, required this.unit});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth > 700 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3
              ? 4
              : 2;
      final width =
          (constraints.maxWidth - AppSpacing.xl * (columns - 1)) / columns;
      final values = [
        ('Workouts', '${block.workouts}'),
        ('Sets', formatAnalyticsNumber(block.sets.toDouble())),
        ('Volume', formatVolumeLoad(block.volumeLoad, unit)),
        ('Records', '${block.records}'),
      ];
      return Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xl,
        children: [
          for (final (label, value) in values)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: AppTypography.figures(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// One column per week of the block. Weeks ahead of the plan show as a
/// short stub, so a block's length reads at a glance. A long run of unused
/// weeks after the latest workout is left out instead: forty empty columns
/// say nothing, and they would push the trained weeks out of view.
class _WeekBars extends StatefulWidget {
  static const double _plotHeight = 88;

  /// Up to this many weeks, the whole planned block is drawn.
  static const int _wholeBlockWeeks = 12;

  final BlockStatistics block;

  const _WeekBars({super.key, required this.block});

  @override
  State<_WeekBars> createState() => _WeekBarsState();
}

class _WeekBarsState extends State<_WeekBars> {
  int? _number;

  List<BlockWeekStatistics> get _visibleWeeks {
    final weeks = widget.block.weeks;
    if (weeks.length <= _WeekBars._wholeBlockWeeks) return weeks;
    final lastTrained = weeks.lastIndexWhere((week) => week.workouts > 0);
    return weeks.sublist(0, math.max(1, lastTrained + 1));
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final weeks = _visibleWeeks;
    final selected =
        weeks.where((week) => week.number == _number).firstOrNull ??
        block.latestWeek ??
        weeks.firstOrNull;
    if (selected == null) return const SizedBox.shrink();
    final maximum = math.max(
      1,
      weeks.fold<int>(0, (max, week) => math.max(max, week.sets)),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final slot = 52.0 * math.max(1, scale);
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    Widget column(BlockWeekStatistics week, double barWidth) {
      final latest = week.number == selected.number;
      final ink =
          latest ? textPrimaryColor(context) : textSecondaryColor(context);
      final height =
          week.sets == 0
              ? 0.0
              : math.max(4.0, week.sets / maximum * _WeekBars._plotHeight);
      return Semantics(
        button: true,
        selected: latest,
        label:
            !week.reached
                ? 'Week ${week.number}, not started'
                : 'Week ${week.number}, ${week.workouts} '
                    '${week.workouts == 1 ? 'workout' : 'workouts'}, '
                    '${week.sets} ${week.sets == 1 ? 'set' : 'sets'}',
        child: ExcludeSemantics(
          child: InkWell(
            key: ValueKey('block-week-${week.number}'),
            borderRadius: AppRadius.control,
            onTap: () => setState(() => _number = week.number),
            child: Column(
              children: [
                SizedBox(
                  height: _WeekBars._plotHeight,
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
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Text(
              'Week ${selected.number}  /  ${selected.reached ? '${selected.sets} ${selected.sets == 1 ? 'set' : 'sets'}' : 'Not started'}',
              key: const ValueKey('block-week-readout'),
              style: AppTypography.figures(
                fontSize: 14,
                color: textSecondaryColor(context),
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Bars widen with their column, so a short block doesn't look sparse.
            double barWidth(double column) => (column * 0.45).clamp(14, 32);
            if (weeks.length * slot <= constraints.maxWidth) {
              final width = barWidth(constraints.maxWidth / weeks.length);
              return Row(
                children: [
                  for (final week in weeks)
                    Expanded(child: column(week, width)),
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
        ),
      ],
    );
  }
}

class _Gains extends StatefulWidget {
  final List<LiftGain> gains;
  final String unit;

  const _Gains({super.key, required this.gains, required this.unit});

  @override
  State<_Gains> createState() => _GainsState();
}

class _GainsState extends State<_Gains> {
  final Set<String> _expanded = {};
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    if (widget.gains.isEmpty) {
      return Text(
        'Log the same lift in two workouts to see its change.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final gains = _showAll ? widget.gains : widget.gains.take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final gain in gains)
          Semantics(
            button: true,
            expanded: _expanded.contains(gain.exerciseId ?? gain.exerciseName),
            label:
                '${gain.exerciseName}, up ${gain.percent.round()}%, '
                'from ${formatAnalyticsWeight(gain.start, widget.unit)} '
                'to ${formatAnalyticsWeight(gain.end, widget.unit)}',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey(
                'block-gain-${gain.exerciseId ?? gain.exerciseName}',
              ),
              borderRadius: AppRadius.control,
              onTap:
                  () => setState(() {
                    if (!_expanded.add(gain.exerciseId ?? gain.exerciseName)) {
                      _expanded.remove(gain.exerciseId ?? gain.exerciseName);
                    }
                  }),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            gain.exerciseName,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Text(
                          '+${gain.percent.round()}%',
                          style: AppTypography.figures(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: successColor(context),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          _expanded.contains(
                                gain.exerciseId ?? gain.exerciseName,
                              )
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          size: 14,
                          color: textSecondaryColor(context),
                        ),
                      ],
                    ),
                    if (_expanded.contains(
                      gain.exerciseId ?? gain.exerciseName,
                    )) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${formatAnalyticsWeight(gain.start, widget.unit)} to ${formatAnalyticsWeight(gain.end, widget.unit)}',
                        style: AppTypography.figures(
                          fontSize: 13,
                          color: textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (widget.gains.length > 3)
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(
              _showAll
                  ? 'Show fewer lifts'
                  : 'Show all ${widget.gains.length} lifts',
            ),
          ),
      ],
    );
  }
}
