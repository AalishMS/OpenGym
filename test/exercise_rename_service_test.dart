import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/exercise_rename_service.dart';
import 'package:gymapp/services/hive_service.dart';

import 'support/hive_test_harness.dart';

void main() {
  final harness = HiveTestHarness();
  final old = DateTime.utc(2026, 1, 1);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
    );
    await harness.open(includeSplits: true);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  tearDownAll(harness.close);

  WorkoutPlan plan(
    String id,
    List<String> names, {
    String splitId = 'split-a',
    DateTime? deletedAt,
  }) => WorkoutPlan(
    id: id,
    name: 'Plan $id',
    splitId: splitId,
    updatedAt: old,
    deletedAt: deletedAt,
    dirty: false,
    exercises: [
      for (final name in names)
        ExerciseTemplate(
          name: name,
          sets: 2,
          setTargets: [SetTemplate(weight: 50, reps: 5)],
          note: 'Cue for $name',
        ),
    ],
  );

  WorkoutSession session(
    String id,
    List<String> names, {
    String splitId = 'split-a',
    bool completed = true,
    DateTime? deletedAt,
  }) => WorkoutSession(
    id: id,
    planName: 'Plan',
    planId: 'p1',
    splitId: splitId,
    date: DateTime(2026, 2, 1),
    isCompleted: completed,
    updatedAt: old,
    deletedAt: deletedAt,
    dirty: false,
    exercises: [
      for (final name in names)
        Exercise(
          name: name,
          sets: [Set(weight: 60, reps: 8, rpe: 8, note: 'set note')],
          note: 'Note for $name',
        ),
    ],
  );

  Future<void> seed({
    List<WorkoutPlan> plans = const [],
    List<WorkoutSession> sessions = const [],
  }) async {
    for (final p in plans) {
      await HiveService.putPlanRaw(p);
    }
    for (final s in sessions) {
      await HiveService.putSessionRaw(s);
    }
  }

  List<String> planNames(String id) => [
    for (final e in HiveService.getPlanById(id)!.exercises) e.name,
  ];
  List<String> sessionNames(String id) => [
    for (final e in HiveService.getSessionById(id)!.exercises) e.name,
  ];

  test('counts matching plans and workouts without writing', () async {
    await seed(
      plans: [
        plan('p1', ['Bench press', 'Squat']),
        plan('p2', ['Squat']),
      ],
      sessions: [
        session('log', ['Bench press']),
        session('draft', ['bench press'], completed: false),
        session('other', ['Squat']),
      ],
    );

    final impact = ExerciseRenameService.impact(
      splitId: 'split-a',
      from: 'Bench press',
      to: 'Barbell bench press',
    );

    expect(impact.plans, 1);
    expect(impact.workouts, 2);
    expect(impact.merges, isFalse);
    expect(planNames('p1'), ['Bench press', 'Squat']);
    expect(HiveService.getPlanById('p1')!.dirty, isFalse);
    expect(HiveService.getSessionById('log')!.dirty, isFalse);
  });

  test('renames plans, drafts and logs and marks them for sync', () async {
    await seed(
      plans: [
        plan('p1', ['Bench press', 'Squat']),
        plan('untouched', ['Squat']),
      ],
      sessions: [
        session('log', ['Bench press', 'Squat']),
        session('draft', ['Bench press'], completed: false),
        session('unrelated', ['Squat']),
      ],
    );

    final changed = await ExerciseRenameService.rename(
      splitId: 'split-a',
      from: 'Bench press',
      to: '  Barbell bench press ',
    );

    expect((changed.plans, changed.workouts), (1, 2));
    expect(planNames('p1'), ['Barbell bench press', 'Squat']);
    expect(sessionNames('log'), ['Barbell bench press', 'Squat']);
    expect(sessionNames('draft'), ['Barbell bench press']);
    for (final saved in [
      HiveService.getPlanById('p1')!,
      HiveService.getSessionById('log')!,
      HiveService.getSessionById('draft')!,
    ]) {
      final (dirty, updatedAt) = switch (saved) {
        WorkoutPlan p => (p.dirty, p.updatedAt),
        WorkoutSession s => (s.dirty, s.updatedAt),
        _ => throw StateError('unexpected'),
      };
      expect(dirty, isTrue);
      expect(updatedAt!.isAfter(old), isTrue);
    }
    // Records with nothing to rename keep their sync state.
    expect(HiveService.getPlanById('untouched')!.dirty, isFalse);
    expect(HiveService.getSessionById('unrelated')!.dirty, isFalse);
    expect(HiveService.getSessionById('unrelated')!.updatedAt, old);

    // Everything but the name is kept.
    final template = HiveService.getPlanById('p1')!.exercises.first;
    expect(template.sets, 2);
    expect(template.setTargets!.single.weight, 50);
    expect(template.note, 'Cue for Bench press');
    final logged = HiveService.getSessionById('log')!;
    expect(logged.isCompleted, isTrue);
    expect(logged.exercises.first.note, 'Note for Bench press');
    final set = logged.exercises.first.sets.single;
    expect((set.weight, set.reps, set.rpe, set.note), (60, 8, 8, 'set note'));
  });

  test('matching ignores case and surrounding or repeated spaces', () async {
    await seed(
      plans: [
        plan('p1', ['  BENCH   press ']),
      ],
      sessions: [
        session('log', ['bench press']),
        session('near', ['Bench presses']),
      ],
    );

    final changed = await ExerciseRenameService.rename(
      splitId: 'split-a',
      from: 'Bench Press',
      to: 'Flat bench',
    );

    expect((changed.plans, changed.workouts), (1, 1));
    expect(planNames('p1'), ['Flat bench']);
    expect(sessionNames('log'), ['Flat bench']);
    expect(sessionNames('near'), ['Bench presses']);
  });

  test('other splits and tombstones are untouched', () async {
    final deleted = DateTime.utc(2026, 1, 2);
    await seed(
      plans: [
        plan('mine', ['Row']),
        plan('theirs', ['Row'], splitId: 'split-b'),
        plan('gone', ['Row'], deletedAt: deleted),
      ],
      sessions: [
        session('mine-log', ['Row']),
        session('theirs-log', ['Row'], splitId: 'split-b'),
        session('gone-log', ['Row'], deletedAt: deleted),
      ],
    );

    final impact = ExerciseRenameService.impact(
      splitId: 'split-a',
      from: 'Row',
      to: 'Cable row',
    );
    expect((impact.plans, impact.workouts), (1, 1));

    await ExerciseRenameService.rename(
      splitId: 'split-a',
      from: 'Row',
      to: 'Cable row',
    );

    expect(planNames('mine'), ['Cable row']);
    expect(sessionNames('mine-log'), ['Cable row']);
    for (final id in ['theirs', 'gone']) {
      expect(planNames(id), ['Row']);
      expect(HiveService.getPlanById(id)!.dirty, isFalse);
      expect(HiveService.getPlanById(id)!.updatedAt, old);
    }
    for (final id in ['theirs-log', 'gone-log']) {
      expect(sessionNames(id), ['Row']);
      expect(HiveService.getSessionById(id)!.dirty, isFalse);
      expect(HiveService.getSessionById(id)!.updatedAt, old);
    }
    expect(HiveService.getSessionById('gone-log')!.deletedAt, deleted);
  });

  test('renaming to an existing name merges and keeps both entries', () async {
    await seed(
      plans: [
        plan('both', ['DB press', 'Dumbbell press']),
      ],
      sessions: [
        session('old', ['DB press']),
        session('new', ['Dumbbell press']),
        session('both-log', ['DB press', 'Dumbbell press']),
      ],
    );

    final impact = ExerciseRenameService.impact(
      splitId: 'split-a',
      from: 'DB press',
      to: 'dumbbell press',
    );
    expect(impact.merges, isTrue);
    expect((impact.plans, impact.workouts), (1, 2));

    await ExerciseRenameService.rename(
      splitId: 'split-a',
      from: 'DB press',
      to: 'Dumbbell press',
    );

    expect(planNames('both'), ['Dumbbell press', 'Dumbbell press']);
    expect(sessionNames('old'), ['Dumbbell press']);
    expect(sessionNames('new'), ['Dumbbell press']);
    expect(sessionNames('both-log'), ['Dumbbell press', 'Dumbbell press']);
    expect(HiveService.getSessionById('new')!.dirty, isFalse);
    expect(
      HiveService.getSessionById('both-log')!.exercises.map((e) => e.note),
      ['Note for DB press', 'Note for Dumbbell press'],
    );
  });

  test('a new name that only changes case is not a merge', () {
    expect(
      ExerciseRenameService.impact(
        splitId: 'split-a',
        from: 'squat',
        to: 'Squat',
      ).merges,
      isFalse,
    );
  });

  test('an empty name is refused', () async {
    await seed(
      plans: [
        plan('p1', ['Squat']),
      ],
    );
    await expectLater(
      ExerciseRenameService.rename(splitId: 'split-a', from: 'Squat', to: ' '),
      throwsArgumentError,
    );
    expect(planNames('p1'), ['Squat']);
  });
}
