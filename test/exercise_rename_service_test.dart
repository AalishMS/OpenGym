import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_definition.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/exercise_name_adoption.dart';
import 'package:gymapp/services/exercise_rename_service.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/utils/set_history.dart';

import 'support/hive_test_harness.dart';

/// A movement has one name, kept in the catalog. Renaming changes what every
/// occurrence shows without rewriting plans or workouts, never drops an
/// occurrence's `exerciseId`, and never merges two movements unless asked to.
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

  test('counts usage across every split without writing', () async {
    await seed(
      plans: [
        plan('p1', [('Bench Press', bench), ('Squat', squat)]),
        // A legacy row without an ID still resolves to the bundled movement.
        plan('p2', [('bench press', null)]),
        plan('p3', [('Squat', squat)]),
        plan('removed', [('Bench Press', bench)], deletedAt: old),
      ],
      sessions: [
        // A snapshot under another name keeps the ID, so it still counts.
        session('log', [('Flat bench', bench)]),
        session('draft', [('Bench Press', bench)], completed: false),
        session('other', [('Squat', squat)]),
        session('gone', [('Bench Press', bench)], deletedAt: old),
        session('elsewhere', [('Bench Press', bench)], splitId: 'split-b'),
      ],
    );

    final usage = ExerciseRenameService.usage(bench);

    expect(usage.plans, 2);
    expect(usage.workouts, 3);
    expect(ExerciseRenameService.usage('builtin:plank').isEmpty, isTrue);
    expect(HiveService.getSessionById('log')!.dirty, isFalse);
  });

  test('renaming changes the name everywhere and rewrites nothing', () async {
    await seed(
      plans: [
        plan('p1', [('Bench Press', bench), ('Squat', squat)]),
        plan('legacy', [('bench press', null)]),
      ],
      sessions: [
        session('log', [('Bench Press', bench), ('Squat', squat)]),
        session('elsewhere', [('Bench Press', bench)], splitId: 'split-b'),
      ],
    );

    await ExerciseRenameService.rename(
      exerciseId: bench,
      currentName: 'Bench Press',
      to: '  Barbell   bench ',
    );

    // The bundled movement keeps its ID; the account's copy has the name.
    final definition = ExerciseCatalog.getById(bench)!;
    expect(definition.name, 'Barbell bench');
    expect(definition.builtIn, isTrue);
    expect(definition.dirty, isTrue);
    expect(definition.aliases, contains('Bench Press'));
    expect(ExerciseCatalog.stored.map((d) => d.id), contains(bench));

    // Every occurrence shows it, whatever snapshot it stored, in any split.
    expect(ExerciseCatalog.label('Bench Press', bench), 'Barbell bench');
    expect(ExerciseCatalog.label('bench press'), 'Barbell bench');
    expect(ExerciseCatalog.findByName('Bench Press')!.id, bench);

    // Plans and workouts are not rewritten.
    final p1 = HiveService.getPlanById('p1')!;
    expect(p1.exercises.first.name, 'Bench Press');
    expect(p1.dirty, isFalse);
    final log = HiveService.getSessionById('log')!;
    expect(log.exercises.first.name, 'Bench Press');
    expect(log.exercises.first.exerciseId, bench);
    expect(log.dirty, isFalse);
  });

  test('a renamed bundled movement keeps its library aliases', () async {
    const press = 'builtin:dumbbell-press';
    expect(ExerciseCatalog.getById(press)?.name, 'Dumbbell Press');
    await ExerciseRenameService.rename(
      exerciseId: press,
      currentName: 'Dumbbell Press',
      to: 'DB press',
    );
    expect(ExerciseCatalog.findByName('DB Bench Press')!.id, press);
    expect(ExerciseCatalog.findByName('Dumbbell Press')!.id, press);
    expect(ExerciseCatalog.label('Dumbbell Chest Press'), 'DB press');
  });

  test('a case-only rename keeps no duplicate alias', () async {
    await ExerciseRenameService.rename(
      exerciseId: bench,
      currentName: 'Bench Press',
      to: 'bench press',
    );
    final definition = ExerciseCatalog.getById(bench)!;
    expect(definition.name, 'bench press');
    expect(
      definition.aliases.where(
        (a) => ExerciseCatalog.normalize(a) == 'bench press',
      ),
      isEmpty,
    );
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
      exerciseId: bench,
      currentName: 'Bench Press',
      to: 'Competition bench',
    );
    // A third workout logged under the new name continues the same lift.
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
    expect(analytics.exerciseNames(sessions), ['Competition bench']);
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
      reason: 'Previous resolves by ID, not by the old name',
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
      exerciseId: plank,
      currentName: 'Plank',
      to: 'Front hold',
    );

    final renamed = HiveService.getSessionById('h2')!.exercises.single;
    expect(
      ExerciseCatalog.label(renamed.name, renamed.exerciseId),
      'Front hold',
    );
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

  test('a name another movement goes by is refused until merged', () async {
    await seed(
      sessions: [
        session('log', [('Squat', squat), ('Bench Press', bench)]),
      ],
    );

    expect(ExerciseRenameService.nameOwner(squat, 'bench press')?.id, bench);
    expect(ExerciseRenameService.nameOwner(bench, 'Bench Press'), isNull);
    await expectLater(
      ExerciseRenameService.rename(
        exerciseId: squat,
        currentName: 'Squat',
        to: 'Bench Press',
      ),
      throwsFormatException,
    );
    expect(ExerciseCatalog.getById(squat)!.name, 'Squat');
    var sessions = HiveService.getCompletedSessions();
    expect(
      analytics.exerciseDirectory(sessions).keys,
      unorderedEquals([squat, bench]),
    );

    await ExerciseRenameService.merge(sourceId: squat, targetId: bench);

    sessions = HiveService.getCompletedSessions();
    expect(analytics.exerciseDirectory(sessions).keys, [bench]);
    expect(ExerciseCatalog.label('Squat', squat), 'Bench Press');
    // The log itself, sets and snapshots included, is untouched.
    final log = HiveService.getSessionById('log')!;
    expect(log.exercises.map((e) => e.exerciseId), [squat, bench]);
    expect(log.exercises.first.name, 'Squat');
    expect(log.dirty, isFalse);
    // Merged names point at the movement they joined.
    expect(ExerciseRenameService.nameOwner(bench, 'Squat'), isNull);
  });

  test('a custom movement keeps its old name as a search term', () async {
    final custom = await ExerciseCatalog.createCustom('Cable press');
    await ExerciseRenameService.rename(
      exerciseId: custom.id,
      currentName: 'Cable press',
      to: 'Standing cable press',
    );
    final definition = ExerciseCatalog.getById(custom.id)!;
    expect(definition.name, 'Standing cable press');
    expect(definition.aliases, contains('Cable press'));
    expect(ExerciseCatalog.findByName('Cable press')!.id, custom.id);
  });

  test(
    'a movement the catalog has not seen is recorded, then renamed',
    () async {
      final id = ExerciseCatalog.legacyId('Hip thrust machine');
      expect(ExerciseCatalog.getById(id), isNull);
      await ExerciseRenameService.rename(
        exerciseId: id,
        currentName: 'Hip thrust machine',
        to: 'Glute drive',
      );
      final definition = ExerciseCatalog.getById(id)!;
      expect(definition.name, 'Glute drive');
      expect(definition.aliases, ['Hip thrust machine']);
      expect(ExerciseCatalog.label('Hip thrust machine', id), 'Glute drive');
    },
  );

  test('rejects empty names before writing', () async {
    expect(ExerciseRenameService.validationMessage('   '), isNotNull);
    expect(ExerciseRenameService.validationMessage('x' * 101), isNotNull);
    expect(ExerciseRenameService.validationMessage('Flat bench'), isNull);
    await expectLater(
      ExerciseRenameService.rename(
        exerciseId: bench,
        currentName: 'Bench Press',
        to: ' ',
      ),
      throwsFormatException,
    );
    expect(ExerciseCatalog.stored, isEmpty);
  });
  group('merging a timed exercise with one counted in reps', () {
    test(
      'is refused between built-in exercises, in either direction',
      () async {
        expect(ExerciseCatalog.canMerge(bench, plank), isFalse);
        expect(ExerciseCatalog.canMerge(plank, bench), isFalse);
        expect(ExerciseCatalog.canMerge(bench, squat), isTrue);
        expect(
          ExerciseRenameService.mergeBlock(bench, plank),
          "Bench Press is counted in reps and Plank is timed, so they can't be "
          'merged.',
        );
        expect(
          ExerciseRenameService.mergeBlock(plank, bench),
          "Plank is timed and Bench Press is counted in reps, so they can't be "
          'merged.',
        );
        await expectLater(
          ExerciseRenameService.merge(sourceId: bench, targetId: plank),
          throwsFormatException,
        );
        // Bench reps are still reps.
        expect(ExerciseCatalog.canonicalId(bench), bench);
        expect(ExerciseCatalog.isTimed('Bench Press', bench), isFalse);
      },
    );

    test('a custom exercise may join a timed one, with a caution', () async {
      final custom = await ExerciseCatalog.createCustom('Front hold');
      expect(ExerciseRenameService.mergeBlock(custom.id, plank), isNull);
      expect(
        ExerciseRenameService.mergeCaution(custom.id, plank),
        'Plank is timed, so the reps logged for Front hold will be read as '
        'seconds.',
      );
      // Two exercises counted the same way need no caution.
      expect(ExerciseRenameService.mergeCaution(custom.id, bench), isNull);

      await ExerciseRenameService.merge(sourceId: custom.id, targetId: plank);
      expect(ExerciseCatalog.isTimed('Front hold', custom.id), isTrue);
      // A timed exercise can't join a custom one: its seconds would be reps.
      final other = await ExerciseCatalog.createCustom('My hold');
      expect(ExerciseCatalog.canMerge('builtin:side-plank', other.id), isFalse);
    });
  });

  group('an exercise merged elsewhere after it was confirmed', () {
    const press = 'builtin:dumbbell-press';

    test('is not merged on: its new owner keeps its own history', () async {
      final custom = await ExerciseCatalog.createCustom('DB Press');
      // Confirmed here: DB Press into Dumbbell Press. A sync then lands
      // DB Press merged into Bench Press.
      await ExerciseCatalog.merge(custom.id, bench);
      await expectLater(
        ExerciseRenameService.merge(sourceId: custom.id, targetId: press),
        throwsA(isA<ExerciseChangedException>()),
      );
      // Bench Press, which nobody confirmed, is still its own exercise.
      expect(ExerciseCatalog.canonicalId(bench), bench);
      expect(ExerciseCatalog.getById(bench)!.mergedIntoId, isNull);
      expect(ExerciseCatalog.canonicalId(custom.id), bench);
    });

    test('is not merged into: the target named is the target used', () async {
      final custom = await ExerciseCatalog.createCustom('DB Press');
      // The confirmed target was itself merged away meanwhile.
      await ExerciseCatalog.merge(press, bench);
      await expectLater(
        ExerciseRenameService.merge(sourceId: custom.id, targetId: press),
        throwsA(isA<ExerciseChangedException>()),
      );
      expect(ExerciseCatalog.canonicalId(custom.id), custom.id);
    });

    test('is not renamed through to its new owner', () async {
      final custom = await ExerciseCatalog.createCustom('DB Press');
      await ExerciseCatalog.merge(custom.id, bench);
      await expectLater(
        ExerciseRenameService.rename(
          exerciseId: custom.id,
          currentName: 'DB Press',
          to: 'Flat dumbbell press',
        ),
        throwsA(isA<ExerciseChangedException>()),
      );
      expect(ExerciseCatalog.getById(bench)!.name, 'Bench Press');
    });
  });

  group('names given before a movement had one name', () {
    const deadlift = 'builtin:deadlift';

    test('a bundled movement takes the name its plans use', () async {
      await seed(
        plans: [
          plan('older', [('Flat bench', bench), ('squat', squat)]),
          plan('newer', [('Barbell bench', bench), ('Squat', plank)])
            ..updatedAt = DateTime.utc(2026, 3),
        ],
        sessions: [
          // Only logs have it, so the latest log's name is kept.
          session('a', [('Pull', deadlift)], date: DateTime(2026, 1, 1)),
          session('b', [('Conventional pull', deadlift)]),
          // A per-workout name never outranks the plan's.
          session('c', [('Paused bench', bench)], date: DateTime(2027)),
        ],
      );
      final custom = await ExerciseCatalog.createCustom('Cable press');
      await seed(
        plans: [
          plan('custom', [('Old cable press', custom.id)]),
        ],
      );

      expect(await ExerciseNameAdoption.adopt(userId: null), 2);

      final renamed = ExerciseCatalog.getById(bench)!;
      expect(renamed.name, 'Barbell bench');
      expect(renamed.updatedAt!.millisecondsSinceEpoch, 0);
      expect(renamed.dirty, isTrue);
      expect(ExerciseCatalog.getById(deadlift)!.name, 'Conventional pull');
      // Case only: unchanged.
      expect(ExerciseCatalog.getById(squat)!.name, 'Squat');
      // Another movement already goes by Squat, so Plank stays Plank.
      expect(ExerciseCatalog.getById(plank)!.name, 'Plank');
      // A custom movement's catalog name was always kept current.
      expect(ExerciseCatalog.getById(custom.id)!.name, 'Cable press');

      // A movement the account has renamed since is never overwritten.
      expect(await ExerciseNameAdoption.adopt(userId: null), 0);
    });

    test('a name merged away from is not brought back', () async {
      final custom = await ExerciseCatalog.createCustom('DB Press');
      await ExerciseRenameService.merge(
        sourceId: custom.id,
        targetId: 'builtin:dumbbell-press',
      );
      await seed(
        plans: [
          plan('p', [('DB Press', custom.id)]),
        ],
      );
      expect(await ExerciseNameAdoption.adopt(userId: null), 0);
      expect(
        ExerciseCatalog.getById('builtin:dumbbell-press')!.name,
        'Dumbbell Press',
      );
    });

    test('runs once, after the account has plans', () async {
      SharedPreferences.setMockInitialValues({});
      await ExerciseNameAdoption.run(userId: null);
      await seed(
        plans: [
          plan('p', [('Flat bench', bench)]),
        ],
      );
      await ExerciseNameAdoption.run(userId: null);
      expect(ExerciseCatalog.getById(bench)!.name, 'Flat bench');
      await ExerciseCatalog.clear();
      await ExerciseNameAdoption.run(userId: null);
      expect(ExerciseCatalog.getById(bench)!.name, 'Bench Press');
    });

    test('an account with workouts but no plans keeps its names too', () async {
      SharedPreferences.setMockInitialValues({});
      await seed(
        sessions: [
          session('log', [('Flat bench', bench)]),
        ],
      );
      await ExerciseNameAdoption.run(userId: null);
      expect(ExerciseCatalog.getById(bench)!.name, 'Flat bench');
    });

    test('a name that could not be saved is tried again next start', () async {
      SharedPreferences.setMockInitialValues({});
      await seed(
        plans: [
          plan('p', [('Flat bench', bench), ('Comp squat', squat)]),
        ],
      );
      // A row left by another account makes every catalog write fail.
      await ExerciseCatalog.put(
        const ExerciseDefinition(id: 'theirs', name: 'Theirs', userId: 'x'),
      );
      await ExerciseNameAdoption.run(userId: null);
      expect(ExerciseCatalog.getById(bench)!.name, 'Bench Press');

      await ExerciseCatalog.clear();
      await ExerciseNameAdoption.run(userId: null);
      expect(ExerciseCatalog.getById(bench)!.name, 'Flat bench');
      expect(ExerciseCatalog.getById(squat)!.name, 'Comp squat');
    });
  });
}
