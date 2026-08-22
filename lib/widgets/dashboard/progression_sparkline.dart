import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// Chrome-free max-weight trend line for one exercise.
///
/// No axes, no grid, no dots — just the shape of the progress, sized to fit a
/// dashboard tile. Angular (`isCurved: false`) like every other chart here; the
/// numbers that matter are spelled out underneath instead of on an axis.
class ProgressionSparkline extends StatelessWidget {
  final String exercise;

  /// Max weight per session, oldest → newest.
  final List<double> values;
  final double height;

  const ProgressionSparkline({
    required this.exercise,
    required this.values,
    this.height = 80,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);

    if (values.length < 2) {
      return Text(
        '> not enough sessions to plot',
        style: GoogleFonts.jetBrainsMono(fontSize: 10, color: textSecondary),
      );
    }

    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    // Pad the band so a flat line doesn't collapse onto the frame edge.
    final pad = (max - min) == 0 ? 5.0 : (max - min) * 0.15;

    final delta = values.last - values.first;
    final deltaColor = delta > 0
        ? successColor(context)
        : delta < 0
            ? errorColor(context)
            : textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          exercise.toUpperCase(),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: textPrimaryColor(context),
            letterSpacing: 0.02,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: min - pad,
              maxY: max + pad,
              lineTouchData: const LineTouchData(enabled: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < values.length; i++)
                      FlSpot(i.toDouble(), values[i]),
                  ],
                  isCurved: false,
                  color: accent,
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: accent.withAlpha(30),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              '${formatWeight(min)}KG → ${formatWeight(max)}KG',
              style:
                  GoogleFonts.jetBrainsMono(fontSize: 9, color: textSecondary),
            ),
            const Spacer(),
            Text(
              '${delta >= 0 ? '+' : ''}${formatWeight(delta)}KG',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: deltaColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
