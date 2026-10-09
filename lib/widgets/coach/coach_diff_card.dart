import 'package:flutter/material.dart';

import '../../models/coach_proposal.dart';
import '../../services/coach/proposal_diff.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Sets as runs of identical sets: `3 × 8 · 60 kg, 1 × 6 · 65 kg`. A weight
/// of 0 is "no weight target", so it's left out.
String formatCoachSets(List<CoachSet> sets) {
  final runs = <(int, CoachSet)>[];
  for (final set in sets) {
    if (runs.isNotEmpty && runs.last.$2 == set) {
      runs.last = (runs.last.$1 + 1, set);
    } else {
      runs.add((1, set));
    }
  }
  return [
    for (final (count, set) in runs)
      set.kg == 0
          ? '$count × ${set.reps}'
          : '$count × ${set.reps} · ${coachNumber(set.kg)} kg',
  ].join(', ');
}

/// One affected plan on the review screen.
class CoachPlanDiffCard extends StatelessWidget {
  final PlanDiff plan;

  const CoachPlanDiffCard({required this.plan, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final removed = plan.kind == DiffKind.removed;
    final status = switch (plan.kind) {
      DiffKind.added => 'New plan',
      DiffKind.removed => 'Removed',
      DiffKind.changed when plan.renamed => 'Renamed from ${plan.previousName}',
      DiffKind.changed => 'Changed',
      DiffKind.unchanged => 'No changes',
    };

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              plan.name,
              style: textTheme.titleMedium?.copyWith(
                color:
                    removed ? errorColor(context) : textPrimaryColor(context),
                decoration: removed ? TextDecoration.lineThrough : null,
                decorationColor: errorColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            status,
            style: textTheme.bodySmall?.copyWith(
              color:
                  plan.kind == DiffKind.added
                      ? accentColor(context)
                      : textSecondaryColor(context),
            ),
          ),
          if (!removed) ...[
            const SizedBox(height: AppSpacing.md),
            for (final exercise in plan.exercises)
              CoachExerciseDiffRow(exercise: exercise),
          ],
        ],
      ),
    );
  }
}

/// One exercise: added in the accent ink, removed struck through in the
/// error colour, changed sets as old → new.
class CoachExerciseDiffRow extends StatelessWidget {
  final ExerciseDiff exercise;

  const CoachExerciseDiffRow({required this.exercise, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final error = errorColor(context);
    final (nameColor, change) = switch (exercise.kind) {
      DiffKind.added => (accentColor(context), 'Added'),
      DiffKind.removed => (error, 'Removed'),
      DiffKind.changed => (textPrimaryColor(context), 'Changed'),
      DiffKind.unchanged => (secondary, 'Unchanged'),
    };
    final removed = exercise.kind == DiffKind.removed;
    final sets = switch (exercise.kind) {
      DiffKind.added => formatCoachSets(exercise.after),
      DiffKind.removed => formatCoachSets(exercise.before),
      _ when exercise.setsChanged =>
        '${formatCoachSets(exercise.before)} → '
            '${formatCoachSets(exercise.after)}',
      _ => formatCoachSets(exercise.after),
    };
    final notes = <String>[
      if (exercise.moved) 'Moved',
      if (exercise.noteChanged && exercise.noteAfter == null) 'Note removed',
      if (exercise.noteChanged && exercise.noteAfter != null)
        'Note: ${exercise.noteAfter}',
    ];

    return MergeSemantics(
      child: Semantics(
        label: [
          '$change: ${exercise.name}',
          if (exercise.custom) 'custom exercise',
          sets,
          ...notes,
        ].join(', '),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      exercise.name,
                      style: textTheme.bodyLarge?.copyWith(
                        color: nameColor,
                        fontWeight:
                            exercise.kind == DiffKind.unchanged
                                ? FontWeight.w500
                                : FontWeight.w600,
                        decoration: removed ? TextDecoration.lineThrough : null,
                        decorationColor: error,
                      ),
                    ),
                  ),
                  if (exercise.custom) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const _CustomLabel(),
                  ],
                ],
              ),
              Text(
                sets,
                style: textTheme.bodySmall?.copyWith(
                  color: removed ? error : secondary,
                  decoration: removed ? TextDecoration.lineThrough : null,
                  decorationColor: error,
                ),
              ),
              for (final note in notes)
                Text(
                  note,
                  style: textTheme.bodySmall?.copyWith(color: secondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomLabel extends StatelessWidget {
  const _CustomLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.badge,
      ),
      child: Text(
        'Custom',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: textSecondaryColor(context)),
      ),
    );
  }
}
