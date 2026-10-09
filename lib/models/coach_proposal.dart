import 'exercise_template.dart';
import 'set_template.dart';
import 'workout_plan.dart';

/// Reps the plan editor shows for a set that has no stored target. The Coach
/// pads missing targets the same way, so a plan it echoes back unchanged
/// still matches what the user sees.
const int kCoachDefaultTargetReps = 8;

/// One prescribed set as the Coach reads and writes it. Always kilograms:
/// Hive stores kg, and set entry and the plan editor show kg.
class CoachSet {
  final int reps;
  final double kg;

  const CoachSet({required this.reps, required this.kg});

  Map<String, dynamic> toJson() => {'reps': reps, 'kg': coachNumber(kg)};

  SetTemplate toTemplate() => SetTemplate(reps: reps, weight: kg);

  @override
  bool operator ==(Object other) =>
      other is CoachSet && other.reps == reps && other.kg == kg;

  @override
  int get hashCode => Object.hash(reps, kg);

  @override
  String toString() => '${reps}x${coachNumber(kg)}';
}

/// A whole number as an int, anything else rounded to two decimals, so the
/// JSON the model reads says `60`, not `60.0`.
num coachNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt();
  return double.parse(value.toStringAsFixed(2));
}

/// [template]'s sets as the plan editor displays them.
List<CoachSet> coachSetsOf(ExerciseTemplate template) => [
  for (var index = 0; index < template.sets; index++)
    CoachSet(
      reps: template.targetAt(index)?.reps ?? kCoachDefaultTargetReps,
      kg: template.targetAt(index)?.weight ?? 0,
    ),
];

/// A note as the Coach compares it: trimmed, with blank meaning none.
String? coachNote(String? note) {
  final trimmed = note?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// What the Coach saw when it was asked: the active split's plans behind the
/// `p1…pN` refs, and the version of each, so a proposal can be validated
/// against the same plans and refused if they changed before it is applied.
class CoachSnapshot {
  final String splitId;
  final String splitName;

  /// The split's live plans in position order; `plans[i]` is ref `p{i+1}`.
  final List<WorkoutPlan> plans;

  /// Each plan's `updatedAt` when the snapshot was taken, keyed by plan ID.
  final Map<String, DateTime?> planVersions;

  /// Names of every live split, this one included.
  final List<String> splitNames;
  final int maxSplits;

  /// Exercise names used in this split that aren't in the library.
  final List<String> customExercises;

  CoachSnapshot({
    required this.splitId,
    required this.splitName,
    required List<WorkoutPlan> plans,
    required List<String> splitNames,
    required this.maxSplits,
    required List<String> customExercises,
  }) : plans = List.unmodifiable(plans),
       planVersions = Map.unmodifiable({
         for (final plan in plans)
           if (plan.id != null) plan.id!: plan.updatedAt,
       }),
       splitNames = List.unmodifiable(splitNames),
       customExercises = List.unmodifiable(customExercises);

  static String refAt(int index) => 'p${index + 1}';

  WorkoutPlan? planForRef(String ref) {
    final match = RegExp(r'^p(\d+)$').firstMatch(ref.trim().toLowerCase());
    if (match == null) return null;
    final index = int.parse(match.group(1)!) - 1;
    return index >= 0 && index < plans.length ? plans[index] : null;
  }
}

class CoachExercise {
  /// Library casing for library exercises; otherwise the name as given.
  final String name;
  final List<CoachSet> sets;
  final String? note;

  /// Not in the exercise library. The review screen labels these.
  final bool custom;

  CoachExercise({
    required this.name,
    required List<CoachSet> sets,
    this.note,
    this.custom = false,
  }) : sets = List.unmodifiable(sets);

  ExerciseTemplate toTemplate() => ExerciseTemplate(
    name: name,
    sets: sets.length,
    setTargets: [for (final set in sets) set.toTemplate()],
    note: note,
  );
}

class CoachPlan {
  /// The plan this replaces, or null for a new plan.
  final WorkoutPlan? existing;
  final String name;
  final List<CoachExercise> exercises;

  CoachPlan({
    required this.existing,
    required this.name,
    required List<CoachExercise> exercises,
  }) : exercises = List.unmodifiable(exercises);

  bool get isNew => existing == null;
}

enum CoachTarget { activeSplit, newSplit }

/// A proposal that passed `ProposalValidator`. Nothing in it is written yet.
class ValidatedProposal {
  final CoachTarget target;

  /// Set only for [CoachTarget.newSplit].
  final String? newSplitName;
  final List<CoachPlan> plans;
  final List<WorkoutPlan> removedPlans;
  final CoachSnapshot snapshot;

  ValidatedProposal({
    required this.target,
    required this.newSplitName,
    required List<CoachPlan> plans,
    required List<WorkoutPlan> removedPlans,
    required this.snapshot,
  }) : plans = List.unmodifiable(plans),
       removedPlans = List.unmodifiable(removedPlans);
}

/// One validated model answer: chat text, plus a proposal when the Coach
/// suggests a change.
class CoachReply {
  final String reply;
  final ValidatedProposal? proposal;

  const CoachReply({required this.reply, this.proposal});
}
