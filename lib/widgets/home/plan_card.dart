import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/plan_colors.dart';
import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/format.dart';
import '../../utils/plan_stats.dart';

/// One plan in the Plans list.
///
/// Every card has the same three lines (name, exercise preview, summary), each
/// held to a single line, so cards line up whatever the plans contain. The old
/// grid let the preview run to three lines or none, which is what made one card
/// look nothing like its neighbour.
///
/// The plan's colour is spent on one thing, the numbered badge, which also
/// shows the plan's place in the split's rotation.
class PlanCard extends StatelessWidget {
  final WorkoutPlan plan;

  /// Index into `WorkoutPlanProvider.plans`; shown one-based on the badge.
  final int index;
  final PlanStat? stat;
  final VoidCallback onOpen;
  final VoidCallback onShowActions;

  /// Now, for deciding whether the plan was trained this week. Tests pin it.
  final DateTime? now;

  const PlanCard({
    required this.plan,
    required this.index,
    required this.stat,
    required this.onOpen,
    required this.onShowActions,
    this.now,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final exerciseNames = plan.exercises.map((e) => e.name).toList();

    return Container(
      // Clips the ink splash to the rounded corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context), width: 1),
        borderRadius: AppRadius.card,
      ),
      // A transparent Material above the fill, so the splash is drawn over the
      // card instead of underneath its opaque colour.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          onLongPress: onShowActions,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                _PlanBadge(plan: plan, number: index + 1),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titleCase(plan.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        exerciseNames.isEmpty
                            ? 'No exercises yet'
                            : exerciseNames.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PlanVolumeSummary(plan: plan),
                          _Recency(stat: stat, now: now),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Plan actions',
                  onPressed: onShowActions,
                  icon: Icon(
                    LucideIcons.ellipsis,
                    size: 18,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `6 exercises · 18 sets`, with the counts set in the primary text colour so
/// the numbers carry the line.
class PlanVolumeSummary extends StatelessWidget {
  final WorkoutPlan plan;

  const PlanVolumeSummary({required this.plan, super.key});

  @override
  Widget build(BuildContext context) {
    final exercises = plan.exercises.length;
    final sets = plan.exercises.fold<int>(0, (sum, e) => sum + e.sets);
    final base = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: textSecondaryColor(context));
    final figure = base?.copyWith(color: textPrimaryColor(context));

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: '$exercises', style: figure),
          TextSpan(text: exercises == 1 ? ' exercise' : ' exercises'),
          const TextSpan(text: '  ·  '),
          TextSpan(text: '$sets', style: figure),
          TextSpan(text: sets == 1 ? ' set' : ' sets'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The plan's colour as a rounded square holding its place in the rotation.
class _PlanBadge extends StatelessWidget {
  final WorkoutPlan plan;
  final int number;

  const _PlanBadge({required this.plan, required this.number});

  static const double _side = 40;

  @override
  Widget build(BuildContext context) {
    final color = planColorOf(plan.planColor, context);
    // Grows with the text inside it, but only so far: past 1.5x the badge
    // would crowd the name it sits beside.
    final side = math.min(
      MediaQuery.textScalerOf(context).scale(_side),
      _side * 1.5,
    );

    return Semantics(
      label: '${titleCase(plan.name)} plan marker',
      child: Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: AppRadius.button),
        child: ExcludeSemantics(
          child: Text(
            number.toString().padLeft(2, '0'),
            style: AppTypography.trainingData(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: onColor(color),
            ),
          ),
        ),
      ),
    );
  }
}

/// When the plan was last trained. Plans already done this week get a check in
/// the success colour, so the list reads as the week's to-do list at a glance.
class _Recency extends StatelessWidget {
  final PlanStat? stat;
  final DateTime? now;

  const _Recency({required this.stat, this.now});

  @override
  Widget build(BuildContext context) {
    final last = stat?.lastTrained;
    final today = now ?? DateTime.now();
    final doneThisWeek = last != null && !last.isBefore(startOfWeek(today));
    final color =
        doneThisWeek ? successColor(context) : textSecondaryColor(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          doneThisWeek ? LucideIcons.check : LucideIcons.clock,
          size: 12,
          color: color,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            last == null ? 'Not trained yet' : formatDaysAgo(last, now: today),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: doneThisWeek ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
