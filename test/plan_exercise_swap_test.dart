import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/plan_exercise_swap.dart';
import 'package:gymapp/services/workout_session_initializer.dart';

void main() {
  const bench = 'builtin:bench-press';
  const cableFly = 'builtin:cable-fly';
  const dumbbellFly = 'builtin:dumbbell-fly';

  ExerciseTemplate fly({String? note}) => ExerciseTemplate(
    name: 'Cable Fly',
    exerciseId: cableFly,
    sets: 3,
    note: note,
    setTargets: [
      SetTemplate(reps: 12, weight: 20, rpe: 8),
      SetTemplate(reps: 12, weight: 20),
      SetTemplate(reps: 15, weight: 15, rpe: 9),
    ],
  );
  WorkoutPlan planOf(List<ExerciseTemplate> exercises) => WorkoutPlan(
    id: 'push',
    name: 'Push',
    splitId: 'split',
    planColor: 3,
    position: 2,
    exercises: exercises,
  );
  final benchPress = ExerciseTemplate(
    name: 'Bench Press',
    exerciseId: bench,
    sets: 2,
  );

  List<(int, double, int?)> targets(ExerciseTemplate template) => [
    for (final t in template.setTargets!) (t.reps, t.weight, t.rpe),
  ];

  test('the replacement takes the slot, its latest sets and the effort '
      'targets, and loses the old note', () {
    final plan = planOf([benchPress, fly(note: 'Cross the cables')]);
    final swapped = PlanExerciseSwap.apply(
      plan,
      from: cableFly,
      to: dumbbellFly,
      name: 'Dumbbell Fly',
      history: [gym.Set(reps: 10, weight: 14), gym.Set(reps: 9, weight: 12)],
    );
    expect(swapped.exercises.map((e) => e.exerciseId), [bench, dumbbellFly]);
    final replacement = swapped.exercises.last;
    expect(replacement.name, 'Dumbbell Fly');
    expect(replacement.sets, 3);
    expect(replacement.note, isNull);
    // The last logged set stands in for a set the history does not have.
    expect(targets(replacement), [
      (10, 14.0, 8),
      (9, 12.0, null),
      (9, 12.0, 9),
    ]);
    // Everything else about the plan stays.
    expect(swapped.id, 'push');
    expect(swapped.name, 'Push');
    expect(swapped.planColor, 3);
    expect(swapped.position, 2);
    expect(identical(swapped.exercises.first, benchPress), isTrue);
    // The plan handed in is not changed.
    expect(plan.exercises.last.exerciseId, cableFly);
  });

  test('with no history the reps stay and there is no weight target', () {
    final swapped = PlanExerciseSwap.apply(
      planOf([fly()]),
      from: cableFly,
      to: dumbbellFly,
      name: 'Dumbbell Fly',
    );
    expect(targets(swapped.exercises.single), [
      (12, 0.0, 8),
      (12, 0.0, null),
      (15, 0.0, 9),
    ]);

    // A plan saved before targets existed still has none.
    final legacy = PlanExerciseSwap.apply(
      planOf([benchPress]),
      from: bench,
      to: dumbbellFly,
      name: 'Dumbbell Fly',
    );
    expect(legacy.exercises.single.sets, 2);
    expect(legacy.exercises.single.setTargets, isNull);
  });

  test('a plan that lists the exercise twice swaps the matching one', () {
    final plan = planOf([fly(), benchPress, fly()]);
    expect(PlanExerciseSwap.indexOf(plan, cableFly), 0);
    expect(PlanExerciseSwap.indexOf(plan, cableFly, occurrence: 1), 2);
    expect(PlanExerciseSwap.indexOf(plan, cableFly, occurrence: 2), -1);
    final swapped = PlanExerciseSwap.apply(
      plan,
      from: cableFly,
      to: dumbbellFly,
      name: 'Dumbbell Fly',
      occurrence: 1,
    );
    expect(swapped.exercises.map((e) => e.exerciseId), [
      cableFly,
      bench,
      dumbbellFly,
    ]);
  });

  test('nothing is swapped when the plan lacks the exercise or already has '
      'the replacement', () {
    final plan = planOf([benchPress, fly()]);
    // Added in a workout, so the plan has no such exercise.
    expect(
      PlanExerciseSwap.canApply(plan, from: dumbbellFly, to: 'builtin:squat'),
      isFalse,
    );
    // Swapping to an exercise the plan lists would list it twice.
    expect(PlanExerciseSwap.canApply(plan, from: cableFly, to: bench), isFalse);
    expect(
      identical(
        PlanExerciseSwap.apply(
          plan,
          from: cableFly,
          to: bench,
          name: 'Bench Press',
        ),
        plan,
      ),
      isTrue,
    );
    expect(
      PlanExerciseSwap.canApply(plan, from: cableFly, to: dumbbellFly),
      isTrue,
    );
  });

  test('once the plan has the swap too, dropping the replacement from the '
      'workout keeps it dropped next week', () {
    final plan = planOf([benchPress, fly()]);
    final swapped = PlanExerciseSwap.apply(
      plan,
      from: cableFly,
      to: dumbbellFly,
      name: 'Dumbbell Fly',
    );
    // The workout swapped the fly, changed the plan too, then dropped it.
    WorkoutSession logged(List<String>? lineup) => WorkoutSession(
      id: 'week-1',
      planId: 'push',
      splitId: 'split',
      planName: 'Push',
      date: DateTime(2026, 2),
      planExerciseIds: lineup,
      exercises: [
        Exercise(
          name: 'Bench Press',
          exerciseId: bench,
          sets: [gym.Set(reps: 8, weight: 80)],
        ),
      ],
    );
    List<String?> nextWeek(List<String>? lineup) => [
      for (final e
          in WorkoutSessionInitializer.initialize(
            plan: swapped,
            week: TrainingWeek(
              id: 'week-2',
              splitId: 'split',
              blockId: 'block',
              number: 2,
              createdAt: DateTime(2026),
            ),
            previousSession: logged(lineup),
          ).exercises)
        e.exerciseId,
    ];

    expect(
      nextWeek(
        PlanExerciseSwap.inLineup(
          [bench, cableFly],
          from: cableFly,
          to: dumbbellFly,
        ),
      ),
      [bench],
    );
    // Left as first recorded, the swap would read as a plan edit made since
    // and bring the dropped exercise back.
    expect(nextWeek([bench, cableFly]), [bench, dumbbellFly]);
  });

  test('a recorded lineup gets the same swap and nothing else', () {
    expect(
      PlanExerciseSwap.inLineup(
        [cableFly, bench, cableFly],
        from: cableFly,
        to: dumbbellFly,
        occurrence: 1,
      ),
      [cableFly, bench, dumbbellFly],
    );
    // The plan gained the exercise after this workout was built: nothing to
    // record, so it still arrives next week as a plan edit.
    expect(
      PlanExerciseSwap.inLineup([bench], from: cableFly, to: dumbbellFly),
      [bench],
    );
    expect(
      PlanExerciseSwap.inLineup(null, from: cableFly, to: dumbbellFly),
      isNull,
    );
  });
}
