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

class ExerciseWithSets {
  final String name;
  final List<ExerciseSetData> sets;

  ExerciseWithSets({required this.name, required this.sets});

  ExerciseWithSets copyWith({String? name, List<ExerciseSetData>? sets}) {
    return ExerciseWithSets(
      name: name ?? this.name,
      sets: sets ?? this.sets,
    );
  }
}
