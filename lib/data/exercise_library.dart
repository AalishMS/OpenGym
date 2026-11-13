import '../models/exercise_definition.dart';

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
  // These IDs are permanent. Renaming a label must never change its ID.
  static const idsByName = <String, String>{
    'Bench Press': 'builtin:bench-press',
    'Incline Bench Press': 'builtin:incline-bench-press',
    'Decline Bench Press': 'builtin:decline-bench-press',
    'Dumbbell Press': 'builtin:dumbbell-press',
    'Incline Dumbbell Press': 'builtin:incline-dumbbell-press',
    'Dumbbell Fly': 'builtin:dumbbell-fly',
    'Cable Fly': 'builtin:cable-fly',
    'Machine Chest Press': 'builtin:machine-chest-press',
    'Machine Incline Chest Press': 'builtin:machine-incline-chest-press',
    'Machine Chest Fly': 'builtin:machine-chest-fly',
    'Push-ups': 'builtin:push-ups',
    'Chest Dips': 'builtin:chest-dips',
    'Cable Crossover': 'builtin:cable-crossover',
    'Deadlift': 'builtin:deadlift',
    'Barbell Row': 'builtin:barbell-row',
    'Dumbbell Row': 'builtin:dumbbell-row',
    'Lat Pulldown': 'builtin:lat-pulldown',
    'Pull-ups': 'builtin:pull-ups',
    'Chin-ups': 'builtin:chin-ups',
    'Seated Cable Row': 'builtin:seated-cable-row',
    'T-Bar Row': 'builtin:t-bar-row',
    'Face Pull': 'builtin:face-pull',
    'Single Arm Row': 'builtin:single-arm-row',
    'Overhead Press': 'builtin:overhead-press',
    'Dumbbell Shoulder Press': 'builtin:dumbbell-shoulder-press',
    'Machine Shoulder Press': 'builtin:machine-shoulder-press',
    'Lateral Raise': 'builtin:lateral-raise',
    'Front Raise': 'builtin:front-raise',
    'Rear Delt Fly': 'builtin:rear-delt-fly',
    'Arnold Press': 'builtin:arnold-press',
    'Shrugs': 'builtin:shrugs',
    'Upright Row': 'builtin:upright-row',
    'Cable Lateral Raise': 'builtin:cable-lateral-raise',
    'Reverse Fly': 'builtin:reverse-fly',
    'Bicep Curl': 'builtin:bicep-curl',
    'Hammer Curl': 'builtin:hammer-curl',
    'Preacher Curl': 'builtin:preacher-curl',
    'Concentration Curl': 'builtin:concentration-curl',
    'Cable Curl': 'builtin:cable-curl',
    'Bayesian Curl': 'builtin:bayesian-curl',
    'Tricep Pushdown': 'builtin:tricep-pushdown',
    'Skull Crusher': 'builtin:skull-crusher',
    'Tricep Dips': 'builtin:tricep-dips',
    'Overhead Tricep Extension': 'builtin:overhead-tricep-extension',
    'Close Grip Bench Press': 'builtin:close-grip-bench-press',
    'Squat': 'builtin:squat',
    'Front Squat': 'builtin:front-squat',
    'Leg Press': 'builtin:leg-press',
    'Hack Squat': 'builtin:hack-squat',
    'Lunges': 'builtin:lunges',
    'Bulgarian Split Squat': 'builtin:bulgarian-split-squat',
    'Leg Extension': 'builtin:leg-extension',
    'Leg Curl': 'builtin:leg-curl',
    'Romanian Deadlift': 'builtin:romanian-deadlift',
    'Calf Raise': 'builtin:calf-raise',
    'Seated Calf Raise': 'builtin:seated-calf-raise',
    'Hip Thrust': 'builtin:hip-thrust',
    'Glute Bridge': 'builtin:glute-bridge',
    'Plank': 'builtin:plank',
    'Crunches': 'builtin:crunches',
    'Russian Twist': 'builtin:russian-twist',
    'Leg Raise': 'builtin:leg-raise',
    'Hanging Leg Raise': 'builtin:hanging-leg-raise',
    'Cable Ab Crunch': 'builtin:cable-ab-crunch',
    'Bicycle Crunches': 'builtin:bicycle-crunches',
    'Mountain Climbers': 'builtin:mountain-climbers',
    'Ab Wheel Rollout': 'builtin:ab-wheel-rollout',
    'Dead Bug': 'builtin:dead-bug',
    'Bird Dog': 'builtin:bird-dog',
    'Side Plank': 'builtin:side-plank',
  };

  static const aliasesByName = <String, List<String>>{
    'Dumbbell Press': [
      'Dumbbell Bench Press',
      'DB Bench Press',
      'Dumbbell Chest Press',
    ],
    'Incline Dumbbell Press': [
      'Incline DB Press',
      'Incline Dumbbell Bench Press',
    ],
    'Dumbbell Shoulder Press': ['DB Shoulder Press'],
    'Dumbbell Row': ['DB Row'],
    'Romanian Deadlift': ['RDL'],
    'Push-ups': ['Pushups', 'Push ups'],
    'Pull-ups': ['Pullups', 'Pull ups'],
    'Chin-ups': ['Chinups', 'Chin ups'],
  };

  static List<ExerciseDefinition> get definitions => [
    for (final category in exercisesByCategory.entries)
      for (final name in category.value)
        ExerciseDefinition(
          id: idsByName[name]!,
          name: name,
          category: category.key,
          aliases: aliasesByName[name] ?? const [],
          builtIn: true,
        ),
  ];

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
  static final Map<String, List<String>> exercisesByCategory = Map.unmodifiable(
    {
      for (final MapEntry(key: category, value: exercises) in catalog.entries)
        category: List<String>.unmodifiable([
          for (final exercise in exercises) exercise.name,
        ]),
    },
  );

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

  static final Map<String, ExerciseKind> _kindById = {
    for (final exercises in catalog.values)
      for (final exercise in exercises)
        idsByName[exercise.name]!: exercise.kind,
  };

  /// How the built-in label [name] is measured. Custom and unknown names are
  /// weighted. Prefer `ExerciseCatalog.kindOf`, which follows an occurrence's
  /// stable ID, so a renamed or merged hold keeps storing seconds.
  static ExerciseKind kindOf(String name) =>
      _index[_key(name)]?.$2.kind ?? ExerciseKind.weighted;

  /// How the built-in exercise with permanent [id] is measured. Custom IDs
  /// are weighted.
  static ExerciseKind kindOfId(String id) =>
      _kindById[id] ?? ExerciseKind.weighted;

  /// Whether the built-in label [name] is a hold whose sets store seconds.
  static bool isTimed(String name) => kindOf(name) == ExerciseKind.timed;

  /// The catalog category of [name], or null for a custom exercise.
  static String? categoryOf(String name) => _index[_key(name)]?.$1;
}
