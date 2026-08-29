import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// A single KPI readout — big accented number over a small muted caption.
///
/// Promoted out of `stats_screen.dart` (was a private `_SummaryCard`) so the
/// Dashboard and Stats screens show identical numbers in identical boxes.
class StatTile extends StatelessWidget {
  final String label;
  final String value;

  /// Colour for the number. Defaults to the active theme accent.
  final Color? accent;

  const StatTile({
    required this.label,
    required this.value,
    this.accent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = accent ?? accentColor(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context), width: 1),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: textSecondaryColor(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
