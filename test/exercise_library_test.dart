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

  test('the public lists keep their names and order', () {
    expect(ExerciseLibrary.categoryNames, [
      'Chest',
      'Back',
      'Shoulders',
      'Arms',
      'Legs',
      'Core',
    ]);
    expect(ExerciseLibrary.exercisesByCategory['Back'], [
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
    ]);
    expect(ExerciseLibrary.exercisesByCategory['Core']!.first, 'Plank');
    expect(ExerciseLibrary.exercisesByCategory['Core']!.last, 'Side Plank');
    expect(ExerciseLibrary.allExercises, hasLength(70));
    expect(
      ExerciseLibrary.allExercises,
      [...ExerciseLibrary.allExercises]..sort(),
    );
    expect(ExerciseLibrary.categories, ExerciseLibrary.exercisesByCategory);
  });

  test('kinds and categories look up by trimmed, case-insensitive name', () {
    expect(ExerciseLibrary.kindOf('Plank'), ExerciseKind.timed);
    expect(ExerciseLibrary.kindOf('  side plank '), ExerciseKind.timed);
    expect(ExerciseLibrary.isTimed('SIDE PLANK'), isTrue);
    for (final name in [
      'Push-ups',
      'pull-ups',
      'Chin-ups',
      'Chest Dips',
      'Tricep Dips',
      'Crunches',
    ]) {
      expect(
        ExerciseLibrary.kindOf(name),
        ExerciseKind.bodyweight,
        reason: name,
      );
    }
    expect(ExerciseLibrary.kindOf('Bench Press'), ExerciseKind.weighted);
    expect(ExerciseLibrary.kindOf('My custom lift'), ExerciseKind.weighted);
    expect(ExerciseLibrary.isTimed('My custom lift'), isFalse);
    expect(ExerciseLibrary.categoryOf(' bench press'), 'Chest');
    expect(ExerciseLibrary.categoryOf('Plank'), 'Core');
    expect(ExerciseLibrary.categoryOf('My custom lift'), isNull);
    for (final exercises in ExerciseLibrary.catalog.values) {
      for (final exercise in exercises) {
        expect(ExerciseLibrary.kindOf(exercise.name), exercise.kind);
      }
    }
  });
}
