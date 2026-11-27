import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/exercise_library.dart';
import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../services/exercise_catalog.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../app_button.dart';
import '../plan_title_hero.dart';
import '../raised_card.dart';
import 'plan_marker.dart';

/// A workout launcher; weekly activity lives outside this card.
///
/// A tap anywhere on the card does what Start (or Resume) does. That tap is
/// for a pointer only: the button stays the one target a screen reader or
/// keyboard meets, so the action is announced once.
class UpNextCard extends StatelessWidget {
  /// Shared with the workout header, so the plan name flies between them.
  static String heroTagFor(WorkoutPlan plan) =>
      'up-next-title-${plan.id ?? plan.name}';

  final WorkoutPlan plan;

  /// One-based place of [plan] in [rotation].
  final int day;

  /// The split's plans in the order they are trained.
  final List<WorkoutPlan> rotation;
  final VoidCallback onStart;
  final GlobalKey? tutorialStartKey;

  /// This plan's workout is already under way, so the card offers to resume
  /// it instead of starting the next one.
  final bool inProgress;

  const UpNextCard({
    required this.plan,
    required this.day,
    required this.rotation,
    required this.onStart,
    this.tutorialStartKey,
    this.inProgress = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // What the workout trains, in the picker's order. The counts are on the
    // plan's own row in the list below; a custom exercise has no group.
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

    return RaisedCard(
      onTap: onStart,
      pointerOnly: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The plan's own mark, as the list below draws it, says which
            // workout this is; the bar beside it places it in the rotation.
            // The status sits on the marker's top edge and the bar on its
            // bottom, so the three read as one mark.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PlanMarker(plan: plan, number: day, count: rotation.length),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          inProgress ? 'In progress' : 'Next up',
                          // Without the leading above it, the caps meet the
                          // marker's top instead of hanging below it.
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                          ),
                          style: textTheme.labelLarge?.copyWith(
                            color: textPrimaryColor(context),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: _RotationBar(
                            plans: rotation,
                            current: day - 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
                style: textTheme.bodySmall?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
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

/// The split's rotation: one segment per plan, each in its plan's colour.
///
/// The plan on offer stands taller than the rest. Height is its only
/// emphasis, so it still reads when two plans share a colour or have none.
/// The marker beside the bar speaks the place aloud, so the bar is silent.
class _RotationBar extends StatelessWidget {
  static const double _rest = 2;
  static const double _current = 6;

  final List<WorkoutPlan> plans;

  /// Zero-based index of the plan on offer.
  final int current;

  const _RotationBar({required this.plans, required this.current});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: _current,
        child: Row(
          children: [
            for (var index = 0; index < plans.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Container(
                  key: ValueKey('rotation-segment-$index'),
                  height: index == current ? _current : _rest,
                  decoration: BoxDecoration(
                    color: planColorOf(plans[index].planColor, context),
                    borderRadius: AppRadius.micro,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
