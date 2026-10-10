import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/coach_proposal.dart';
import '../../services/coach/proposal_diff.dart';
import '../../services/coach/proposal_selection.dart';
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

/// One affected plan on the review screen: a checkbox for the whole plan,
/// then one checkbox per change in it.
class CoachPlanReviewCard extends StatelessWidget {
  final PlanDiff plan;
  final ProposalSelection selection;

  /// Called after the selection changed, so the screen can rebuild. Null
  /// while applying, which disables every checkbox.
  final VoidCallback? onChanged;

  const CoachPlanReviewCard({
    required this.plan,
    required this.selection,
    required this.onChanged,
    super.key,
  });

  VoidCallback? _toggle(VoidCallback change) {
    final onChanged = this.onChanged;
    if (onChanged == null) return null;
    return () {
      change();
      onChanged();
    };
  }

  @override
  Widget build(BuildContext context) {
    final changes = selection.changesIn(plan);
    final state = selection.planState(plan);
    final removed = plan.kind == DiffKind.removed;
    final added = plan.kind == DiffKind.added;
    final unchanged = [
      for (final exercise in plan.exercises)
        if (exercise.kind == DiffKind.unchanged) exercise.name,
    ];

    return Material(
      color: surfaceColor(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CheckRow(
            value: state,
            onChanged: _toggle(
              () => selection.setPlanKept(plan, state != true),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: _PlanHeader(plan: plan, selection: selection),
          ),
          if (!removed)
            for (final (index, change) in changes.indexed) ...[
              _Hairline(indent: index > 0),
              _CheckRow(
                value: selection.isKept(change),
                onChanged: _toggle(
                  () => selection.setKept(change, !selection.isKept(change)),
                ),
                child: _ChangeDetails(
                  change: change,
                  kept: selection.isKept(change),
                  showVerb: !added,
                ),
              ),
            ],
          if (unchanged.isNotEmpty && !removed && !added) ...[
            const _Hairline(indent: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'Unchanged: ${unchanged.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanHeader extends StatelessWidget {
  final PlanDiff plan;
  final ProposalSelection selection;

  const _PlanHeader({required this.plan, required this.selection});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final changes = selection.changesIn(plan);
    final kept = changes.where(selection.isKept).length;
    final (tag, tagColor) = switch (plan.kind) {
      DiffKind.added => ('New plan', accentColor(context)),
      DiffKind.removed => ('Delete plan', errorColor(context)),
      _ => ('Edited', null),
    };
    final count = plan.exercises.length;
    final exercisesLabel = count == 1 ? '1 exercise' : '$count exercises';
    final detail = switch (plan.kind) {
      DiffKind.removed =>
        'Deletes the plan and its $exercisesLabel. Logged workouts '
            "aren't changed.",
      DiffKind.added when kept == changes.length => exercisesLabel,
      DiffKind.added => '$kept of $exercisesLabel selected',
      _ when kept == changes.length =>
        changes.length == 1 ? '1 change' : '${changes.length} changes',
      _ => '$kept of ${changes.length} changes selected',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                plan.name,
                style: textTheme.titleMedium?.copyWith(
                  color: textPrimaryColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Tag(label: tag, color: tagColor),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(detail, style: textTheme.bodySmall?.copyWith(color: secondary)),
        if (plan.kind == DiffKind.removed) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            [for (final exercise in plan.exercises) exercise.name].join(', '),
            style: textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ],
      ],
    );
  }
}

/// What one change does: a verb line, the exercise or setting it touches,
/// and its before and after values.
class _ChangeDetails extends StatelessWidget {
  final ReviewChange change;
  final bool kept;

  /// False inside a new plan, where every row is an addition.
  final bool showVerb;

  const _ChangeDetails({
    required this.change,
    required this.kept,
    required this.showVerb,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primary = textPrimaryColor(context);
    final secondary = textSecondaryColor(context);
    final plan = change.plan;
    final exercise = change.exercise;

    final (verb, icon, verbColor) = switch (change.kind) {
      ReviewChangeKind.rename => (
        'Rename',
        LucideIcons.textCursorInput,
        primary,
      ),
      ReviewChangeKind.reorder => ('Reorder', LucideIcons.arrowUpDown, primary),
      ReviewChangeKind.removePlan => (
        'Delete',
        LucideIcons.minus,
        errorColor(context),
      ),
      ReviewChangeKind.exercise => switch (exercise!.kind) {
        DiffKind.added => ('Add', LucideIcons.plus, accentColor(context)),
        DiffKind.removed => ('Remove', LucideIcons.minus, errorColor(context)),
        _ => ('Change', LucideIcons.pencil, primary),
      },
    };
    final title = switch (change.kind) {
      ReviewChangeKind.rename => 'Plan name',
      ReviewChangeKind.reorder => 'Exercise order',
      _ => exercise?.name ?? plan.name,
    };

    final details = <Widget>[];
    if (exercise != null) {
      switch (exercise.kind) {
        case DiffKind.added:
          details.add(_Value(formatCoachSets(exercise.after), kept: kept));
          if (exercise.noteAfter case final note?) {
            details.add(_Value('Note: $note', kept: kept));
          }
        case DiffKind.removed:
          details.add(_Value(formatCoachSets(exercise.before), kept: false));
        case DiffKind.changed || DiffKind.unchanged:
          if (exercise.setsChanged) {
            details.add(
              _BeforeAfter(
                before: formatCoachSets(exercise.before),
                after: formatCoachSets(exercise.after),
                kept: kept,
              ),
            );
          }
          if (exercise.noteChanged) {
            details.add(
              _BeforeAfter(
                label: 'Note',
                before: exercise.noteBefore ?? 'None',
                after: exercise.noteAfter ?? 'None',
                kept: kept,
              ),
            );
          }
      }
    } else if (change.kind == ReviewChangeKind.rename) {
      details.add(
        _BeforeAfter(before: plan.previousName!, after: plan.name, kept: kept),
      );
    } else if (change.kind == ReviewChangeKind.reorder) {
      details.add(
        _BeforeAfter(
          before: [
            for (final exercise in plan.existing!.exercises) exercise.name,
          ].join(', '),
          after: [
            for (final exercise in plan.proposed!.exercises) exercise.name,
          ].join(', '),
          kept: kept,
        ),
      );
    }

    final skipped = Text(
      'Skipped',
      style: textTheme.labelMedium?.copyWith(color: secondary),
    );
    final name = Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: textTheme.bodyLarge?.copyWith(
                    color: kept ? primary : secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (exercise?.custom ?? false) ...[
                const SizedBox(width: AppSpacing.sm),
                const _Tag(label: 'Custom'),
              ],
            ],
          ),
        ),
        if (!showVerb && !kept) ...[
          const SizedBox(width: AppSpacing.sm),
          skipped,
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showVerb) ...[
          Row(
            children: [
              Icon(icon, size: 14, color: kept ? verbColor : secondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                verb,
                style: textTheme.labelMedium?.copyWith(
                  color: kept ? verbColor : secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!kept) ...[const Spacer(), skipped],
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        name,
        for (final detail in details) ...[
          const SizedBox(height: AppSpacing.xxs),
          detail,
        ],
      ],
    );
  }
}

/// A value line under a change.
class _Value extends StatelessWidget {
  final String text;
  final bool kept;

  const _Value(this.text, {required this.kept});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: kept ? textPrimaryColor(context) : textSecondaryColor(context),
      ),
    );
  }
}

/// `Before` and `After` on their own lines, so the eye compares like with
/// like instead of parsing one long `old → new` string.
class _BeforeAfter extends StatelessWidget {
  final String? label;
  final String before;
  final String after;
  final bool kept;

  const _BeforeAfter({
    required this.before,
    required this.after,
    required this.kept,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primary = textPrimaryColor(context);
    final secondary = textSecondaryColor(context);
    final label = this.label;

    Widget line(String name, String value, {required bool strong}) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            name,
            style: textTheme.labelMedium?.copyWith(color: secondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: strong ? primary : secondary,
              fontWeight: strong ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Text(label, style: textTheme.labelMedium?.copyWith(color: secondary)),
        line('Before', before, strong: !kept),
        line('After', after, strong: kept),
      ],
    );
  }
}

/// A checkbox row. The whole row toggles, and its semantics merge into one
/// node so a screen reader reads the change with its checked state.
class _CheckRow extends StatelessWidget {
  /// Null shows the mixed state of a partly selected plan.
  final bool? value;
  final VoidCallback? onChanged;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.md,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged,
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                tristate: value == null,
                onChanged: onChanged == null ? null : (_) => onChanged!(),
                activeColor: accentFillColor(context),
                checkColor: onAccentColor(context),
                visualDensity: VisualDensity.compact,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.badge,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rule across the card. Between two changes it starts at the text, so
/// the checkboxes read as one column; under the plan header it runs edge to
/// edge.
class _Hairline extends StatelessWidget {
  final bool indent;

  const _Hairline({this.indent = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: indent ? 52 : 0),
      height: 1,
      color: borderColor(context),
    );
  }
}

/// A small outlined label: a plan's status, or `Custom` on an exercise.
class _Tag extends StatelessWidget {
  final String label;
  final Color? color;

  const _Tag({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: this.color ?? borderColor(context)),
        borderRadius: AppRadius.badge,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
