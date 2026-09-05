import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../utils/statistics_format.dart';

class WeeklyVolumeChart extends StatefulWidget {
  final List<WeeklyTrainingValue> weeks;
  final String weightUnit;

  const WeeklyVolumeChart({
    super.key,
    required this.weeks,
    required this.weightUnit,
  });

  @override
  State<WeeklyVolumeChart> createState() => _WeeklyVolumeChartState();
}

class _WeeklyVolumeChartState extends State<WeeklyVolumeChart> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final weeks = widget.weeks;
    if (weeks.isEmpty) return const Text('No performed sets yet.');
    final selected = weeks.indexWhere((week) => week.weekStart == _selected);
    final index = selected < 0 ? weeks.length - 1 : selected;
    final week = weeks[index];
    final maximum = _niceMaximum(
      weeks.fold<double>(
        0,
        (value, week) =>
            math.max(value, displayWeight(week.volumeLoad, widget.weightUnit)),
      ),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final slot = math.max(56.0, 56 * scale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChartReadout(
          value: formatExactVolume(week.volumeLoad, widget.weightUnit),
          label:
              index == weeks.length - 1
                  ? 'This week · In progress'
                  : '${formatIsoWeek(week.weekStart)} · ${isoWeek(week.weekStart).year}',
          detail: formatWeekRange(week.weekStart),
        ),
        const SizedBox(height: 20),
        _ScrollablePlot(
          storageKey: 'weekly-volume-scroll',
          axisTitle: 'Volume (${widget.weightUnit})',
          maximum: maximum,
          unit: widget.weightUnit,
          onLatest: () => setState(() => _selected = null),
          builder:
              (context, width) => SizedBox(
                width: math.max(width, weeks.length * slot),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < weeks.length; i++)
                        Semantics(
                          button: true,
                          selected: i == index,
                          label:
                              '${formatWeekRange(weeks[i].weekStart)}, ${formatExactVolume(weeks[i].volumeLoad, widget.weightUnit)}',
                          child: InkWell(
                            key: ValueKey(
                              'week-${weeks[i].weekStart.toIso8601String()}',
                            ),
                            borderRadius: AppRadius.control,
                            onTap:
                                () => setState(
                                  () => _selected = weeks[i].weekStart,
                                ),
                            child: SizedBox(
                              width: slot,
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: _plotHeight,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final height =
                                            displayWeight(
                                              weeks[i].volumeLoad,
                                              widget.weightUnit,
                                            ) /
                                            maximum *
                                            _plotHeight;
                                        return Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned(
                                              bottom: height + 6,
                                              left: 0,
                                              right: 0,
                                              child: Text(
                                                formatChartNumber(
                                                  displayWeight(
                                                    weeks[i].volumeLoad,
                                                    widget.weightUnit,
                                                  ),
                                                ),
                                                textAlign: TextAlign.center,
                                                style: AppTypography.trainingData(
                                                  fontSize: 11,
                                                  color:
                                                      i == index
                                                          ? textPrimaryColor(
                                                            context,
                                                          )
                                                          : textSecondaryColor(
                                                            context,
                                                          ),
                                                ),
                                              ),
                                            ),
                                            Align(
                                              alignment: Alignment.bottomCenter,
                                              child: Container(
                                                key: ValueKey('volume-bar-$i'),
                                                width: 24,
                                                height: height,
                                                decoration: BoxDecoration(
                                                  color:
                                                      i == index
                                                          ? accentFillColor(
                                                            context,
                                                          )
                                                          : accentDimColor(
                                                            context,
                                                          ),
                                                  borderRadius:
                                                      AppRadius.barCap,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    formatIsoWeek(weeks[i].weekStart),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium?.copyWith(
                                      color:
                                          i == index
                                              ? textPrimaryColor(context)
                                              : textSecondaryColor(context),
                                    ),
                                  ),
                                ],
                              ),
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

class ExerciseTrendChart extends StatefulWidget {
  final ExerciseProgress progress;
  final ExerciseMetric metric;
  final String weightUnit;

  const ExerciseTrendChart({
    super.key,
    required this.progress,
    required this.metric,
    required this.weightUnit,
  });

  @override
  State<ExerciseTrendChart> createState() => _ExerciseTrendChartState();
}

class _ExerciseTrendChartState extends State<ExerciseTrendChart> {
  String? _sessionId;

  @override
  Widget build(BuildContext context) {
    final points = widget.progress.points;
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          widget.metric == ExerciseMetric.estimatedOneRepMax
              ? 'No weighted sets with 1–12 reps in this period. Choose another metric or a longer period.'
              : 'No performed sets in this period. Choose a longer period to see earlier workouts.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: textSecondaryColor(context)),
        ),
      );
    }
    final found = points.indexWhere((point) => point.session.id == _sessionId);
    final selected = found < 0 ? points.length - 1 : found;
    final point = points[selected];
    final weighted =
        widget.metric != ExerciseMetric.totalReps &&
        widget.metric != ExerciseMetric.totalSets;
    final values =
        points
            .map(
              (point) =>
                  weighted
                      ? displayWeight(point.value, widget.weightUnit)
                      : point.value,
            )
            .toList();
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final spread = math.max(
      maxValue - minValue,
      math.max(maxValue * 0.15, 1.0),
    );
    final lower = math.max(0.0, minValue - spread * 0.3);
    final upper = maxValue + spread * 0.35;
    final step = _niceStep((upper - lower) / 3);
    final maximum = math.max(3 * step, (upper / step).ceil() * step);
    final minimum = math.max(0.0, maximum - 3 * step);
    final unit =
        weighted
            ? widget.weightUnit
            : widget.metric == ExerciseMetric.totalReps
            ? 'reps'
            : 'sets';
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final slot = math.max(80.0, 80 * scale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScrollablePlot(
          storageKey: 'exercise-trend-scroll',
          divisions: 3,
          maximum: maximum,
          minimum: minimum,
          unit: unit,
          onLatest: () => setState(() => _sessionId = null),
          builder: (context, viewport) {
            final width = math.max(viewport, points.length * slot);
            final pitch = width / points.length;
            final offsets = [
              for (var i = 0; i < values.length; i++)
                Offset(
                  pitch * (i + 0.5),
                  _plotHeight *
                      (1 - (values[i] - minimum) / (maximum - minimum)),
                ),
            ];
            return SizedBox(
              width: width,
              height: _plotHeight + 46 * scale,
              child: Stack(
                children: [
                  SizedBox(
                    width: width,
                    height: _plotHeight,
                    child: CustomPaint(
                      painter: _TrendPainter(
                        points: offsets,
                        selected: selected,
                        ink: accentColor(context),
                        ground: surfaceColor(context),
                        guide: borderColor(context),
                      ),
                    ),
                  ),
                  for (var i = 0; i < points.length; i++)
                    Positioned(
                      left: i * pitch,
                      width: pitch,
                      top: 0,
                      bottom: 0,
                      child: Semantics(
                        button: true,
                        selected: i == selected,
                        label:
                            '${formatStatisticsDate(points[i].session.date)}, ${formatChartExerciseValue(points[i].value, widget.metric, widget.weightUnit)}, ${points[i].session.planName}',
                        child: InkWell(
                          borderRadius: AppRadius.control,
                          key: ValueKey('progress-point-$i'),
                          onTap:
                              () => setState(
                                () => _sessionId = points[i].session.id,
                              ),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                '${points[i].session.date.day} ${_month(points[i].session.date)}',
                                style: Theme.of(
                                  context,
                                ).textTheme.labelMedium?.copyWith(
                                  color: textSecondaryColor(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    width: pitch,
                    top: math.max(0, offsets.last.dy - 27 * scale),
                    child: IgnorePointer(
                      child: Text(
                        formatChartNumber(values.last),
                        textAlign: TextAlign.center,
                        style: AppTypography.trainingData(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textPrimaryColor(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        ChartReadout(
          value: formatChartExerciseValue(
            point.value,
            widget.metric,
            widget.weightUnit,
          ),
          label:
              selected == points.length - 1
                  ? 'Latest workout'
                  : 'Selected workout',
          detail:
              '${formatStatisticsDate(point.session.date)} · ${point.session.planName}',
          compact: true,
        ),
      ],
    );
  }
}

const double _plotHeight = 180;

double _niceMaximum(double value) {
  if (value <= 0) return 1;
  return _niceStep(value * 1.25 / 4) * 4;
}

double _niceStep(double target) {
  final power = math.pow(10, (math.log(target) / math.ln10).floor()).toDouble();
  for (final multiple in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (multiple * power >= target) return multiple * power;
  }
  return 10 * power;
}

String _month(DateTime date) => formatStatisticsDate(date).split(' ')[1];

class ChartReadout extends StatelessWidget {
  final String value;
  final String label;
  final String detail;
  final bool compact;

  const ChartReadout({
    super.key,
    required this.value,
    required this.label,
    required this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: textSecondaryColor(context)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.trainingData(
            fontSize: compact ? 20 : 30,
            fontWeight: FontWeight.w700,
            color: textPrimaryColor(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: textSecondaryColor(context)),
        ),
      ],
    ),
  );
}

/// Only the plot scrolls. The axis, scale, and unit remain in view.
class _ScrollablePlot extends StatefulWidget {
  final double maximum;
  final double minimum;
  final String unit;
  final String? axisTitle;
  final String storageKey;
  final int divisions;
  final Widget Function(BuildContext, double) builder;
  final VoidCallback onLatest;

  const _ScrollablePlot({
    required this.maximum,
    this.minimum = 0,
    required this.unit,
    this.axisTitle,
    required this.storageKey,
    this.divisions = 4,
    required this.builder,
    required this.onLatest,
  });

  @override
  State<_ScrollablePlot> createState() => _ScrollablePlotState();
}

class _ScrollablePlotState extends State<_ScrollablePlot> {
  final _scroll = ScrollController(keepScrollOffset: false);
  bool _older = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final older = _scroll.offset > 8;
    if (older != _older) setState(() => _older = older);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final textScaler = MediaQuery.textScalerOf(context);
    final axisStyle = DefaultTextStyle.of(context).style.merge(
      AppTypography.trainingData(
        fontSize: 11,
        letterSpacing: 0,
        color: textSecondaryColor(context),
      ),
    );
    final labels = [
      for (var i = 0; i <= widget.divisions; i++)
        formatChartNumber(
          widget.maximum -
              (widget.maximum - widget.minimum) * i / widget.divisions,
        ),
    ];
    // Measure the actual typeface and accessibility scale: a fixed gutter can
    // split suffixes such as "k" onto a second line or clip longer values.
    final labelSizes =
        labels.map((label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: axisStyle),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          final size = painter.size;
          painter.dispose();
          return size;
        }).toList();
    final axisWidth =
        labelSizes
            .fold<double>(0, (width, size) => math.max(width, size.width))
            .ceilToDouble() +
        12;
    final footer = 46.0 * scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: axisWidth),
            Expanded(
              child: Text(
                widget.axisTitle ?? widget.unit,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child:
                  _older
                      ? TextButton.icon(
                        onPressed: () {
                          _scroll.jumpTo(0);
                          widget.onLatest();
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('Latest'),
                      )
                      : null,
            ),
          ],
        ),
        SizedBox(
          height: _plotHeight + footer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: axisWidth,
                height: _plotHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i <= widget.divisions; i++)
                      Positioned(
                        top:
                            i * _plotHeight / widget.divisions -
                            labelSizes[i].height / 2,
                        left: 0,
                        right: 12,
                        child: Text(
                          labels[i],
                          key: ValueKey('${widget.storageKey}-axis-$i'),
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.right,
                          style: axisStyle,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder:
                      (context, constraints) => Stack(
                        children: [
                          for (var i = 0; i <= widget.divisions; i++)
                            Positioned(
                              top: i * _plotHeight / widget.divisions,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 1,
                                color: borderColor(context),
                              ),
                            ),
                          Scrollbar(
                            controller: _scroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              key: ValueKey(widget.storageKey),
                              controller: _scroll,
                              reverse: true,
                              scrollDirection: Axis.horizontal,
                              child: widget.builder(
                                context,
                                constraints.maxWidth,
                              ),
                            ),
                          ),
                        ],
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<Offset> points;
  final int selected;
  final Color ink;
  final Color ground;
  final Color guide;
  const _TrendPainter({
    required this.points,
    required this.selected,
    required this.ink,
    required this.ground,
    required this.guide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final selectedPoint = points[selected];
    canvas.drawLine(
      Offset(selectedPoint.dx, 0),
      Offset(selectedPoint.dx, size.height),
      Paint()
        ..color = guide
        ..strokeWidth = 1,
    );
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        points[i],
        i == selected ? 6 : 4,
        Paint()..color = ground,
      );
      canvas.drawCircle(
        points[i],
        i == selected ? 6 : 4,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (i == selected) {
        canvas.drawCircle(points[i], 2.5, Paint()..color = ink);
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      selected != oldDelegate.selected ||
      ink != oldDelegate.ink ||
      ground != oldDelegate.ground ||
      guide != oldDelegate.guide ||
      !listEquals(points, oldDelegate.points);
}
