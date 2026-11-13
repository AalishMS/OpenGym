import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/exercise_rename_service.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/utils/set_history.dart';

import 'support/hive_test_harness.dart';

/// Renaming is a label change over stable catalog identities: it must never
/// drop an occurrence's `exerciseId`, split a movement's history, or merge two
/// movements because their names now match.
void main() {
  final harness = HiveTestHarness();
  final old = DateTime.utc(2026, 1, 1);
  const bench = 'builtin:bench-press';
  const squat = 'builtin:squat';
  const plank = 'builtin:plank';
  const analytics = StatisticsAnalyticsService();

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
    await ExerciseCatalog.clear();
  });

  tearDownAll(harness.close);

  WorkoutPlan plan(
    String id,
    List<(String, String?)> exercises, {
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
      for (final (name, exerciseId) in exercises)
        ExerciseTemplate(
          name: name,
          exerciseId: exerciseId,
          sets: 2,
          setTargets: [SetTemplate(weight: 50, reps: 5)],
          note: 'Cue for $name',
        ),
    ],
  );

  WorkoutSession session(
    String id,
    List<(String, String?)> exercises, {
    String splitId = 'split-a',
    bool completed = true,
    DateTime? date,
    DateTime? deletedAt,
    double weight = 60,
    int reps = 8,
  }) => WorkoutSession(
    id: id,
    planName: 'Plan',
    planId: 'p1',
    splitId: splitId,
    date: date ?? DateTime(2026, 2, 1),
    isCompleted: completed,
    updatedAt: old,
    deletedAt: deletedAt,
    dirty: false,
    exercises: [
      for (final (name, exerciseId) in exercises)
        Exercise(
          name: name,
          exerciseId: exerciseId,
          sets: [Set(weight: weight, reps: reps, rpe: 8, note: 'set note')],
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

  test('counts occurrences of the same movement without writing', () async {
    await seed(
      plans: [
        plan('p1', [('Bench Press', bench), ('Squat', squat)]),
        // A legacy row without an ID still resolves to the bundled movement.
        plan('p2', [('bench press', null)]),
        plan('p3', [('Squat', squat)]),
      ],
      sessions: [
        // An earlier occurrence rename kept the ID, so it still counts.
        session('log', [('Flat bench', bench)]),
        session('draft', [('Bench Press', bench)], completed: false),
        session('other', [('Squat', squat)]),
        session('gone', [('Bench Press', bench)], deletedAt: old),
        session('elsewhere', [('Bench Press', bench)], splitId: 'split-b'),
      ],
    );

    final impact = ExerciseRenameService.impact(
      splitId: 'split-a',
      exerciseId: bench,
      to: 'Barbell bench',
    );

    expect(impact.plans, 2);
    expect(impact.workouts, 2);
    expect(impact.otherMovement, isNull);
    expect(HiveService.getSessionById('log')!.dirty, isFalse);
    expect(HiveService.getPlanById('p1')!.exercises.first.name, 'Bench Press');
  });

  test('renames labels and keeps every exercise ID', () async {
    await seed(
      plans: [
        plan('p1', [('Bench Press', bench), ('Squat', squat)]),
        plan('legacy', [('bench press', null)]),
      ],
      sessions: [
        session('log', [('Bench Press', bench), ('Squat', squat)]),
        session('draft', [('Flat bench', bench)], completed: false),
        session('gone', [('Bench Press', bench)], deletedAt: old),
        session('elsewhere', [('Bench Press', bench)], splitId: 'split-b'),
      ],
    );

    final result = await ExerciseRenameService.rename(
      splitId: 'split-a',
      exerciseId: bench,
      to: '  Barbell   bench ',
    );

    expect(result.plans, 2);
    expect(result.workouts, 2);

    final p1 = HiveService.getPlanById('p1')!;
    expect(p1.exercises.first.name, 'Barbell bench');
    expect(p1.exercises.first.exerciseId, bench);
    expect(p1.exercises.first.setTargets!.single.weight, 50);
    expect(p1.exercises.first.note, 'Cue for Bench Press');
    expect(p1.exercises.last.name, 'Squat');
    expect(p1.exercises.last.exerciseId, squat);
    expect(p1.dirty, isTrue);
    expect(p1.updatedAt!.isAfter(old), isTrue);

    // A legacy null ID is filled with the identity it already resolved to.
    final legacy = HiveService.getPlanById('legacy')!.exercises.single;
    expect(legacy.name, 'Barbell bench');
    expect(legacy.exerciseId, bench);

    final log = HiveService.getSessionById('log')!;
    expect(log.exercises.first.name, 'Barbell bench');
    expect(log.exercises.first.exerciseId, bench);
    expect(log.exercises.first.sets.single.weight, 60);
    expect(log.exercises.first.sets.single.note, 'set note');
    expect(log.exercises.first.note, 'Note for Bench Press');
    expect(log.exercises.last.exerciseId, squat);
    expect(log.dirty, isTrue);

    final draft = HiveService.getSessionById('draft')!.exercises.single;
    expect(draft.name, 'Barbell bench');
    expect(draft.exerciseId, bench);

    // Tombstones and other splits are left exactly as they were.
    final gone = HiveService.getSessionById('gone')!;
    expect(gone.exercises.single.name, 'Bench Press');
    expect(gone.dirty, isFalse);
    final elsewhere = HiveService.getSessionById('elsewhere')!;
    expect(elsewhere.exercises.single.name, 'Bench Press');
    expect(elsewhere.dirty, isFalse);
  });

  test('history, records and Previous survive a rename', () async {
    await seed(
      sessions: [
        session(
          'w1',
          [('Bench Press', bench)],
          date: DateTime(2026, 1, 1),
          weight: 60,
        ),
        session(
          'w2',
          [('Bench Press', bench)],
          date: DateTime(2026, 1, 8),
          weight: 70,
        ),
      ],
    );
    List<RecordEvent> records() =>
        analytics.recordEvents(HiveService.getCompletedSessions());
    expect(records().single.session.id, 'w2');

    await ExerciseRenameService.rename(
      splitId: 'split-a',
      exerciseId: bench,
      to: 'Competition bench',
    );
    // A third workout logged under the new label continues the same lift.
    await seed(
      sessions: [
        session(
          'w3',
          [('Competition bench', bench)],
          date: DateTime(2026, 1, 15),
          weight: 75,
        ),
      ],
    );

    final sessions = HiveService.getCompletedSessions();
    expect(analytics.exerciseNames(sessions), ['Bench Press']);
    final events = records();
    expect(events.map((e) => e.session.id), ['w3', 'w2']);
    expect(events.every((e) => e.exerciseId == bench), isTrue);
    final heaviest = events.first.achievements.firstWhere(
      (a) => a.type == RecordType.heaviestWeight,
    );
    expect(heaviest.previousValue, 70);
    expect(
      analytics
          .exerciseProgress(sessions, bench, ExerciseMetric.bestWeight)
          .points
          .length,
      3,
    );
    expect(
      previousExerciseSets(sessions, 'Bench Press').single.weight,
      75,
      reason: 'Previous resolves by ID, not by the old label',
    );
  });

  test('a renamed hold keeps storing seconds', () async {
    await seed(
      sessions: [
        session(
          'h1',
          [('Plank', plank)],
          date: DateTime(2026, 1, 1),
          weight: 0,
          reps: 45,
        ),
        session(
          'h2',
          [('Plank', plank)],
          date: DateTime(2026, 1, 8),
          weight: 0,
          reps: 60,
        ),
      ],
    );

    await ExerciseRenameService.rename(
      splitId: 'split-a',
      exerciseId: plank,
      to: 'Front hold',
    );

    final renamed = HiveService.getSessionById('h2')!.exercises.single;
    expect(renamed.name, 'Front hold');
    expect(ExerciseCatalog.isTimed(renamed.name, renamed.exerciseId), isTrue);
    // A custom movement merely named like a hold is not timed.
    expect(ExerciseCatalog.isTimed('Plank', 'custom-plank-like'), isFalse);

    final sessions = HiveService.getCompletedSessions();
    final stats = analytics.sessionStatistics(
      sessions.firstWhere((s) => s.id == 'h2'),
    );
    expect(stats.totalReps, 0, reason: 'seconds never become reps');
    expect(stats.totalSets, 1);
    final event = analytics.recordEvents(sessions).single;
    expect(event.achievements.single.type, RecordType.longestHold);
    expect(event.achievements.single.value, 60);
  });

  test('a name owned by another movement never merges histories', () async {
    await seed(
      plans: [
        plan('p1', [('Squat', squat), ('Bench Press', bench)]),
      ],
      sessions: [
        session('log', [('Squat', squat), ('Bench Press', bench)]),
      ],
    );

    final impact = ExerciseRenameService.impact(
      splitId: 'split-a',
      exerciseId: squat,
      to: 'bench press',
    );
    expect(impact.otherMovement, 'Bench Press');

    await ExerciseRenameService.rename(
      splitId: 'split-a',
      exerciseId: squat,
      to: 'Bench Press',
    );

    final log = HiveService.getSessionById('log')!;
    expect(log.exercises.map((e) => e.exerciseId), [squat, bench]);
    final sessions = HiveService.getCompletedSessions();
    expect(
      analytics.exerciseDirectory(sessions).keys,
      unorderedEquals([squat, bench]),
    );
  });

  test('an owned custom movement is relabelled in the catalog', () async {
    final custom = await ExerciseCatalog.createCustom('Cable press');
    await seed(
      sessions: [
        session('log', [('Cable press', custom.id)]),
      ],
    );

    await ExerciseRenameService.rename(
      splitId: 'split-a',
      exerciseId: custom.id,
      to: 'Standing cable press',
    );

    final definition = ExerciseCatalog.getById(custom.id)!;
    expect(definition.name, 'Standing cable press');
    expect(definition.aliases, contains('Cable press'));
    expect(
      HiveService.getSessionById('log')!.exercises.single.exerciseId,
      custom.id,
    );
    // Bundled labels are permanent.
    await ExerciseRenameService.rename(
      splitId: 'split-a',
      exerciseId: bench,
      to: 'Flat bench',
    );
    expect(ExerciseCatalog.getById(bench)!.name, 'Bench Press');
  });

  test('rejects empty names before writing', () async {
    expect(ExerciseRenameService.validationMessage('   '), isNotNull);
    expect(ExerciseRenameService.validationMessage('x' * 101), isNotNull);
    expect(ExerciseRenameService.validationMessage('Flat bench'), isNull);
    await seed(
      sessions: [
        session('log', [('Bench Press', bench)]),
      ],
    );
    await expectLater(
      ExerciseRenameService.rename(
        splitId: 'split-a',
        exerciseId: bench,
        to: ' ',
      ),
      throwsArgumentError,
    );
    expect(HiveService.getSessionById('log')!.dirty, isFalse);
  });
}
