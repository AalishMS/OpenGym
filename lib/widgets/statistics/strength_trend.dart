import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import '../motion/state_switcher.dart';
import 'trend_line.dart';
import 'training_overview.dart';
import '../rolling_figure.dart';

/// A lift's selected value, plot and period summary on a single open canvas.
class StrengthTrend extends StatefulWidget {
  final ExerciseProgress progress;
  final ExerciseMetric metric;
  final String weightUnit;

  /// What the plot shows: the lift, period and measure. A new dataset starts
  /// at the latest workout, lands its figures at once and crosses the plot
  /// to the new line; the same dataset with new workouts updates in place.
  /// Defaults to [metric].
  final Object? dataset;

  const StrengthTrend({
    super.key,
    required this.progress,
    required this.metric,
    required this.weightUnit,
    this.dataset,
  });

  @override
  State<StrengthTrend> createState() => _StrengthTrendState();
}

class _StrengthTrendState extends State<StrengthTrend> {
  String? _sessionId;

  Object get _dataset => widget.dataset ?? widget.metric;

  @override
  void didUpdateWidget(StrengthTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.dataset ?? oldWidget.metric) != _dataset) _sessionId = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.progress.points;
    if (points.isEmpty) return const SizedBox.shrink();
    final found = points.indexWhere((p) => p.session.id == _sessionId);
    final selected = found < 0 ? points.length - 1 : found;
    final point = points[selected];
    final raw = points.map((p) => p.value).toList();
    final low = raw.reduce(math.min);
    final high = raw.reduce(math.max);
    final spread = math.max(high - low, math.max(high * 0.12, 1.0));
    final minimum = math.max(0.0, low - spread * 0.35);
    final maximum = high + spread * 0.35;
    final change = widget.progress.change;
    String value(double number) =>
    // A timed or bodyweight-only lift falls back to seconds or reps.
    formatProgressValue(
      number,
      widget.metric,
      widget.progress.fallback,
      widget.weightUnit,
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final dataset = _dataset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          // Keyed by the dataset, so a figure from another lift, period or
          // measure lands at once instead of rolling from a value it isn't
          // comparable with. The key sits below this column's own children:
          // a keyed sibling would make the plot beside it rebuild from
          // scratch, and its cross would never play.
          child: Column(
            key: ValueKey(('readout', dataset)),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selected == points.length - 1
                    ? 'Latest workout'
                    : 'Selected workout',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              RollingFigure(
                value(point.value),
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
                '${formatStatisticsDate(point.session.date)} · ${point.session.planName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final pitch = math.max(
              48 * scale,
              constraints.maxWidth / math.max(1, points.length),
            );
            final width = math.max(constraints.maxWidth, points.length * pitch);
            const height = 180.0;
            final offsets = [
              for (var i = 0; i < points.length; i++)
                Offset(
                  pitch * (i + 0.5),
                  height *
                      (1 - (points[i].value - minimum) / (maximum - minimum)),
                ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The measure is named by its picker above the readout.
                Text(
                  value(maximum),
                  textAlign: TextAlign.right,
                  style: AppTypography.figures(
                    fontSize: 11,
                    color: textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Another lift, period or measure is a different line, so
                // the plot crosses to it rather than morphing.
                StateSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey(('plot', dataset)),
                    child: SingleChildScrollView(
                      key: const ValueKey('strength-timeline'),
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: SizedBox(
                        width: width,
                        height: height + 36 * scale,
                        child: Stack(
                          children: [
                            SizedBox(
                              width: width,
                              height: height,
                              child: CustomPaint(
                                painter: TrendLinePainter(
                                  points: offsets,
                                  selected: selected,
                                  ink: accentColor(context),
                                  wash: accentMutedColor(context),
                                  ground: backgroundColor(context),
                                  guide: hairlineColor(context),
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
                                      '${formatStatisticsDate(points[i].session.date)}, ${value(points[i].value)}, ${points[i].session.planName}',
                                  excludeSemantics: true,
                                  child: InkWell(
                                    key: ValueKey('strength-point-$i'),
                                    borderRadius: AppRadius.control,
                                    onTap:
                                        () => setState(
                                          () =>
                                              _sessionId = points[i].session.id,
                                        ),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppSpacing.sm,
                                        ),
                                        child:
                                            i > 0 &&
                                                    DateUtils.isSameDay(
                                                      points[i - 1]
                                                          .session
                                                          .date,
                                                      points[i].session.date,
                                                    )
                                                ? null
                                                : Text(
                                                  formatDayMonth(
                                                    points[i].session.date,
                                                  ),
                                                  style: AppTypography.figures(
                                                    fontSize: 10,
                                                    color: textSecondaryColor(
                                                      context,
                                                    ),
                                                  ),
                                                ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        // Lands at once for a new dataset, like the readout; the unkeyed
        // wrapper keeps the key out of this column's own children.
        KeyedSubtree(
          child: StatisticsFigures(
            key: ValueKey(('figures', dataset)),
            values: [
              (
                'Change',
                change == null
                    ? 'Need 2 workouts'
                    : formatSignedChange(change, value),
              ),
              ('Best in period', value(high)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${points.length} ${points.length == 1 ? 'workout' : 'workouts'} in this period. Tap a point to inspect it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
