import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/workout_session_initializer.dart';

void main() {
  final plan = WorkoutPlan(
    name: 'Strength',
    splitId: 'split-a',
    exercises: [
      ExerciseTemplate(
        name: 'Squat',
        sets: 2,
        note: 'Reduce the load between sets.',
        setTargets: [
          SetTemplate(reps: 5, weight: 100.5, rpe: 8),
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

  test(
    'explicit sparse week uses targets, explicit IDs and a fresh clean draft',
    () {
      final week = TrainingWeek(
        id: 'week-3',
        splitId: 'split-a',
        blockId: 'block',
        number: 3,
        createdAt: DateTime(2026),
      );
      final session = WorkoutSessionInitializer.initialize(
        plan: plan.copyWith(id: 'plan'),
        week: week,
        now: DateTime(2026, 10),
      );
      expect(session.trainingWeekId, 'week-3');
      expect(session.planId, 'plan');
      expect(session.id, isNotNull);
      expect(session.exercises.first.sets.first.weight, 100.5);
      expect(session.startedAt, isNull);
      expect(session.completionTransition, isNull);
    },
  );

  test(
    'a workout built before lineups were recorded carries over as it was',
    () {
      final current = plan.copyWith(
        id: 'plan',
        exercises: [
          ExerciseTemplate(
            name: '  SQUAT ',
            sets: 2,
            note: 'Current cue',
            setTargets: [SetTemplate(reps: 5, weight: 10)],
          ),
          ExerciseTemplate(
            name: 'New',
            sets: 1,
            setTargets: [SetTemplate(reps: 8, weight: 20)],
          ),
          ExerciseTemplate(name: 'Squat', sets: 1),
        ],
      );
      final source = WorkoutSession(
        id: 'source',
        planId: 'plan',
        splitId: 'split-a',
        planName: 'Old',
        date: DateTime(2026),
        exercises: [
          Exercise(
            name: 'squat',
            note: 'Old cue',
            sets: [gym.Set(reps: 9, weight: 90, rpe: 8, note: 'Old note')],
          ),
          Exercise(
            name: 'Added there',
            note: 'Its own note',
            sets: [gym.Set(reps: 4, weight: 40)],
          ),
          Exercise(name: 'Squat', sets: [gym.Set(reps: 6, weight: 60)]),
        ],
      );
      final week = TrainingWeek(
        id: 'week',
        splitId: 'split-a',
        blockId: 'block',
        number: 2,
        createdAt: DateTime(2026),
      );
      final session = WorkoutSessionInitializer.initialize(
        plan: current,
        week: week,
        previousSession: source,
      );
      // With no recorded lineup the plan counts as unchanged since, so the
      // workout's own lineup wins: its addition stays, the plan exercise it
      // dropped stays dropped, and repeats match by occurrence.
      expect(session.exercises.map((e) => e.name), [
        'Squat',
        'Added there',
        'Squat',
      ]);
      expect(session.exercises.map((e) => e.sets.first.weight), [90, 40, 60]);
      // Plan guidance wins; an exercise it says nothing about keeps its note.
      expect(session.exercises.first.note, 'Current cue');
      expect(session.exercises[1].note, 'Its own note');
      expect(session.exercises.first.sets.single.note, isNull);
      expect(session.planExerciseIds, hasLength(3));
      session.exercises.first.sets[0] = gym.Set(reps: 1, weight: 1);
      expect(source.exercises.first.sets.single.weight, 90);
      expect(
        identical(
          WorkoutSessionInitializer.initialize(
            plan: current,
            week: week,
            existingSession: session,
          ),
          session,
        ),
        isTrue,
      );
    },
  );

  group('carry-over from the last workout', () {
    final week = TrainingWeek(
      id: 'week-3',
      splitId: 'split-a',
      blockId: 'block',
      number: 3,
      createdAt: DateTime(2026),
    );
    ExerciseTemplate template(String name, {int sets = 1, double w = 10}) =>
        ExerciseTemplate(
          name: name,
          exerciseId: 'id-$name',
          sets: sets,
          setTargets: [
            for (var i = 0; i < sets; i++) SetTemplate(reps: 5, weight: w),
          ],
        );
    WorkoutPlan planOf(List<String> names) => WorkoutPlan(
      id: 'plan',
      name: 'Strength',
      splitId: 'split-a',
      exercises: [for (final n in names) template(n)],
    );
    Exercise logged(String name, {double w = 50, int sets = 1}) => Exercise(
      name: name,
      exerciseId: 'id-$name',
      sets: [for (var i = 0; i < sets; i++) gym.Set(reps: 8, weight: w)],
    );
    WorkoutSession last(List<Exercise> exercises, {List<String>? lineup}) =>
        WorkoutSession(
          id: 'last',
          planId: 'plan',
          splitId: 'split-a',
          planName: 'Strength',
          date: DateTime(2026, 2),
          exercises: exercises,
          planExerciseIds: lineup?.map((n) => 'id-$n').toList(),
        );
    List<String> names(WorkoutSession s) => [
      for (final e in s.exercises) e.exerciseId!.substring(3),
    ];

    test('replacements, additions, removals and order carry over', () {
      final session = WorkoutSessionInitializer.initialize(
        plan: planOf(['Squat', 'Press', 'Row']),
        week: week,
        previousSession: last(
          [
            logged('Row', w: 70),
            logged('Squat', w: 100),
            logged('Dips', w: 0),
            logged('Curl', w: 15),
          ],
          lineup: ['Squat', 'Press', 'Row'],
        ),
      );
      expect(names(session), ['Row', 'Squat', 'Dips', 'Curl']);
      expect(session.exercises.map((e) => e.sets.single.weight), [
        70,
        100,
        0,
        15,
      ]);
      expect(session.planExerciseIds, ['id-Squat', 'id-Press', 'id-Row']);
    });

    test('an exercise added to the plan since arrives after its neighbour', () {
      final session = WorkoutSessionInitializer.initialize(
        plan: planOf(['Lunge', 'Squat', 'Press', 'Fly', 'Row']),
        week: week,
        previousSession: last(
          [logged('Squat'), logged('Curl'), logged('Press'), logged('Row')],
          lineup: ['Squat', 'Press', 'Row'],
        ),
      );
      expect(names(session), ['Lunge', 'Squat', 'Curl', 'Press', 'Fly', 'Row']);
      // A plan addition has no logged sets yet, so it opens with its targets.
      expect(session.exercises.first.sets.single.weight, 10);
    });

    test('an exercise dropped from the plan since is dropped', () {
      final session = WorkoutSessionInitializer.initialize(
        plan: planOf(['Squat', 'Row']),
        week: week,
        previousSession: last(
          [logged('Squat'), logged('Press'), logged('Curl'), logged('Row')],
          lineup: ['Squat', 'Press', 'Row'],
        ),
      );
      expect(names(session), ['Squat', 'Curl', 'Row']);
    });

    test('a plan exercise removed in the workout stays removed', () {
      final session = WorkoutSessionInitializer.initialize(
        plan: planOf(['Squat', 'Press', 'Row']),
        week: week,
        previousSession: last(
          [logged('Squat'), logged('Row')],
          lineup: ['Squat', 'Press', 'Row'],
        ),
      );
      expect(names(session), ['Squat', 'Row']);
    });

    test('with no recorded lineup, only a plan saved after the workout adds '
        'the exercises the workout lacks', () {
      // Logged by an older version: Press was either removed that day or
      // added to the plan later, and nothing recorded says which.
      final legacy = last([logged('Row'), logged('Squat'), logged('Curl')]);
      WorkoutSession build(DateTime planSaved) =>
          WorkoutSessionInitializer.initialize(
            plan: planOf([
              'Squat',
              'Press',
              'Fly',
              'Row',
            ]).copyWith(updatedAt: planSaved),
            week: week,
            previousSession: legacy,
          );

      // Saved before the workout: the plan cannot have changed since, so the
      // workout's lineup is carried as it is.
      expect(names(build(DateTime(2026, 1))), ['Row', 'Squat', 'Curl']);

      // Saved after it: the plan's extra exercises arrive after their plan
      // neighbour, and the workout's own order and addition stay.
      final after = build(DateTime(2026, 3));
      expect(names(after), ['Row', 'Squat', 'Press', 'Fly', 'Curl']);
      expect(after.planExerciseIds, [
        'id-Squat',
        'id-Press',
        'id-Fly',
        'id-Row',
      ]);

      // A workout that did record its lineup is never second-guessed.
      final recorded = WorkoutSessionInitializer.initialize(
        plan: planOf([
          'Squat',
          'Press',
          'Row',
        ]).copyWith(updatedAt: DateTime(2026, 3)),
        week: week,
        previousSession: last(
          [logged('Row'), logged('Squat')],
          lineup: ['Squat', 'Press', 'Row'],
        ),
      );
      expect(names(recorded), ['Row', 'Squat']);
    });

    test('a plan reordered since takes the plan order, keeping additions '
        'after the exercise they followed', () {
      final session = WorkoutSessionInitializer.initialize(
        plan: planOf(['Row', 'Press', 'Squat']),
        week: week,
        previousSession: last(
          [
            logged('Curl'),
            logged('Squat'),
            logged('Dips'),
            logged('Press'),
            logged('Row'),
          ],
          lineup: ['Squat', 'Press', 'Row'],
        ),
      );
      expect(names(session), ['Curl', 'Row', 'Press', 'Squat', 'Dips']);
    });

    test('a new block keeps the latest lineup but restarts from its sets', () {
      final blockStart = last(
        [logged('Squat', w: 80), logged('Press', w: 40)],
        lineup: ['Squat', 'Press'],
      );
      final latest = WorkoutSession(
        id: 'latest',
        planId: 'plan',
        splitId: 'split-a',
        planName: 'Strength',
        date: DateTime(2026, 3),
        exercises: [logged('Squat', w: 120), logged('Dips', w: 10)],
        planExerciseIds: const ['id-Squat', 'id-Press'],
      );
      final session = WorkoutSessionInitializer.initialize(
        plan: planOf(['Squat', 'Press']),
        week: week,
        previousSession: blockStart,
        lastSession: latest,
      );
      expect(names(session), ['Squat', 'Dips']);
      // Week 1's sets where it has them, the last workout's otherwise.
      expect(session.exercises.map((e) => e.sets.single.weight), [80, 10]);
    });

    test('without last week\'s sets, plan exercises use targets and the '
        'rest open blank', () {
      final session = WorkoutSessionInitializer.initialize(
        plan: planOf(['Squat']),
        week: week,
        previousSession: last(
          [logged('Squat', w: 100), logged('Dips', w: 20, sets: 3)],
          lineup: ['Squat'],
        ),
        copySets: false,
      );
      expect(names(session), ['Squat', 'Dips']);
      expect(session.exercises.first.sets.single.weight, 10);
      expect(session.exercises.last.sets, hasLength(3));
      expect(
        session.exercises.last.sets.map((s) => (s.reps, s.weight)),
        everyElement((0, 0.0)),
      );
    });

    test('an unfinished or deleted workout is not carried over', () {
      for (final source in [
        last([logged('Dips')]).copyWith(isCompleted: false),
        last([logged('Dips')]).copyWith(deletedAt: DateTime(2026)),
        last([logged('Dips')]).copyWith(planId: 'other'),
      ]) {
        final session = WorkoutSessionInitializer.initialize(
          plan: planOf(['Squat']),
          week: week,
          previousSession: source,
          lastSession: source,
        );
        expect(names(session), ['Squat']);
      }
    });
  });

  test('Week 1 receives every prescribed set including decimal weights', () {
    final session = WorkoutSessionInitializer.initialize(
      plan: plan,
      week: TrainingWeek(
        id: 'week-1',
        splitId: 'split-a',
        blockId: 'block',
        number: 1,
        createdAt: DateTime(2026),
      ),
    );

    expect(session.splitId, 'split-a');
    expect(session.isCompleted, isFalse);
    expect(session.durationSeconds, 0);
    expect(session.exercises, hasLength(2));
    expect(session.exercises[0].sets, hasLength(2));
    expect(session.exercises[0].note, 'Reduce the load between sets.');
    expect(session.exercises[0].sets.map((set) => (set.reps, set.weight)), [
      (5, 100.5),
      (6, 102.25),
    ]);
    expect(session.exercises[1].sets.single.weight, 42.5);
    expect(session.exercises[0].sets.first.rpe, 8);
    expect(session.exercises[0].sets.last.rpe, isNull);
  });

  test('existing Week 1 data is returned without being overwritten', () {
    final existing = WorkoutSession(
      date: DateTime(2026),
      planName: plan.name,
      weekNumber: 1,
      splitId: 'split-a',
      exercises: [
        Exercise(name: 'Squat', sets: [gym.Set(reps: 3, weight: 77.5)]),
      ],
    );

    final session = WorkoutSessionInitializer.initialize(
      plan: plan,
      week: TrainingWeek(
        id: 'week-1',
        splitId: 'split-a',
        blockId: 'block',
        number: 1,
        createdAt: DateTime(2026),
      ),
      existingSession: existing,
    );

    expect(identical(session, existing), isTrue);
    expect(session.exercises.single.sets.single.weight, 77.5);
  });

  test('plans without targets receive safe empty sets', () {
    final legacyPlan = WorkoutPlan(
      name: 'Legacy',
      splitId: 'split-a',
      exercises: [ExerciseTemplate(name: 'Row', sets: 3)],
    );

    final session = WorkoutSessionInitializer.initialize(
      plan: legacyPlan,
      week: TrainingWeek(
        id: 'week-1',
        splitId: 'split-a',
        blockId: 'block',
        number: 1,
        createdAt: DateTime(2026),
      ),
    );

    expect(session.exercises.single.sets, hasLength(3));
    expect(
      session.exercises.single.sets,
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
      splitId: 'split-a',
      exercises: [
        Exercise(
          name: 'Squat',
          sets: [gym.Set(reps: 9, weight: 88.75, rpe: 7, note: 'solid')],
          note: 'previous note',
        ),
      ],
    );

    final session = WorkoutSessionInitializer.initialize(
      plan: plan,
      week: TrainingWeek(
        id: 'week-2',
        splitId: 'split-a',
        blockId: 'block',
        number: 2,
        createdAt: DateTime(2026),
      ),
      previousSession: previous,
    );

    final copied = session.exercises.first.sets.single;
    expect(
      (copied.reps, copied.weight, copied.rpe, copied.note),
      (9, 88.75, 7, null),
    );
    expect(identical(copied, previous.exercises.single.sets.single), isFalse);
  });

  test('missing source in later weeks uses current plan targets', () {
    final session = WorkoutSessionInitializer.initialize(
      plan: plan,
      week: TrainingWeek(
        id: 'week-2',
        splitId: 'split-a',
        blockId: 'block',
        number: 2,
        createdAt: DateTime(2026),
      ),
    );

    expect(session.exercises[0].sets.first.reps, 5);
    expect(session.exercises[0].sets.first.weight, 100.5);
    expect(session.exercises[0].sets.first.rpe, 8);
    expect(session.exercises[0].note, 'Reduce the load between sets.');
  });
}
