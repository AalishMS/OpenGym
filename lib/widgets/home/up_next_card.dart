import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/exercise_library.dart';
import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/plan_stats.dart';
import '../app_button.dart';

/// A workout launcher; weekly activity lives outside this card.
class UpNextCard extends StatelessWidget {
  final WorkoutPlan plan;
  final int day;
  final int dayCount;
  final PlanStat? stat;
  final VoidCallback onStart;
  final Set<int> trainedDays;
  final int? durationMinutes;
  final GlobalKey? tutorialStartKey;

  const UpNextCard({
    required this.plan,
    required this.day,
    required this.dayCount,
    required this.stat,
    required this.onStart,
    this.trainedDays = const {},
    this.durationMinutes,
    this.tutorialStartKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    // Neutral emphasis pairs with every user-selected accent.
    final nextColor = textPrimaryColor(context);
    final last = stat?.lastTrained;
    final names = plan.exercises.map((e) => e.name.toLowerCase()).toSet();
    final groups =
        ExerciseLibrary.categories.entries
            .where(
              (entry) =>
                  entry.value.any((name) => names.contains(name.toLowerCase())),
            )
            .map((entry) => entry.key)
            .toList();
    final sets = plan.exercises.fold<int>(0, (sum, e) => sum + e.sets);
    final count = plan.exercises.length;
    // One meta line instead of a chip row keeps the card short enough for the
    // plan list to show below it on a phone.
    final meta = [
      if (groups.isNotEmpty) groups.join(', '),
      'Day $day of $dayCount',
      '$count ${count == 1 ? 'exercise' : 'exercises'}',
      '$sets ${sets == 1 ? 'set' : 'sets'}',
      if (durationMinutes != null) '~$durationMinutes min',
    ].join(' · ');

    return Material(
      color: raisedSurfaceColor(context),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor(context).withAlpha(96)),
        borderRadius: AppRadius.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onStart,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(
                    'Next up',
                    style: textTheme.labelLarge?.copyWith(color: nextColor),
                  ),
                  if (last != null)
                    Text(
                      'Last: ${formatDaysAgo(last).toLowerCase()}',
                      style: textTheme.bodySmall?.copyWith(color: secondary),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                label:
                    'Day $day of $dayCount. ${trainedDays.length} plans trained this week',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var index = 0; index < dayCount; index++) ...[
                        if (index > 0) const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color:
                                  index == day - 1
                                      ? nextColor
                                      : trainedDays.contains(index)
                                      ? accentFillColor(context)
                                      : borderColor(context),
                              borderRadius: AppRadius.micro,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                titleCase(plan.name),
                style: textTheme.headlineLarge?.copyWith(
                  color: textPrimaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                meta,
                style: textTheme.bodySmall?.copyWith(color: secondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton.primary(
                key: tutorialStartKey,
                label: 'Start workout',
                onPressed: onStart,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.play, size: 18),
                    SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        'Start workout',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
