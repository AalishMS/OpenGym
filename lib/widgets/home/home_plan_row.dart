import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../app_button.dart';
import '../phrase_line.dart';
import '../raised_card.dart';
import 'plan_marker.dart';

/// Where a plan stands this week, shown at the head of its details line.
enum HomePlanStatus {
  none,

  /// Trained since Monday.
  done,

  /// The next workout in the rotation.
  next,

  /// Its workout is under way; the Up next card offers to resume it.
  inProgress,
}

/// A plan on Home: a quiet row on the page, one of a ruled list.
///
/// Every plan is the same flat row. The plan that is next (or in progress)
/// says so at the head of its details line rather than lifting into a second
/// card under the Up next card, so the first screen has one raised launcher.
/// A tap opens the plan's workout, which the play glyph promises.
class HomePlanRow extends StatelessWidget {
  final WorkoutPlan plan;
  final int workoutNumber;
  final int workoutCount;
  final HomePlanStatus status;
  final VoidCallback onOpen;
  final VoidCallback onShowActions;

  const HomePlanRow({
    required this.plan,
    required this.workoutNumber,
    required this.workoutCount,
    required this.onOpen,
    required this.onShowActions,
    this.status = HomePlanStatus.none,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = titleCase(plan.name);
    final secondary = textSecondaryColor(context);
    final detailStyle = textTheme.bodySmall?.copyWith(color: secondary);
    final exercises = plan.exercises.length;
    final sets = plan.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.sets,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: RaisedCard(
        raised: false,
        onTap: onOpen,
        onLongPress: onShowActions,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              PlanMarker(
                plan: plan,
                number: workoutNumber,
                count: workoutCount,
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
                    PhraseLine(
                      style: detailStyle,
                      phrases: [
                        if (status != HomePlanStatus.none)
                          _StatusTag(status: status, style: detailStyle),
                        Text(
                          countOf(exercises, 'exercise'),
                          style: detailStyle,
                        ),
                        Text(countOf(sets, 'set'), style: detailStyle),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The row is the button; the glyph only says what it does.
              ExcludeSemantics(
                child: Icon(LucideIcons.play, size: 16, color: secondary),
              ),
              AppIconButton(
                label: 'Actions for $name',
                icon: LucideIcons.ellipsis,
                color: secondary,
                onPressed: onShowActions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Next`, `In progress` in accent ink, or a success check and `Done`.
class _StatusTag extends StatelessWidget {
  final HomePlanStatus status;
  final TextStyle? style;

  const _StatusTag({required this.status, required this.style});

  @override
  Widget build(BuildContext context) {
    final strong = style?.copyWith(fontWeight: FontWeight.w700);
    switch (status) {
      case HomePlanStatus.next:
        return Text(
          'Next',
          style: strong?.copyWith(color: accentColor(context)),
        );
      case HomePlanStatus.inProgress:
        return Text(
          'In progress',
          style: strong?.copyWith(color: accentColor(context)),
        );
      case HomePlanStatus.done:
        final color = successColor(context);
        return Semantics(
          label: 'Done this week',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.check, size: 12, color: color),
              const SizedBox(width: AppSpacing.xxs),
              Text('Done', style: strong?.copyWith(color: color)),
            ],
          ),
        );
      case HomePlanStatus.none:
        return const SizedBox.shrink();
    }
  }
}
