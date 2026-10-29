import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';

/// Every lift in the period on one line each: its latest value, the shape of
/// its trend and how far it moved. Tapping a lift opens it in the chart below.
class LiftList extends StatefulWidget {
  static const int collapsedCount = 5;

  final List<LiftSummary> lifts;
  final String? selected;
  final ExerciseMetric metric;
  final String weightUnit;
  final ValueChanged<String> onSelect;

  const LiftList({
    super.key,
    required this.lifts,
    required this.selected,
    required this.metric,
    required this.weightUnit,
    required this.onSelect,
  });

  @override
  State<LiftList> createState() => _LiftListState();
}

class _LiftListState extends State<LiftList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lifts = widget.lifts;
    final selectedIndex = lifts.indexWhere(
      (lift) => lift.exerciseName == widget.selected,
    );
    // A selection further down the list keeps itself visible when collapsed.
    final visible =
        _expanded || lifts.length <= LiftList.collapsedCount
            ? lifts
            : [
              ...lifts.take(LiftList.collapsedCount),
              if (selectedIndex >= LiftList.collapsedCount)
                lifts[selectedIndex],
            ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final lift in visible)
          _LiftRow(
            key: ValueKey('lift-${lift.exerciseName}'),
            lift: lift,
            selected: lift.exerciseName == widget.selected,
            metric: widget.metric,
            unit: widget.weightUnit,
            onTap: () => widget.onSelect(lift.exerciseName),
          ),
        if (lifts.length > LiftList.collapsedCount)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 18,
            ),
            label: Text(
              _expanded ? 'Show fewer' : 'Show all ${lifts.length} lifts',
            ),
          ),
      ],
    );
  }
}

class _LiftRow extends StatelessWidget {
  final LiftSummary lift;
  final bool selected;
  final ExerciseMetric metric;
  final String unit;
  final VoidCallback onTap;

  const _LiftRow({
    super.key,
    required this.lift,
    required this.selected,
    required this.metric,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = lift.progress.points;
    final latest = points.last;
    final change = lift.progress.change;
    final value = formatChartExerciseValue(latest.value, metric, unit);
    final changeText =
        change == null || change == 0
            ? null
            : '${change > 0 ? '+' : '−'}'
                '${formatChartExerciseValue(change.abs(), metric, unit)}';
    final changeColor =
        change != null && change > 0
            ? successColor(context)
            : textSecondaryColor(context);
    final changeLabel = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (changeText != null) ...[
          Icon(
            change! > 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown,
            size: 14,
            color: changeColor,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(
          child: Text(
            changeText ?? (points.length < 2 ? 'New' : 'Same'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.figures(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  changeText == null
                      ? textSecondaryColor(context)
                      : changeColor,
            ),
          ),
        ),
      ],
    );
    // Large text has no room for a trailing column; the change moves under
    // the value instead of being cut short.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${lift.exerciseName}, ${metric.label} $value'
          '${changeText == null ? '' : ', change $changeText'}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.control,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected ? accentColor(context) : null,
                    borderRadius: AppRadius.micro,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lift.exerciseName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          value,
                          style: AppTypography.figures(
                            fontSize: 12,
                            color: textSecondaryColor(context),
                          ),
                        ),
                        if (stacked) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          changeLabel,
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 64,
                  height: 28,
                  child: CustomPaint(
                    painter: _SparkPainter(
                      values: [for (final point in points) point.value],
                      color: accentColor(context),
                    ),
                  ),
                ),
                if (!stacked) ...[
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 76,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: changeLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  const _SparkPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final range = high - low;
    const inset = 3.0;
    Offset at(int i) => Offset(
      values.length == 1
          ? size.width - inset
          : inset + (size.width - inset * 2) * i / (values.length - 1),
      range == 0
          ? size.height / 2
          : inset + (size.height - inset * 2) * (1 - (values[i] - low) / range),
    );
    if (values.length > 1) {
      final path = Path()..moveTo(at(0).dx, at(0).dy);
      for (var i = 1; i < values.length; i++) {
        path.lineTo(at(i).dx, at(i).dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawCircle(at(values.length - 1), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.color != color || !_sameValues(old.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
