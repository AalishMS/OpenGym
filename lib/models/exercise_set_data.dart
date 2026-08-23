/// One prescribed set while the plan editor is open.
///
/// Not a Hive type: this is the editor's working copy, converted to
/// [SetTemplate] on save and hydrated back from it on open. Kept separate so a
/// half-finished edit can never reach the box.
class ExerciseSetData {
  final int reps;
  final double weight;

  ExerciseSetData({required this.reps, required this.weight});

  ExerciseSetData copyWith({int? reps, double? weight}) {
    return ExerciseSetData(
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
    );
  }
}
