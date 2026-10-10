import '../../models/coach_proposal.dart';
import '../../models/workout_plan.dart';
import 'proposal_diff.dart';
import 'proposal_validator.dart';

enum ReviewChangeKind {
  /// An exercise added, removed, or changed.
  exercise,

  /// A plan's new name.
  rename,

  /// A new order for the exercises a plan keeps.
  reorder,

  /// Removing a whole plan.
  removePlan,
}

/// One change on the review screen that the user can keep or skip. Compared
/// by identity: a [ProposalSelection] creates each one once.
class ReviewChange {
  final ReviewChangeKind kind;
  final PlanDiff plan;

  /// Set for [ReviewChangeKind.exercise] only.
  final ExerciseDiff? exercise;

  ReviewChange._(this.kind, this.plan, [this.exercise]);
}

/// Which changes of a proposal the user keeps. Every change starts kept.
///
/// [resolve] turns the kept changes back into a [ValidatedProposal], so
/// `CoachApplier` writes a partial proposal exactly as it writes a whole one,
/// with the same stale check and rollback.
class ProposalSelection {
  final ProposalDiff diff;

  /// Every change, plan by plan, in review order.
  final List<ReviewChange> changes;
  final Map<PlanDiff, List<ReviewChange>> _byPlan;
  final Set<ReviewChange> _skipped = {};

  factory ProposalSelection(ProposalDiff diff) => ProposalSelection._(diff, {
    for (final plan in diff.plans)
      if (plan.kind != DiffKind.unchanged) plan: _changesOf(plan),
  });

  ProposalSelection._(this.diff, this._byPlan)
    : changes = List.unmodifiable([
        for (final changes in _byPlan.values) ...changes,
      ]);

  static List<ReviewChange> _changesOf(PlanDiff plan) {
    if (plan.kind == DiffKind.removed) {
      return [ReviewChange._(ReviewChangeKind.removePlan, plan)];
    }
    return [
      if (plan.renamed) ReviewChange._(ReviewChangeKind.rename, plan),
      for (final exercise in plan.exercises)
        if (exercise.kind != DiffKind.unchanged)
          ReviewChange._(ReviewChangeKind.exercise, plan, exercise),
      if (plan.reordered) ReviewChange._(ReviewChangeKind.reorder, plan),
    ];
  }

  /// The plans with something to review, in proposal order.
  Iterable<PlanDiff> get plans => _byPlan.keys;

  List<ReviewChange> changesIn(PlanDiff plan) => _byPlan[plan] ?? const [];

  bool isKept(ReviewChange change) => !_skipped.contains(change);

  void setKept(ReviewChange change, bool keep) {
    if (keep) {
      _skipped.remove(change);
    } else {
      _skipped.add(change);
    }
  }

  /// True when every change in [plan] is kept, false when none is, and null
  /// when some are.
  bool? planState(PlanDiff plan) {
    final changes = changesIn(plan);
    final kept = changes.where(isKept).length;
    if (kept == changes.length) return true;
    return kept == 0 ? false : null;
  }

  void setPlanKept(PlanDiff plan, bool keep) {
    for (final change in changesIn(plan)) {
      setKept(change, keep);
    }
  }

  void setAllKept(bool keep) {
    if (keep) {
      _skipped.clear();
    } else {
      _skipped.addAll(changes);
    }
  }

  int get keptCount => changes.length - _skipped.length;

  bool get keepsAll => _skipped.isEmpty;

  /// Why the kept changes can't be applied together, written for the user.
  /// Empty when they can, or when nothing is kept.
  List<String> get problems {
    if (keptCount == 0) return const [];
    final resolved = resolve();
    final snapshot = resolved.snapshot;
    final problems = <String>[
      for (final plan in resolved.plans)
        if (plan.exercises.isEmpty)
          '${plan.name} would have no exercises. Keep at least one.',
    ];

    final removedIds = {for (final plan in resolved.removedPlans) plan.id};
    final editedIds = {
      for (final plan in resolved.plans)
        if (plan.existing != null) plan.existing!.id,
    };
    final activeSplit = resolved.target == CoachTarget.activeSplit;
    if (activeSplit) {
      final count =
          snapshot.plans.length -
          removedIds.length +
          resolved.plans.where((plan) => plan.isNew).length;
      if (count < 1) {
        problems.add('The split would have no plans. Keep at least one.');
      } else if (count > ProposalValidator.maxPlansInSplit) {
        problems.add(
          'The split would have $count plans, and the most is '
          '${ProposalValidator.maxPlansInSplit}. Skip a new plan or keep a '
          'removal.',
        );
      }
    }

    final seen = <String>{};
    final repeated = <String>{};
    for (final name in [
      if (activeSplit)
        for (final plan in snapshot.plans)
          if (!editedIds.contains(plan.id) && !removedIds.contains(plan.id))
            plan.name.trim(),
      for (final plan in resolved.plans) plan.name.trim(),
    ]) {
      if (!seen.add(name.toLowerCase()) && repeated.add(name.toLowerCase())) {
        problems.add('Two plans would be named $name. Keep or skip both.');
      }
    }
    return problems;
  }

