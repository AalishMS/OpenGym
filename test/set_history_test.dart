import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/utils/set_history.dart';

void main() {
  WorkoutSession session(
    int week, {
    String plan = 'Push',
    String name = 'Bench',
    DateTime? deletedAt,
    List<gym.Set>? sets,
  }) => WorkoutSession(
    date: DateTime(2026, 1, week),
    planName: plan,
    weekNumber: week,
    deletedAt: deletedAt,
    exercises: [
      Exercise(name: name, sets: sets ?? [gym.Set(weight: week * 10, reps: 8)]),
    ],
  );

  test(
    'workout previous excludes current, future, deleted and other plans',
    () {
      final previous = previousExerciseSets(
        [
          session(5),
          session(2),
          session(1),
          session(4),
          session(3, deletedAt: DateTime(2026)),
          session(3, plan: 'Other'),
        ],
        'bench',
        planName: 'Push',
        beforeWeek: 4,
      );
      expect(previous.single.weight, 20);
    },
  );

  test('skips missing and empty exercises without shifting set positions', () {
    final sets = [
      gym.Set(weight: 50, reps: 8),
      gym.Set(weight: 0, reps: 0),
      gym.Set(weight: 45, reps: 10),
    ];
    final previous = previousExerciseSets(
      [
        session(3, name: 'Squat'),
        session(2, sets: [gym.Set(weight: 0, reps: 0)]),
        session(1, sets: sets),
      ],
      'Bench',
      planName: 'Push',
      beforeWeek: 4,
    );
    expect(previous, same(sets));
    expect(previous[1].reps, 0);
    expect(previousExerciseSets([], 'Bench'), isEmpty);
  });

  test(
    'plan editor finds latest exercise across plans without mutating history',
    () {
      final latest = session(5, plan: 'Other');
      final previous = previousExerciseSets([session(2), latest], 'Bench');
      expect(previous.single.weight, 50);
      expect(latest.exercises.single.sets.single.weight, 50);
    },
  );

  test('previous results never cross the requested split', () {
    final local = session(1)..splitId = 'split-a';
    final other = session(5)..splitId = 'split-b';
    expect(
      previousExerciseSets(
        [local, other],
        'Bench',
        splitId: 'split-a',
      ).single.weight,
      10,
    );
    expect(
      previousExerciseSets([local, other], 'Bench', splitId: 'split-c'),
      isEmpty,
    );
  });
}
