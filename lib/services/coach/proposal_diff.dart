import '../../models/coach_proposal.dart';
import '../../models/exercise_template.dart';
import '../../models/workout_plan.dart';

enum DiffKind { added, removed, changed, unchanged }

/// One exercise in a reviewed plan. [before] is empty for an added exercise
/// and [after] is empty for a removed one.
class ExerciseDiff {
  final DiffKind kind;
  final String name;
  final List<CoachSet> before;
  final List<CoachSet> after;
  final String? noteBefore;
  final String? noteAfter;

  /// Its position among the exercises both versions share changed.
  final bool moved;

  /// Not in the exercise library; the review screen labels these.
  final bool custom;

  /// The stored exercise, null for an added one. Declining a change keeps it
  /// exactly as stored.
  final ExerciseTemplate? original;

  /// Its index in the stored plan, null for an added exercise.
  final int? originalIndex;

  /// What the Coach proposed, null for a removed exercise.
  final CoachExercise? proposed;

  ExerciseDiff({
    required this.kind,
    required this.name,
    required List<CoachSet> before,
    required List<CoachSet> after,
    this.noteBefore,
    this.noteAfter,
    this.moved = false,
    this.custom = false,
    this.original,
    this.originalIndex,
    this.proposed,
  }) : before = List.unmodifiable(before),
       after = List.unmodifiable(after);

  bool get setsChanged => !_sameSets(before, after);

  bool get noteChanged => noteBefore != noteAfter;
}

class PlanDiff {
  final DiffKind kind;

  /// The plan's name after applying, or the removed plan's name.
  final String name;

  /// The old name, only when the plan is renamed.
  final String? previousName;

  /// The stored plan, null for an added one.
  final WorkoutPlan? existing;

  /// What the Coach proposed, null for a removed plan.
  final CoachPlan? proposed;
  final List<ExerciseDiff> exercises;

  PlanDiff({
    required this.kind,
    required this.name,
    required this.existing,
    required List<ExerciseDiff> exercises,
    this.proposed,
    this.previousName,
  }) : exercises = List.unmodifiable(exercises);

  bool get renamed => previousName != null;

  /// Some exercise kept by both versions changed position.
  bool get reordered => exercises.any((exercise) => exercise.moved);
}

/// What applying a [ValidatedProposal] would change, for the review screen
/// and the proposal card's summary.
class ProposalDiff {
  final ValidatedProposal proposal;

  /// Proposed plans in proposal order, then removed plans.
  final List<PlanDiff> plans;

  ProposalDiff._(this.proposal, List<PlanDiff> plans)
    : plans = List.unmodifiable(plans);

  int count(DiffKind kind) => plans.where((plan) => plan.kind == kind).length;

  bool get hasChanges => plans.any((plan) => plan.kind != DiffKind.unchanged);

  static ProposalDiff compute(ValidatedProposal proposal) =>
      ProposalDiff._(proposal, [
        for (final plan in proposal.plans) _planDiff(plan),
        for (final plan in proposal.removedPlans)
          PlanDiff(
            kind: DiffKind.removed,
            name: plan.name,
            existing: plan,
            exercises: [
              for (var index = 0; index < plan.exercises.length; index++)
                _removed(plan.exercises[index], index),
            ],
          ),
      ]);

  static PlanDiff _planDiff(CoachPlan plan) {
    final existing = plan.existing;
    if (existing == null) {
      return PlanDiff(
        kind: DiffKind.added,
        name: plan.name,
        existing: null,
        proposed: plan,
        exercises: [for (final exercise in plan.exercises) _added(exercise)],
      );
    }

    final exercises = _exerciseDiffs(existing.exercises, plan.exercises);
    final renamed = existing.name.trim() != plan.name;
    final changed =
        renamed ||
        exercises.any(
          (exercise) => exercise.kind != DiffKind.unchanged || exercise.moved,
        );
    return PlanDiff(
      kind: changed ? DiffKind.changed : DiffKind.unchanged,
      name: plan.name,
      previousName: renamed ? existing.name : null,
      existing: existing,
      proposed: plan,
      exercises: exercises,
    );
  }

  /// Pairs exercises by name (ignoring case), occurrence by occurrence, so a
  /// plan that lists one exercise twice still pairs up. Unpaired old exercises
  /// are listed as removed after the proposed ones.
  static List<ExerciseDiff> _exerciseDiffs(
    List<ExerciseTemplate> before,
    List<CoachExercise> after,
  ) {
    final unpaired = <String, List<int>>{};
    for (var index = 0; index < before.length; index++) {
      unpaired.putIfAbsent(_key(before[index].name), () => []).add(index);
    }
    final pairedIndex = <int?>[
      for (final exercise in after)
        () {
          final queue = unpaired[_key(exercise.name)];
          return queue == null || queue.isEmpty ? null : queue.removeAt(0);
        }(),
    ];
    final stayed = _longestIncreasing([...pairedIndex.whereType<int>()]);

    return [
      for (var index = 0; index < after.length; index++)
        if (pairedIndex[index] case final oldIndex?)
          _paired(
            before[oldIndex],
            oldIndex,
            after[index],
            moved: !stayed.contains(oldIndex),
          )
        else
          _added(after[index]),
      for (final indices in unpaired.values)
        for (final oldIndex in indices) _removed(before[oldIndex], oldIndex),
    ];
  }

  static ExerciseDiff _paired(
    ExerciseTemplate before,
    int beforeIndex,
    CoachExercise after, {
    required bool moved,
  }) {
    final beforeSets = coachSetsOf(before);
    final noteBefore = coachNote(before.note);
    final same = _sameSets(beforeSets, after.sets) && noteBefore == after.note;
    return ExerciseDiff(
      kind: same ? DiffKind.unchanged : DiffKind.changed,
      name: after.name,
      before: beforeSets,
      after: after.sets,
      noteBefore: noteBefore,
      noteAfter: after.note,
      moved: moved,
      custom: after.custom,
      original: before,
      originalIndex: beforeIndex,
      proposed: after,
    );
  }

  static ExerciseDiff _added(CoachExercise exercise) => ExerciseDiff(
    kind: DiffKind.added,
    name: exercise.name,
    before: const [],
    after: exercise.sets,
    noteAfter: exercise.note,
    custom: exercise.custom,
    proposed: exercise,
  );

  static ExerciseDiff _removed(ExerciseTemplate exercise, int index) =>
      ExerciseDiff(
        kind: DiffKind.removed,
        name: exercise.name,
        before: coachSetsOf(exercise),
        after: const [],
        noteBefore: coachNote(exercise.note),
        original: exercise,
        originalIndex: index,
      );

  /// The values of a longest strictly increasing subsequence. Exercises in it
  /// kept their relative order; the rest count as moved, so moving one
  /// exercise to the top marks one exercise, not every one it passed.
  static Set<int> _longestIncreasing(List<int> values) {
    if (values.isEmpty) return {};
    final tails = <int>[];
    final previous = List<int>.filled(values.length, -1);
    for (var index = 0; index < values.length; index++) {
      var low = 0;
      var high = tails.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (values[tails[mid]] < values[index]) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      if (low > 0) previous[index] = tails[low - 1];
      if (low == tails.length) {
        tails.add(index);
      } else {
        tails[low] = index;
      }
    }
    final result = <int>{};
    for (var index = tails.last; index != -1; index = previous[index]) {
      result.add(values[index]);
    }
    return result;
  }

  static String _key(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

bool _sameSets(List<CoachSet> a, List<CoachSet> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