  /// The proposal with only the kept changes. A plan with nothing kept is
  /// left out, so it isn't written at all.
  ValidatedProposal resolve() {
    final source = diff.proposal;
    final written = <CoachPlan>[];
    final removed = <WorkoutPlan>[];
    for (final plan in plans) {
      switch (plan.kind) {
        case DiffKind.removed:
          if (isKept(changesIn(plan).single)) removed.add(plan.existing!);
        case DiffKind.added:
          final exercises = [
            for (final change in changesIn(plan))
              if (isKept(change)) change.exercise!.proposed!,
          ];
          if (exercises.isNotEmpty) {
            written.add(
              CoachPlan(existing: null, name: plan.name, exercises: exercises),
            );
          }
        case DiffKind.changed:
          if (planState(plan) != false) written.add(_editedPlan(plan));
        case DiffKind.unchanged:
          break;
      }
    }
    return ValidatedProposal(
      target: source.target,
      newSplitName: source.newSplitName,
      plans: written,
      removedPlans: removed,
      snapshot: source.snapshot,
    );
  }

  CoachPlan _editedPlan(PlanDiff plan) {
    final byExercise = <ExerciseDiff, ReviewChange>{};
    ReviewChange? rename;
    ReviewChange? reorder;
    for (final change in changesIn(plan)) {
      switch (change.kind) {
        case ReviewChangeKind.exercise:
          byExercise[change.exercise!] = change;
        case ReviewChangeKind.rename:
          rename = change;
        case ReviewChangeKind.reorder:
          reorder = change;
        case ReviewChangeKind.removePlan:
          break;
      }
    }

    bool keeps(ExerciseDiff exercise) {
      final change = byExercise[exercise];
      return change == null || isKept(change);
    }

    CoachExercise? result(ExerciseDiff exercise) => switch (exercise.kind) {
      DiffKind.unchanged => CoachExercise.stored(exercise.original!),
      DiffKind.changed =>
        keeps(exercise)
            ? exercise.proposed!
            : CoachExercise.stored(exercise.original!),
      DiffKind.added => keeps(exercise) ? exercise.proposed! : null,
      DiffKind.removed =>
        keeps(exercise) ? null : CoachExercise.stored(exercise.original!),
    };

    final ordered = <(ExerciseDiff, CoachExercise)>[];
    final stored = [
      for (final exercise in plan.exercises)
        if (exercise.originalIndex != null) exercise,
    ]..sort((a, b) => a.originalIndex!.compareTo(b.originalIndex!));

    if (reorder == null || isKept(reorder)) {
      // The proposed order. A removal the user skipped goes back after the
      // exercise it followed in the stored plan.
      for (final exercise in plan.exercises) {
        if (exercise.kind == DiffKind.removed) continue;
        if (result(exercise) case final kept?) ordered.add((exercise, kept));
      }
      for (final exercise in stored) {
        if (exercise.kind != DiffKind.removed) continue;
        final kept = result(exercise);
        if (kept == null) continue;
        var at = 0;
        var anchor = -1;
        for (var index = 0; index < ordered.length; index++) {
          final before = ordered[index].$1.originalIndex;
          if (before != null &&
              before < exercise.originalIndex! &&
              before > anchor) {
            anchor = before;
            at = index + 1;
          }
        }
        ordered.insert(at, (exercise, kept));
      }
    } else {
      // The stored order. A kept addition goes after the exercise it
      // followed in the proposal.
      for (final exercise in stored) {
        if (result(exercise) case final kept?) ordered.add((exercise, kept));
      }
      ExerciseDiff? anchor;
      for (final exercise in plan.exercises) {
        if (exercise.kind == DiffKind.removed) continue;
        if (exercise.kind != DiffKind.added) {
          anchor = exercise;
          continue;
        }
        final kept = result(exercise);
        if (kept == null) continue;
        final at =
            anchor == null
                ? 0
                : ordered.indexWhere((entry) => entry.$1 == anchor) + 1;
        ordered.insert(at, (exercise, kept));
        anchor = exercise;
      }
    }

    final renameKept = rename != null && isKept(rename);
    return CoachPlan(
      existing: plan.existing,
      name: renameKept || rename == null ? plan.name : plan.existing!.name,
      exercises: [for (final (_, exercise) in ordered) exercise],
    );
  }
}
