import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/exercise_library.dart';
import '../../services/exercise_catalog.dart';
import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/plan_stats.dart';
import '../app_button.dart';
import '../plan_title_hero.dart';
import '../raised_card.dart';

/// A workout launcher; weekly activity lives outside this card.
class UpNextCard extends StatelessWidget {
  /// Shared with the workout header, so the plan name flies between them.
  static String heroTagFor(WorkoutPlan plan) =>
      'up-next-title-${plan.id ?? plan.name}';

  final WorkoutPlan plan;
  final int day;
  final int dayCount;
  final PlanStat? stat;
  final VoidCallback onStart;
  final Set<int> trainedDays;
  final int? durationMinutes;
  final GlobalKey? tutorialStartKey;

  /// This plan's workout is already under way, so the card offers to resume
  /// it instead of starting the next one.
  final bool inProgress;

  const UpNextCard({
    required this.plan,
    required this.day,
    required this.dayCount,
    required this.stat,
    required this.onStart,
    this.trainedDays = const {},
    this.durationMinutes,
    this.tutorialStartKey,
    this.inProgress = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    // Neutral emphasis pairs with every user-selected accent.
    final nextColor = textPrimaryColor(context);
    // The strip marks the next workout as its strongest step. In light mode
    // that is near-black ink after accent steps. In dark mode the same rule
    // drew a white bar, the brightest thing in the card, louder than the
    // title, so there the next step is the full accent and finished workouts
    // drop to its dim wash.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final nextStep = dark ? accentFillColor(context) : nextColor;
    final doneStep = dark ? accentDimColor(context) : accentFillColor(context);
    final last = stat?.lastTrained;
    final groups =
        plan.exercises
            .map(
              (e) =>
                  ExerciseCatalog.getById(
                    ExerciseCatalog.identity(e.name, e.exerciseId),
                  )?.category,
            )
            .whereType<String>()
            .where((category) => category != 'Custom')
            .toSet()
            .toList()
          ..sort(
            (a, b) => ExerciseLibrary.categoryNames
                .indexOf(a)
                .compareTo(ExerciseLibrary.categoryNames.indexOf(b)),
          );
    final sets = plan.exercises.fold<int>(0, (sum, e) => sum + e.sets);
    final count = plan.exercises.length;
    final meta = [
      '$count ${count == 1 ? 'exercise' : 'exercises'}',
      '$sets ${sets == 1 ? 'set' : 'sets'}',
      if (durationMinutes != null) '~$durationMinutes min',
    ];

    return RaisedCard(
      onTap: onStart,
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
                  inProgress ? 'In progress' : 'Next up',
                  style: textTheme.labelLarge?.copyWith(color: nextColor),
                ),
                if (last != null)
                  Text(
                    'Last: ${formatDaysAgo(last).toLowerCase()}',
                    style: textTheme.bodySmall?.copyWith(color: secondary),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Workout $day of $dayCount',
              style: textTheme.bodySmall?.copyWith(color: secondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label:
                  'Workout $day of $dayCount. ${trainedDays.length} plans trained this week',
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
                                    ? nextStep
                                    : trainedDays.contains(index)
                                    ? doneStep
                                    : controlFillColor(context),
                            borderRadius: AppRadius.micro,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PlanTitleHero(
              tag: heroTagFor(plan),
              text: titleCase(plan.name),
              style: textTheme.headlineLarge?.copyWith(
                color: textPrimaryColor(context),
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                groups.join(', '),
                style: textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                for (final detail in meta)
                  Text(
                    detail,
                    style: textTheme.bodySmall?.copyWith(color: secondary),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton.primary(
              key: tutorialStartKey,
              label: inProgress ? 'Resume workout' : 'Start workout',
              onPressed: onStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.play, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      inProgress ? 'Resume workout' : 'Start workout',
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
    );
  }
}
