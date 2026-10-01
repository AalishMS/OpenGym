import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';

/// A quiet plan entry, with a distinct outline for the next workout.
class HomePlanRow extends StatelessWidget {
  final WorkoutPlan plan;
  final bool isNext;
  final VoidCallback onOpen;
  final VoidCallback onShowActions;

  const HomePlanRow({
    required this.plan,
    required this.isNext,
    required this.onOpen,
    required this.onShowActions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = titleCase(plan.name);
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final initials =
        words.take(2).map((word) => word.characters.first).join().toUpperCase();
    final markerGround = Color.alphaBlend(
      planColorOf(plan.planColor, context).withAlpha(32),
      raisedSurfaceColor(context),
    );
    final nextColor = planSwatch(2, context);
    final nextGround = Color.alphaBlend(
      nextColor.withAlpha(28),
      raisedSurfaceColor(context),
    );
    final exercises = plan.exercises.length;
    final sets = plan.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.sets,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Material(
        color: isNext ? raisedSurfaceColor(context) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: isNext ? BorderSide(color: nextColor) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          onLongPress: onShowActions,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.lg,
            ),
            child: Row(
              children: [
                Semantics(
                  label: '$name plan marker',
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: markerGround,
                      borderRadius: AppRadius.button,
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        initials.isEmpty ? 'P' : initials,
                        style: textTheme.labelMedium?.copyWith(
                          color: onColor(markerGround),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: textTheme.titleMedium?.copyWith(
                          color: textPrimaryColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$exercises ${exercises == 1 ? 'exercise' : 'exercises'} · '
                        '$sets ${sets == 1 ? 'set' : 'sets'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (isNext)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: nextGround,
                      borderRadius: AppRadius.chip,
                    ),
                    child: Text(
                      'Next',
                      style: textTheme.labelSmall?.copyWith(
                        color: onColor(nextGround),
                      ),
                    ),
                  )
                else
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: textSecondaryColor(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
