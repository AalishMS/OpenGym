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
    'explicit inheritance matches normalized duplicate occurrences in current template order',
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
          Exercise(name: 'Removed', sets: [gym.Set(reps: 4, weight: 40)]),
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
      expect(
        session.exercises.map((e) => e.name),
        current.exercises.map((e) => e.name),
      );
      expect(session.exercises.map((e) => e.sets.first.weight), [90, 20, 60]);
      expect(session.exercises.first.note, 'Current cue');
      expect(session.exercises.first.sets.single.note, isNull);
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
