class ExerciseLibrary {
  static const Map<String, List<String>> exercisesByCategory = {
    'Chest': [
      'Bench Press',
      'Incline Bench Press',
      'Decline Bench Press',
      'Dumbbell Press',
      'Incline Dumbbell Press',
      'Dumbbell Fly',
      'Cable Fly',
      'Machine Chest Press',
      'Machine Incline Chest Press',
      'Machine Chest Fly',
      'Push-ups',
      'Chest Dips',
      'Cable Crossover',
    ],
    'Back': [
      'Deadlift',
      'Barbell Row',
      'Dumbbell Row',
      'Lat Pulldown',
      'Pull-ups',
      'Chin-ups',
      'Seated Cable Row',
      'T-Bar Row',
      'Face Pull',
      'Single Arm Row',
    ],
    'Shoulders': [
      'Overhead Press',
      'Dumbbell Shoulder Press',
      'Machine Shoulder Press',
      'Lateral Raise',
      'Front Raise',
      'Rear Delt Fly',
      'Arnold Press',
      'Shrugs',
      'Upright Row',
      'Cable Lateral Raise',
      'Reverse Fly',
    ],
    'Arms': [
      'Bicep Curl',
      'Hammer Curl',
      'Preacher Curl',
      'Concentration Curl',
      'Cable Curl',
      'Bayesian Curl',
      'Tricep Pushdown',
      'Skull Crusher',
      'Tricep Dips',
      'Overhead Tricep Extension',
      'Close Grip Bench Press',
    ],
    'Legs': [
      'Squat',
      'Front Squat',
      'Leg Press',
      'Hack Squat',
      'Lunges',
      'Bulgarian Split Squat',
      'Leg Extension',
      'Leg Curl',
      'Romanian Deadlift',
      'Calf Raise',
      'Seated Calf Raise',
      'Hip Thrust',
      'Glute Bridge',
    ],
    'Core': [
      'Plank',
      'Crunches',
      'Russian Twist',
      'Leg Raise',
      'Hanging Leg Raise',
      'Cable Ab Crunch',
      'Bicycle Crunches',
      'Mountain Climbers',
      'Ab Wheel Rollout',
      'Dead Bug',
      'Bird Dog',
      'Side Plank',
    ],
  };

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
}
