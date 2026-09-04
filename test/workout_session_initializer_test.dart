import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/workout_session_initializer.dart';

void main() {
  final plan = WorkoutPlan(
    name: 'Strength',
    exercises: [
      ExerciseTemplate(
        name: 'Squat',
        sets: 2,
        setTargets: [
          SetTemplate(reps: 5, weight: 100.5),
          SetTemplate(reps: 6, weight: 102.25),
        ],
      ),
      ExerciseTemplate(
        name: 'Press',
        sets: 1,
        setTargets: [SetTemplate(reps: 8, weight: 42.5)],
      ),
    ],
  );

  test('Week 1 receives every prescribed set including decimal weights', () {
    final result = WorkoutSessionInitializer.initialize(
      plan: plan,
      weekNumber: 1,
    );

    expect(result.seededFromPlan, isTrue);
    expect(result.session.exercises, hasLength(2));
    expect(result.session.exercises[0].sets, hasLength(2));
    expect(
      result.session.exercises[0].sets.map((set) => (set.reps, set.weight)),
      [(5, 100.5), (6, 102.25)],
    );
    expect(result.session.exercises[1].sets.single.weight, 42.5);
  });

  test('existing Week 1 data is returned without being overwritten', () {
    final existing = WorkoutSession(
      date: DateTime(2026),
      planName: plan.name,
      weekNumber: 1,
      exercises: [
        Exercise(name: 'Squat', sets: [gym.Set(reps: 3, weight: 77.5)]),
      ],
    );

    final result = WorkoutSessionInitializer.initialize(
      plan: plan,
      weekNumber: 1,
      existingSession: existing,
    );

    expect(result.seededFromPlan, isFalse);
    expect(identical(result.session, existing), isTrue);
    expect(result.session.exercises.single.sets.single.weight, 77.5);
  });

  test('plans without targets receive safe empty sets', () {
    final legacyPlan = WorkoutPlan(
      name: 'Legacy',
      exercises: [ExerciseTemplate(name: 'Row', sets: 3)],
    );

    final result = WorkoutSessionInitializer.initialize(
      plan: legacyPlan,
      weekNumber: 1,
    );

    expect(result.session.exercises.single.sets, hasLength(3));
    expect(
      result.session.exercises.single.sets,
      everyElement(
        isA<gym.Set>()
            .having((set) => set.reps, 'reps', 0)
            .having((set) => set.weight, 'weight', 0),
      ),
    );
  });

  test('later weeks still copy prior workout data', () {
    final previous = WorkoutSession(
      date: DateTime(2026),
      planName: plan.name,
      weekNumber: 1,
      exercises: [
        Exercise(
          name: 'Squat',
          sets: [gym.Set(reps: 9, weight: 88.75, rpe: 7, note: 'solid')],
          note: 'previous note',
        ),
      ],
    );

    final result = WorkoutSessionInitializer.initialize(
      plan: plan,
      weekNumber: 2,
      previousSession: previous,
    );

    expect(result.seededFromPlan, isFalse);
    final copied = result.session.exercises.single.sets.single;
    expect(
      (copied.reps, copied.weight, copied.rpe, copied.note),
      (9, 88.75, 7, 'solid'),
    );
    expect(identical(copied, previous.exercises.single.sets.single), isFalse);
  });

  test('later weeks without prior data remain empty despite plan targets', () {
    final result = WorkoutSessionInitializer.initialize(
      plan: plan,
      weekNumber: 2,
    );

    expect(result.seededFromPlan, isFalse);
    expect(result.session.exercises[0].sets.first.reps, 0);
    expect(result.session.exercises[0].sets.first.weight, 0);
  });
}
