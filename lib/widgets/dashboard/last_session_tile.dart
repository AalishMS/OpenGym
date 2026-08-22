import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// Summary of the most recent session, paired with a `[RESUME]` action in the
/// enclosing panel's header.
class LastSessionTile extends StatelessWidget {
  final WorkoutSession session;

  const LastSessionTile({required this.session, super.key});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);

    var sets = 0;
    var volume = 0;
    var topWeight = 0.0;
    for (final exercise in session.exercises) {
      sets += exercise.sets.length;
      for (final set in exercise.sets) {
        volume += (set.weight * set.reps).round();
        if (set.weight > topWeight) topWeight = set.weight;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          session.planName.toUpperCase(),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: textPrimaryColor(context),
            letterSpacing: 0.04,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'WEEK ${session.weekNumber}  ·  '
          '${session.exercises.length} EXERCISES  ·  '
          '$sets SETS  ·  '
          '${formatVolume(volume)} KG  ·  '
          'TOP ${formatWeight(topWeight)}KG',
          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '// ${session.date.day}/${session.date.month}/${session.date.year}',
          style: GoogleFonts.jetBrainsMono(fontSize: 9, color: accent),
        ),
      ],
    );
  }
}

/// `[ LABEL ]` bracket button in the terminal idiom, sized for panel headers.
class BracketButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const BracketButton({required this.label, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? accentColor(context) : textSecondaryColor(context);

    return InkWell(
      onTap: onTap,
      splashColor: color.withAlpha(40),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(border: Border.all(color: color)),
        child: Text(
          '[$label]',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.06,
          ),
        ),
      ),
    );
  }
}
