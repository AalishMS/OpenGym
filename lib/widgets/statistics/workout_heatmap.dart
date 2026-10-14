import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';

/// Recent training days, one column per week and one square per day.
///
/// The grid fits the width it is given: as many 16px weeks as fit, between
/// [minWeeks] and [maxWeeks], with no scrolling. The caption and the summary
/// read off the same window, so they always describe what is drawn.
///
/// Each day is either a workout day or not: most people train once a day, so
/// a per-day count would be a ramp almost nobody climbs. The count still
/// appears in each day's tooltip and semantics label.
class WorkoutHeatmap extends StatelessWidget {
  final List<WorkoutSession> sessions;
  final DateTime? now;

  static const minWeeks = 12;
  static const maxWeeks = 52;

  const WorkoutHeatmap({super.key, required this.sessions, this.now});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder:
        (context, constraints) => _HeatmapGrid(
          sessions: sessions,
          now: now,
          width: constraints.maxWidth,
        ),
  );
}

class _HeatmapGrid extends StatelessWidget {
  final List<WorkoutSession> sessions;
  final DateTime? now;
  final double width;

  const _HeatmapGrid({
    required this.sessions,
    required this.now,
    required this.width,
  });

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  // UTC is only a calendar key for the local date, as in statistics analytics.
  // Advancing keys by days cannot skip/repeat a row at a DST boundary.
  DateTime _calendarDate(DateTime date) {
    final local = date.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: textSecondaryColor(context),
      fontSize: 11,
    );
    final scale = MediaQuery.textScalerOf(context);
    // Rows keep room for a day label; the weeks share the width that is left.
    final step = math.max(16.0, scale.scale(11) * 1.5 + 4);
    final labelWidth = scale.scale(12);
    final gridWidth = math.max(0.0, width - labelWidth - 6);
    final weeks = (gridWidth / step).floor().clamp(
      WorkoutHeatmap.minWeeks,
      WorkoutHeatmap.maxWeeks,
    );
    final column = gridWidth / weeks;
    final cell = math.min(step, column) - 4;
    final headerHeight = step + 4;

    final end = _calendarDate(now ?? DateTime.now());
    final start = end.subtract(
      Duration(days: (weeks - 1) * 7 + end.weekday - DateTime.monday),
    );
    final counts = <DateTime, int>{};
    for (final session in sessions) {
      if (!session.isCompleted || session.deletedAt != null) continue;
      final date = _calendarDate(session.date);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      counts[date] = (counts[date] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Days you trained · Last $weeks weeks',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: textSecondaryColor(context)),
        ),
        const SizedBox(height: 20),
        _Summary(counts: counts, start: start, weeks: weeks),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: headerHeight),
              child: Column(
                children: [
                  for (final label in _dayLabels)
                    SizedBox(
                      height: step,
                      width: labelWidth,
                      child: Center(child: Text(label, style: style)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: gridWidth,
              child: Column(
                children: [
                  _monthLabels(
                    context,
                    start,
                    end,
                    weeks,
                    column,
                    headerHeight,
                    style,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int week = 0; week < weeks; week++)
                        Column(
                          children: [
                            for (int day = 0; day < 7; day++)
                              _dayCell(
                                context,
                                start.add(Duration(days: week * 7 + day)),
                                end,
                                counts,
                                width: column,
                                height: step,
                                size: cell,
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _legendItem(
              _square(context, worked: true, size: 12),
              'Workout',
              style,
            ),
            _legendItem(
              _square(context, worked: false, today: true, size: 12),
              'Today',
              style,
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Widget key, String label, TextStyle? style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [key, const SizedBox(width: 6), Text(label, style: style)],
  );

  Widget _monthLabels(
    BuildContext context,
    DateTime start,
    DateTime end,
    int weeks,
    double column,
    double height,
    TextStyle? style,
  ) {
    final labelWidth = MediaQuery.textScalerOf(context).scale(36);
    final labels = <Widget>[];
    double nextLeft = weeks * column;
    // Place the newest label first so even a one-day current month is named.
    // Suppress a short partial month at the left edge if labels would overlap.
    for (
      DateTime month = DateTime.utc(end.year, end.month);
      !month.isBefore(DateTime.utc(start.year, start.month));
      month = DateTime.utc(month.year, month.month - 1)
    ) {
      final week = math.max(0, month.difference(start).inDays ~/ 7);
      final left = math.min(week * column, weeks * column - labelWidth);
      if (left + labelWidth > nextLeft) continue;
      labels.add(
        Positioned(
          left: left + 2,
          top: 0,
          width: labelWidth,
          child: Text(_months[month.month - 1], style: style),
        ),
      );
      nextLeft = left;
    }
    return SizedBox(
      width: weeks * column,
      height: height,
      child: Stack(children: labels),
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime date,
    DateTime end,
    Map<DateTime, int> counts, {
    required double width,
    required double height,
    required double size,
  }) {
    if (date.isAfter(end)) return SizedBox(width: width, height: height);
    final count = counts[date] ?? 0;
    final label =
        '${MaterialLocalizations.of(context).formatFullDate(date)}: '
        '${switch (count) {
          0 => 'No workout',
          1 => '1 workout',
          _ => '$count workouts',
        }}';
    // Each day is its own node; without the old scroll viewport, sibling
    // labels would otherwise merge into one long announcement.
    return Semantics(
      container: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: _square(
              context,
              worked: count > 0,
              today: date == end,
              size: size,
            ),
          ),
        ),
      ),
    );
  }

  Widget _square(
    BuildContext context, {
    required bool worked,
    bool today = false,
    required double size,
  }) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      // The page colour reads as a quiet hole in the card; borderColor was
      // solved for hairlines and made a year of rest days look heavy.
      color: worked ? accentFillColor(context) : backgroundColor(context),
      borderRadius: AppRadius.micro,
      border:
          today ? Border.all(color: accentColor(context), width: 1.5) : null,
    ),
  );
}

/// Workout days, the current weekly streak and the weekly average, read off
/// the same calendar the grid draws.
class _Summary extends StatelessWidget {
  final Map<DateTime, int> counts;
  final DateTime start;
  final int weeks;

  const _Summary({
    required this.counts,
    required this.start,
    required this.weeks,
  });

  @override
  Widget build(BuildContext context) {
    final activeWeeks = List.filled(weeks, false);
    for (final date in counts.keys) {
      activeWeeks[date.difference(start).inDays ~/ 7] = true;
    }

    // The current week is still in progress, so an empty one doesn't break
    // the streak yet.
    var week = activeWeeks.length - 1;
    if (!activeWeeks[week]) week--;
    var streak = 0;
    while (week >= 0 && activeWeeks[week]) {
      streak++;
      week--;
    }

    // Average over the weeks since training started in this window, so a new
    // user isn't divided by a year they weren't here for.
    final firstWeek = activeWeeks.indexOf(true);
    final average =
        firstWeek < 0 ? 0.0 : counts.length / (activeWeeks.length - firstWeek);
    final averageText =
        average == average.roundToDouble()
            ? average.toStringAsFixed(0)
            : average.toStringAsFixed(1);

    final values = [
      ('Workout days', '${counts.length}'),
      ('Week streak', '$streak ${streak == 1 ? 'week' : 'weeks'}'),
      ('Days per week', averageText),
    ];
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final (label, value) in values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.figures(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimaryColor(context),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
