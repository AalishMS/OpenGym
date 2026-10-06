import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';

class WorkoutHeatmap extends StatefulWidget {
  final List<WorkoutSession> sessions;
  final DateTime? now;

  const WorkoutHeatmap({super.key, required this.sessions, this.now});

  @override
  State<WorkoutHeatmap> createState() => _WorkoutHeatmapState();
}

class _WorkoutHeatmapState extends State<WorkoutHeatmap> {
  static const _weeks = 52;
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
  final ScrollController _scrollController = ScrollController();

  // UTC is only a calendar key for the local date, as in statistics analytics.
  // Advancing keys by days cannot skip/repeat a row at a DST boundary.
  DateTime _calendarDate(DateTime date) {
    final local = date.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = _calendarDate(widget.now ?? DateTime.now());
    final start = end.subtract(
      Duration(days: (_weeks - 1) * 7 + end.weekday - DateTime.monday),
    );
    final counts = <DateTime, int>{};
    for (final session in widget.sessions) {
      if (!session.isCompleted || session.deletedAt != null) continue;
      final date = _calendarDate(session.date);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      counts[date] = (counts[date] ?? 0) + 1;
    }

    final localizations = MaterialLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: textSecondaryColor(context),
      fontSize: 11,
    );
    final scale = MediaQuery.textScalerOf(context);
    final step = math.max(16.0, scale.scale(11) * 1.5 + 4);
    final headerHeight = step + 8;
    final gridWidth = _weeks * step;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${localizations.formatMediumDate(start)} – '
          '${localizations.formatMediumDate(end)}',
          style: style,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: headerHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final label in const [
                    'Mon',
                    '',
                    'Wed',
                    '',
                    'Fri',
                    '',
                    '',
                  ])
                    SizedBox(
                      height: step,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(label, style: style),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: gridWidth,
                    child: Column(
                      children: [
                        _monthLabels(start, end, step, headerHeight, style),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int week = 0; week < _weeks; week++)
                              Column(
                                children: [
                                  for (int day = 0; day < 7; day++)
                                    _dayCell(
                                      start.add(Duration(days: week * 7 + day)),
                                      end,
                                      counts,
                                      step,
                                      localizations,
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Workouts per day', style: style),
            for (int count = 0; count < 4; count++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _square(count, 12),
                  const SizedBox(width: 4),
                  Text(count == 3 ? '3+' : '$count', style: style),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _monthLabels(
    DateTime start,
    DateTime end,
    double step,
    double height,
    TextStyle? style,
  ) {
    final labelWidth = MediaQuery.textScalerOf(context).scale(36);
    final labels = <Widget>[];
    double nextLeft = _weeks * step;
    // Place the newest label first so even a one-day current month is named.
    // Suppress a short partial month at the left edge if labels would overlap.
    for (
      DateTime month = DateTime.utc(end.year, end.month);
      !month.isBefore(DateTime.utc(start.year, start.month));
      month = DateTime.utc(month.year, month.month - 1)
    ) {
      final week = math.max(0, month.difference(start).inDays ~/ 7);
      final left = math.min(week * step, _weeks * step - labelWidth);
      if (left + labelWidth > nextLeft) continue;
      labels.add(
        Positioned(
          left: left,
          top: 0,
          width: labelWidth,
          child: Text(_months[month.month - 1], style: style),
        ),
      );
      nextLeft = left;
    }
    return SizedBox(
      width: _weeks * step,
      height: height,
      child: Stack(children: labels),
    );
  }

  Widget _dayCell(
    DateTime date,
    DateTime end,
    Map<DateTime, int> counts,
    double step,
    MaterialLocalizations localizations,
  ) {
    if (date.isAfter(end)) return SizedBox(width: step, height: step);
    final count = counts[date] ?? 0;
    final label =
        '${localizations.formatFullDate(date)}: '
        '$count ${count == 1 ? 'workout' : 'workouts'}';
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox(
          width: step,
          height: step,
          child: Center(child: _square(count, step - 4)),
        ),
      ),
    );
  }

  Widget _square(int count, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: switch (count) {
        0 => backgroundColor(context),
        1 => accentMutedColor(context),
        2 => accentDimColor(context),
        _ => accentFillColor(context),
      },
      borderRadius: AppRadius.micro,
      border:
          count == 0
              ? Border.all(color: borderColor(context), width: 0.5)
              : null,
    ),
  );
}
