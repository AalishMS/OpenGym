import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../utils/statistics_format.dart';

class StatisticsSectionHeader extends StatelessWidget {
  final String title;
  final String? supportingText;

  const StatisticsSectionHeader({
    super.key,
    required this.title,
    this.supportingText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (supportingText != null) ...[
          const SizedBox(height: 4),
          Text(
            supportingText!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

class StatisticsChoiceBar<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  const StatisticsChoiceBar({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          Semantics(
            button: true,
            selected: value == selected,
            label: labelFor(value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: ChoiceChip(
                label: Text(labelFor(value)),
                selected: value == selected,
                onSelected: (_) => onSelected(value),
                showCheckmark: false,
              ),
            ),
          ),
      ],
    );
  }
}

class WeeklyTrainingChart extends StatelessWidget {
  final TrainingOverview overview;
  final TrainingMetric metric;
  final String weightUnit;

  const WeeklyTrainingChart({
    super.key,
    required this.overview,
    required this.metric,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    if (metric == TrainingMetric.duration && !overview.hasDurationData) {
      return const _ChartEmptyState(
        message: 'Duration was not recorded for these workouts.',
      );
    }
    final values = overview.weeks.map((week) => week.valueFor(metric)).toList();
    final maximum = values.fold<double>(0, math.max);
    final chartWidth =
        math
            .max(
              MediaQuery.sizeOf(context).width - 64,
              overview.weeks.length * 34,
            )
            .toDouble();
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          height: 240,
          child: Semantics(
            label: '${metric.label} by week',
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maximum == 0 ? 1.0 : maximum * 1.15,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final week = overview.weeks[group.x];
                      return BarTooltipItem(
                        'Week of ${formatStatisticsDate(week.weekStart)}\n'
                        '${formatTrainingValue(rod.toY, metric, weightUnit)}',
                        GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: textPrimaryColor(context),
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: _labelInterval(overview.weeks.length),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= overview.weeks.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            formatWeekLabel(overview.weeks[index].weekStart),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: textSecondaryColor(context),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine:
                      (_) =>
                          FlLine(color: borderColor(context), strokeWidth: 1),
                ),
                barGroups: [
                  for (var index = 0; index < values.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: values[index],
                          width: 18,
                          color: accentColor(context),
                          borderRadius: AppRadius.barCap,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _labelInterval(int count) {
    if (count <= 6) return 1;
    if (count <= 14) return 2;
    return (count / 8).ceilToDouble();
  }
}

class ExerciseProgressChart extends StatelessWidget {
  final ExerciseProgress progress;
  final ExerciseMetric metric;
  final String weightUnit;

  const ExerciseProgressChart({
    super.key,
    required this.progress,
    required this.metric,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    if (progress.points.isEmpty) {
      return _ChartEmptyState(
        message:
            metric == ExerciseMetric.estimatedOneRepMax
                ? 'No valid weighted sets are available for estimated 1RM.'
                : 'No performed sets are available for this exercise.',
      );
    }
    final maximum = progress.points
        .map((point) => point.value)
        .reduce(math.max);
    final minimum = progress.points
        .map((point) => point.value)
        .reduce(math.min);
    final padding = math.max((maximum - minimum) * 0.2, maximum * 0.08);
    final chartWidth =
        math
            .max(
              MediaQuery.sizeOf(context).width - 64,
              progress.points.length * 54,
            )
            .toDouble();
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          height: 240,
          child: Semantics(
            label: '${metric.label} progress chart',
            child: LineChart(
              LineChartData(
                minY: math.max(0.0, minimum - padding),
                maxY: maximum + (padding == 0 ? 1 : padding),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems:
                        (spots) => [
                          for (final spot in spots)
                            LineTooltipItem(
                              '${formatStatisticsDate(progress.points[spot.x.toInt()].session.date)}\n'
                              '${formatExerciseValue(spot.y, metric, weightUnit)}',
                              GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: textPrimaryColor(context),
                              ),
                            ),
                        ],
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval:
                          math
                              .max(1, (progress.points.length / 6).ceil())
                              .toDouble(),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= progress.points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            formatWeekLabel(
                              progress.points[index].session.date,
                            ),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: textSecondaryColor(context),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine:
                      (_) =>
                          FlLine(color: borderColor(context), strokeWidth: 1),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (
                        var index = 0;
                        index < progress.points.length;
                        index++
                      )
                        FlSpot(index.toDouble(), progress.points[index].value),
                    ],
                    isCurved: false,
                    color: accentColor(context),
                    barWidth: 2,
                    belowBarData: BarAreaData(show: false),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter:
                          (spot, percent, bar, index) => FlDotCirclePainter(
                            radius: 4,
                            color: accentColor(context),
                            strokeColor: surfaceColor(context),
                            strokeWidth: 2,
                          ),
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

class SessionStatisticsRow extends StatelessWidget {
  final SessionStatistics statistics;
  final String weightUnit;
  final VoidCallback onTap;

  const SessionStatisticsRow({
    super.key,
    required this.statistics,
    required this.weightUnit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final session = statistics.session;
    return Semantics(
      button: true,
      label:
          'Open ${session.planName} workout from ${formatStatisticsDate(session.date)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor(context))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.planName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatStatisticsDate(session.date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _DataText(
                    label: 'Duration',
                    value:
                        statistics.durationSeconds == null
                            ? 'Not recorded'
                            : formatStatisticsDuration(
                              statistics.durationSeconds!,
                            ),
                  ),
                  _DataText(
                    label: 'Volume',
                    value: formatVolumeLoad(statistics.volumeLoad, weightUnit),
                  ),
                  _DataText(label: 'Reps', value: '${statistics.totalReps}'),
                  _DataText(label: 'Sets', value: '${statistics.totalSets}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordEventRow extends StatelessWidget {
  final RecordEvent event;
  final String weightUnit;

  const RecordEventRow({
    super.key,
    required this.event,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    final labels = <String>[];
    for (final achievement in event.achievements) {
      final label = achievement.type.label(achievement.reps);
      if (!labels.contains(label)) labels.add(label);
    }
    final producer = event.achievements.last;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor(context),
              borderRadius: AppRadius.micro,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.exerciseName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  labels.join(' · '),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: accentColor(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatAnalyticsWeight(producer.setWeight, weightUnit)} × '
                  '${producer.setReps} · ${event.session.planName} · '
                  '${formatStatisticsDate(event.session.date)}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MetricSummary extends StatelessWidget {
  final List<(String, String)> values;

  const MetricSummary({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final value in values)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112),
            child: _DataText(label: value.$1, value: value.$2, prominent: true),
          ),
      ],
    );
  }
}

class _DataText extends StatelessWidget {
  final String label;
  final String value;
  final bool prominent;

  const _DataText({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: textSecondaryColor(context)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: prominent ? 16 : 12,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w600,
            color: textPrimaryColor(context),
          ),
        ),
      ],
    );
  }
}

class _ChartEmptyState extends StatelessWidget {
  final String message;

  const _ChartEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: textSecondaryColor(context)),
      ),
    );
  }
}
