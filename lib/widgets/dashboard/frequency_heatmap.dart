import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// GitHub-style contribution grid: one column per week, one square per day.
///
/// Built by hand rather than with fl_chart — the cells are barely-rounded
/// squares on a 1px grid at a size a chart library fights. Intensity climbs the
/// theme's opaque accent washes (see [heatmapSteps]), so it recolours with the
/// user's accent.
///
/// [HiveService.getWorkoutFrequency] is per-*week*, so this buckets raw
/// sessions by calendar day instead.
class FrequencyHeatmap extends StatelessWidget {
  final List<WorkoutSession> sessions;

  /// Cell edge length in logical pixels.
  final double cellSize;

  /// Gap between cells.
  final double gap;

  const FrequencyHeatmap({
    required this.sessions,
    this.cellSize = 12,
    this.gap = 3,
    super.key,
  });

  static const _dayLabels = ['M', '', 'W', '', 'F', '', 'S'];

  @override
  Widget build(BuildContext context) {
    final steps = heatmapSteps(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);

    // Bucket by calendar day (time-of-day stripped) so two sessions on the same
    // day stack into one darker square.
    final counts = <DateTime, int>{};
    for (final s in sessions) {
      final day = DateTime(s.date.year, s.date.month, s.date.day);
      counts[day] = (counts[day] ?? 0) + 1;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Last column is the week containing today; walk back to its Monday.
    final lastMonday = today.subtract(Duration(days: today.weekday - 1));

    const labelWidth = 14.0;
    final columnWidth = cellSize + gap;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the available width with as many week-columns as fit, clamped to
        // a year. `constraints.maxWidth` is finite inside the tile grid.
        final available = constraints.maxWidth - labelWidth - AppSpacing.sm;
        final weeks = (available / columnWidth).floor().clamp(4, 53);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final label in _dayLabels)
                    SizedBox(
                      height: cellSize + gap,
                      child: Text(
                        label,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          height: 1.4,
                          color: textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Row(
              children: [
                for (int w = weeks - 1; w >= 0; w--)
                  Padding(
                    padding: EdgeInsets.only(right: w == 0 ? 0 : gap),
                    child: Column(
                      children: [
                        for (int d = 0; d < 7; d++)
                          _cell(
                            date: lastMonday
                                .subtract(Duration(days: w * 7))
                                .add(Duration(days: d)),
                            today: today,
                            counts: counts,
                            steps: steps,
                            border: border,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _cell({
    required DateTime date,
    required DateTime today,
    required Map<DateTime, int> counts,
    required List<Color> steps,
    required Color border,
  }) {
    final future = date.isAfter(today);
    final count = counts[date] ?? 0;

    // 0 → empty outline; 1/2/3+ → the three opaque accent washes. Opaque, not
    // `accent.withAlpha(...)`: the alpha steps composited against whatever sat
    // behind the cell, so the same count read as a different colour on a card
    // than on the page. [steps] is the shared ramp the legend also draws.
    final Color fill;
    if (future || count == 0) {
      fill = Colors.transparent;
    } else if (count == 1) {
      fill = steps[1];
    } else if (count == 2) {
      fill = steps[2];
    } else {
      fill = steps[3];
    }

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Tooltip(
        message: '${date.day}/${date.month}/${date.year} · '
            '$count workout${count == 1 ? '' : 's'}',
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          width: cellSize,
          height: cellSize,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(
              color: future ? border.withAlpha(80) : border,
              width: 1,
            ),
            borderRadius: AppRadius.micro,
          ),
        ),
      ),
    );
  }
}

/// The four intensity steps of the heatmap, shared by [FrequencyHeatmap] and
/// [HeatmapLegend] so the grid and its key can never drift apart. Step 0 is the
/// empty-cell transparent; 1–3 are the theme's opaque accent washes, even
/// perceptual steps from the background up to the full fill.
List<Color> heatmapSteps(BuildContext context) => [
      Colors.transparent,
      accentMutedColor(context),
      accentDimColor(context),
      accentFillColor(context),
    ];

/// `LESS ▪▪▪▪ MORE` key for [FrequencyHeatmap].
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryColor(context);
    final style = GoogleFonts.jetBrainsMono(fontSize: 8, color: textSecondary);
    final steps = heatmapSteps(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('LESS', style: style),
        const SizedBox(width: AppSpacing.xs),
        for (final c in steps)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: c,
                border: Border.all(color: borderColor(context)),
                borderRadius: AppRadius.micro,
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.xxs),
        Text('MORE', style: style),
      ],
    );
  }
}
