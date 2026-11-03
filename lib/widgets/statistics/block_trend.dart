import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';

/// Presentation measures for the block timeline; persisted models stay unchanged.
enum BlockTrendMeasure { volume, sets, workouts, records }

extension BlockTrendMeasureValues on BlockTrendMeasure {
  String get label => switch (this) {
    BlockTrendMeasure.volume => 'Volume',
    BlockTrendMeasure.sets => 'Sets',
    BlockTrendMeasure.workouts => 'Workouts',
    BlockTrendMeasure.records => 'Records',
  };

  double valueFor(BlockStatistics block, {required bool perWeek}) {
    final total = switch (this) {
      BlockTrendMeasure.volume => block.volumeLoad,
      BlockTrendMeasure.sets => block.sets.toDouble(),
      BlockTrendMeasure.workouts => block.workouts.toDouble(),
      BlockTrendMeasure.records => block.records.toDouble(),
    };
    return perWeek
        ? (block.trainedWeeks == 0 ? 0 : total / block.trainedWeeks)
        : total;
  }

  String format(double value, String unit, {bool compact = false}) {
    if (this == BlockTrendMeasure.volume) {
      return compact
          ? formatVolumeLoad(value, unit)
          : formatExactVolume(value, unit);
    }
    return formatAnalyticsNumber(
      value,
      decimals: value == value.roundToDouble() ? 0 : 1,
    );
  }
}

/// The block order is the horizontal axis. Selection is shared with the block's
/// totals and weekly detail below; only the plot browses horizontally.
class BlockTrendChart extends StatelessWidget {
  final List<BlockStatistics> blocks;
  final String selectedId;
  final BlockTrendMeasure measure;
  final bool perWeek;
  final String weightUnit;
  final ValueChanged<String> onSelect;

  const BlockTrendChart({
    super.key,
    required this.blocks,
    required this.selectedId,
    required this.measure,
    required this.perWeek,
    required this.weightUnit,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    final values = [
      for (final block in blocks) measure.valueFor(block, perWeek: perWeek),
    ];
    final selected = math.max(
      0,
      blocks.indexWhere((block) => block.block.id == selectedId),
    );
    final maximum = math.max(1.0, values.reduce(math.max) * 1.2);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final axisStyle = AppTypography.figures(
      fontSize: 11,
      color: textSecondaryColor(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = (constraints.maxWidth / (88 * scale)).floor().clamp(
          1,
          4,
        );
        final pitch = constraints.maxWidth / math.min(visible, blocks.length);
        final width = math.max(constraints.maxWidth, blocks.length * pitch);
        const height = 176.0;
        final offsets = [
          for (var i = 0; i < blocks.length; i++)
            Offset(pitch * (i + 0.5), height * (1 - values[i] / maximum)),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              measure.format(maximum, weightUnit, compact: true),
              textAlign: TextAlign.right,
              style: axisStyle,
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              key: const ValueKey('block-trend-scroll'),
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: SizedBox(
                width: width,
                height: height + 60 * scale,
                child: Stack(
                  children: [
                    SizedBox(
                      width: width,
                      height: height,
                      child: CustomPaint(
                        painter: _BlockTrendPainter(
                          points: offsets,
                          selected: selected,
                          ink: accentColor(context),
                          wash: accentMutedColor(context),
                          ground: backgroundColor(context),
                          guide: borderColor(context),
                        ),
                      ),
                    ),
                    for (var i = 0; i < blocks.length; i++)
                      Positioned(
                        left: i * pitch,
                        width: pitch,
                        top: 0,
                        bottom: 0,
                        child: Semantics(
                          button: true,
                          selected: i == selected,
                          label:
                              '${blocks[i].block.name}, ${measure.label}, '
                              '${measure.format(values[i], weightUnit)}, '
                              '${perWeek ? 'per trained week' : 'block total'}',
                          excludeSemantics: true,
                          child: InkWell(
                            key: ValueKey('block-point-${blocks[i].block.id}'),
                            borderRadius: AppRadius.control,
                            onTap: () => onSelect(blocks[i].block.id),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.sm,
                                  0,
                                  AppSpacing.sm,
                                  AppSpacing.md,
                                ),
                                child: Text(
                                  blocks[i].block.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium?.copyWith(
                                    color:
                                        i == selected
                                            ? textPrimaryColor(context)
                                            : textSecondaryColor(context),
                                    fontWeight:
                                        i == selected
                                            ? FontWeight.w700
                                            : FontWeight.w400,
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
            if (blocks.length == 1)
              Text(
                'Your next logged block will extend this trend.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (blocks.length > visible)
              Text(
                'Swipe through blocks. Tap a point to explore.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );
      },
    );
  }
}

class _BlockTrendPainter extends CustomPainter {
  final List<Offset> points;
  final int selected;
  final Color ink;
  final Color wash;
  final Color ground;
  final Color guide;

  const _BlockTrendPainter({
    required this.points,
    required this.selected,
    required this.ink,
    required this.wash,
    required this.ground,
    required this.guide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = guide,
      );
    }
    if (points.length > 1) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        line.lineTo(point.dx, point.dy);
      }
      final area =
          Path.from(line)
            ..lineTo(points.last.dx, size.height)
            ..lineTo(points.first.dx, size.height)
            ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [wash, ground],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = ink
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    final point = points[selected];
    canvas.drawLine(
      Offset(point.dx, point.dy + 8),
      Offset(point.dx, size.height),
      Paint()..color = guide,
    );
    for (final point in points) {
      canvas.drawCircle(point, 2.5, Paint()..color = ink);
    }
    canvas.drawCircle(point, 7, Paint()..color = ground);
    canvas.drawCircle(point, 5, Paint()..color = ink);
    canvas.drawCircle(point, 2, Paint()..color = ground);
  }

  @override
  bool shouldRepaint(_BlockTrendPainter old) =>
      !listEquals(old.points, points) ||
      old.selected != selected ||
      old.ink != ink ||
      old.wash != wash ||
      old.ground != ground ||
      old.guide != guide;
}
