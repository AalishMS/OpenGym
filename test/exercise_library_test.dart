import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/data/exercise_library.dart';

void main() {
  test('requested exercises belong to their expected categories', () {
    const expectedCategories = <String, List<String>>{
      'Chest': [
        'Machine Chest Press',
        'Machine Incline Chest Press',
        'Machine Chest Fly',
      ],
      'Shoulders': ['Machine Shoulder Press'],
      'Arms': ['Bayesian Curl'],
      'Core': ['Hanging Leg Raise', 'Cable Ab Crunch'],
    };

    for (final entry in expectedCategories.entries) {
      final categoryExercises = ExerciseLibrary.exercisesByCategory[entry.key];
      expect(categoryExercises, isNotNull);
      for (final exercise in entry.value) {
        expect(categoryExercises, contains(exercise));
        expect(
          ExerciseLibrary.exercisesByCategory.values
              .expand((exercises) => exercises)
              .where((name) => name == exercise),
          hasLength(1),
        );
      }
    }
  });

  test('close-name aliases are not added as separate exercises', () {
    for (final alias in <String>['Machine Lat Pulldown', 'Pushups', 'Dips']) {
      expect(ExerciseLibrary.allExercises, isNot(contains(alias)));
    }
    expect(
      ExerciseLibrary.exercisesByCategory['Back'],
      contains('Lat Pulldown'),
    );
    expect(ExerciseLibrary.exercisesByCategory['Chest'], contains('Push-ups'));
    expect(
      ExerciseLibrary.exercisesByCategory['Chest'],
      contains('Chest Dips'),
    );
    expect(
      ExerciseLibrary.exercisesByCategory['Arms'],
      contains('Tricep Dips'),
    );
  });
}
