/// How a built-in exercise is measured.
enum ExerciseKind {
  /// Weight × reps. Also the kind of every custom or unknown exercise.
  weighted,

  /// Normally done without added load. Statistics still decide bodyweight
  /// from the data (a set at weight 0), so this is a hint for the catalog.
  bodyweight,

  /// A hold. Its sets store seconds in `Set.reps`.
  timed,
}

/// One built-in exercise and how it is measured.
class LibraryExercise {
  final String name;
  final ExerciseKind kind;

  const LibraryExercise(this.name) : kind = ExerciseKind.weighted;
  const LibraryExercise.bodyweight(this.name) : kind = ExerciseKind.bodyweight;
  const LibraryExercise.timed(this.name) : kind = ExerciseKind.timed;
}

class ExerciseLibrary {
  /// The catalog, by category, in picker order.
  static const Map<String, List<LibraryExercise>> catalog = {
    'Chest': [
      LibraryExercise('Bench Press'),
      LibraryExercise('Incline Bench Press'),
      LibraryExercise('Decline Bench Press'),
      LibraryExercise('Dumbbell Press'),
      LibraryExercise('Incline Dumbbell Press'),
      LibraryExercise('Dumbbell Fly'),
      LibraryExercise('Cable Fly'),
      LibraryExercise('Machine Chest Press'),
      LibraryExercise('Machine Incline Chest Press'),
      LibraryExercise('Machine Chest Fly'),
      LibraryExercise.bodyweight('Push-ups'),
      LibraryExercise.bodyweight('Chest Dips'),
      LibraryExercise('Cable Crossover'),
    ],
    'Back': [
      LibraryExercise('Deadlift'),
      LibraryExercise('Barbell Row'),
      LibraryExercise('Dumbbell Row'),
      LibraryExercise('Lat Pulldown'),
      LibraryExercise.bodyweight('Pull-ups'),
      LibraryExercise.bodyweight('Chin-ups'),
      LibraryExercise('Seated Cable Row'),
      LibraryExercise('T-Bar Row'),
      LibraryExercise('Face Pull'),
      LibraryExercise('Single Arm Row'),
    ],
    'Shoulders': [
      LibraryExercise('Overhead Press'),
      LibraryExercise('Dumbbell Shoulder Press'),
      LibraryExercise('Machine Shoulder Press'),
      LibraryExercise('Lateral Raise'),
      LibraryExercise('Front Raise'),
      LibraryExercise('Rear Delt Fly'),
      LibraryExercise('Arnold Press'),
      LibraryExercise('Shrugs'),
      LibraryExercise('Upright Row'),
      LibraryExercise('Cable Lateral Raise'),
      LibraryExercise('Reverse Fly'),
    ],
    'Arms': [
      LibraryExercise('Bicep Curl'),
      LibraryExercise('Hammer Curl'),
      LibraryExercise('Preacher Curl'),
      LibraryExercise('Concentration Curl'),
      LibraryExercise('Cable Curl'),
      LibraryExercise('Bayesian Curl'),
      LibraryExercise('Tricep Pushdown'),
      LibraryExercise('Skull Crusher'),
      LibraryExercise.bodyweight('Tricep Dips'),
      LibraryExercise('Overhead Tricep Extension'),
      LibraryExercise('Close Grip Bench Press'),
    ],
    'Legs': [
      LibraryExercise('Squat'),
      LibraryExercise('Front Squat'),
      LibraryExercise('Leg Press'),
      LibraryExercise('Hack Squat'),
      LibraryExercise('Lunges'),
      LibraryExercise('Bulgarian Split Squat'),
      LibraryExercise('Leg Extension'),
      LibraryExercise('Leg Curl'),
      LibraryExercise('Romanian Deadlift'),
      LibraryExercise('Calf Raise'),
      LibraryExercise('Seated Calf Raise'),
      LibraryExercise('Hip Thrust'),
      LibraryExercise.bodyweight('Glute Bridge'),
    ],
    'Core': [
      LibraryExercise.timed('Plank'),
      LibraryExercise.bodyweight('Crunches'),
      LibraryExercise.bodyweight('Russian Twist'),
      LibraryExercise.bodyweight('Leg Raise'),
      LibraryExercise.bodyweight('Hanging Leg Raise'),
      LibraryExercise('Cable Ab Crunch'),
      LibraryExercise.bodyweight('Bicycle Crunches'),
      LibraryExercise.bodyweight('Mountain Climbers'),
      LibraryExercise.bodyweight('Ab Wheel Rollout'),
      LibraryExercise.bodyweight('Dead Bug'),
      LibraryExercise.bodyweight('Bird Dog'),
      LibraryExercise.timed('Side Plank'),
    ],
  };

  /// Exercise names by category, in picker order.
  static final Map<String, List<String>> exercisesByCategory = Map.unmodifiable({
    for (final MapEntry(key: category, value: exercises) in catalog.entries)
      category: List<String>.unmodifiable([
        for (final exercise in exercises) exercise.name,
      ]),
  });

  static List<String> get allExercises {
    final all = <String>[];
    for (var exercises in exercisesByCategory.values) {
      all.addAll(exercises);
    }
    all.sort();
    return all;
  }

  static Map<String, List<String>> get categories => exercisesByCategory;

  static List<String> get categoryNames => exercisesByCategory.keys.toList();

  static final Map<String, (String, LibraryExercise)> _index = {
    for (final MapEntry(key: category, value: exercises) in catalog.entries)
      for (final exercise in exercises)
        _key(exercise.name): (category, exercise),
  };

  /// Exercise identity: trimmed, case-insensitive, repeated spaces ignored.
  static String _key(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// How [name] is measured. Custom and unknown names are weighted.
  static ExerciseKind kindOf(String name) =>
      _index[_key(name)]?.$2.kind ?? ExerciseKind.weighted;

  /// Whether [name] is a hold whose sets store seconds instead of reps.
  static bool isTimed(String name) => kindOf(name) == ExerciseKind.timed;

  /// The catalog category of [name], or null for a custom exercise.
  static String? categoryOf(String name) => _index[_key(name)]?.$1;
}
