import 'package:flutter/material.dart';

import '../../models/workout_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// Summary of the most recent session, paired with a Resume action in the
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
          session.planName,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Week ${session.weekNumber}  ·  '
          '${session.exercises.length} exercises  ·  '
          '$sets sets  ·  '
          '${formatVolume(volume)} kg  ·  '
          'Top ${formatWeight(topWeight)} kg',
          style: AppTypography.trainingData(fontSize: 10, color: textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${session.date.day}/${session.date.month}/${session.date.year}',
          style: AppTypography.trainingData(fontSize: 9, color: accent),
        ),
      ],
    );
  }
}
