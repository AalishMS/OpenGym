import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/spacing.dart';

/// GitHub-style contribution grid: one column per week, one square per day.
///
/// Built by hand rather than with fl_chart — the aesthetic wants hard-edged,
/// zero-radius cells on a 1px grid, which a chart library fights. Intensity is
/// the accent at increasing alpha, so it recolours with the user's theme.
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
    final accent = accentColor(context);
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
                            accent: accent,
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
    required Color accent,
    required Color border,
  }) {
    final future = date.isAfter(today);
    final count = counts[date] ?? 0;

    // 0 → empty outline; 1/2/3+ → three accent steps.
    final Color fill;
    if (future || count == 0) {
      fill = Colors.transparent;
    } else if (count == 1) {
      fill = accent.withAlpha(90);
    } else if (count == 2) {
      fill = accent.withAlpha(160);
    } else {
      fill = accent;
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
          ),
        ),
      ),
    );
  }
}

/// `LESS ▪▪▪▪ MORE` key for [FrequencyHeatmap].
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    final style = GoogleFonts.jetBrainsMono(fontSize: 8, color: textSecondary);
    final steps = [
      Colors.transparent,
      accent.withAlpha(90),
      accent.withAlpha(160),
      accent,
    ];

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
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.xxs),
        Text('MORE', style: style),
      ],
    );
  }
}
