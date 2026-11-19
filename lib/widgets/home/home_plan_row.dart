import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../app_button.dart';
import '../raised_card.dart';

/// A quiet plan entry; the next workout rises into a raised card.
class HomePlanRow extends StatelessWidget {
  final WorkoutPlan plan;
  final int workoutNumber;
  final bool isNext;
  final VoidCallback onOpen;
  final VoidCallback onShowActions;

  const HomePlanRow({
    required this.plan,
    required this.workoutNumber,
    required this.isNext,
    required this.onOpen,
    required this.onShowActions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = titleCase(plan.name);
    final planColor = planColorOf(plan.planColor, context);
    // Light mode washes the marker in the plan's colour. A wash that faint over
    // near-black is a dark, greyed tone, and a dark orange or yellow *is* brown
    // or olive, so in dark mode the colour moves into the number instead, on
    // the control fill. The plan colour is solved for 4.5:1 on that fill.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final markerGround =
        dark
            ? controlFillColor(context)
            : Color.alphaBlend(
              planColor.withAlpha(32),
              isNext ? surfaceColor(context) : backgroundColor(context),
            );
    final markerInk = dark ? planColor : onColor(markerGround);
    final exercises = plan.exercises.length;
    final sets = plan.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.sets,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      // The next workout lifts off the ledger as a raised card; the rest are
      // rows on the page.
      child: RaisedCard(
        raised: isNext,
        onTap: onOpen,
        onLongPress: onShowActions,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            children: [
              Semantics(
                label: '$name plan marker',
                value: 'Workout $workoutNumber',
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
                      '$workoutNumber',
                      style: AppTypography.figures(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: markerInk,
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
                Text(
                  'Next',
                  style: textTheme.labelMedium?.copyWith(
                    color: accentColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              AppIconButton(
                label: 'Actions for $name',
                icon: LucideIcons.ellipsis,
                color: textSecondaryColor(context),
                onPressed: onShowActions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
