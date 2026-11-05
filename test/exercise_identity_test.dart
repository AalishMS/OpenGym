import 'dart:convert';

import 'package:gymapp/services/adopt_local_data.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymapp/data/exercise_library.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_definition.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/backup_service.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/exercise_identity_migration.dart';
import 'package:gymapp/services/pr_tracking_service.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/services/training_block_graph.dart';
import 'package:gymapp/services/workout_session_initializer.dart';
import 'package:gymapp/utils/set_history.dart';

import 'support/hive_test_harness.dart';

const customId = '11111111-1111-4111-8111-111111111111';
const otherId = '22222222-2222-4222-8222-222222222222';
const pressId = 'builtin:dumbbell-press';
const analytics = StatisticsAnalyticsService();

gym.Set set(double weight) => gym.Set(weight: weight, reps: 8);
WorkoutSession session(
  String name,
  double weight,
  int day, {
  String? exerciseId,
}) => WorkoutSession(
  id: 'session-$day',
  splitId: 'split',
  planId: 'plan',
  date: DateTime(2026, 11, day),
  planName: 'Push',
  exercises: [
    Exercise(name: name, exerciseId: exerciseId, sets: [set(weight)]),
  ],
);
TrainingBlockGraph graph(List<WorkoutSession> sessions) => TrainingBlockGraph(
  ownerId: null,
  activeSplitId: 'split',
  splits: [Split(id: 'split', name: 'My split', createdAt: DateTime(2026))],
  plans: [
    WorkoutPlan(
      id: 'plan',
      splitId: 'split',
      name: 'Push',
      exercises: [ExerciseTemplate(name: 'dumbbell   press', sets: 2)],
    ),
  ],
  sessions: sessions,
);

void main() {
  final storage = HiveTestHarness();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
  });
  tearDown(storage.close);

  test('bundled IDs are unique and aliases never create another movement', () {
    final definitions = ExerciseLibrary.definitions;
    expect(definitions.map((d) => d.id).toSet(), hasLength(definitions.length));
    expect(ExerciseCatalog.identity('  DUMBBELL   press  '), pressId);
    expect(ExerciseCatalog.identity('DB Bench Press'), pressId);
    expect(ExerciseCatalog.identity('DB Press'), isNot(pressId));
    expect(ExerciseCatalog.identity('Incline Dumbbell Press'), isNot(pressId));
    expect(ExerciseCatalog.identity('Dumbbell Shoulder Press'), isNot(pressId));
    expect(ExerciseCatalog.search('DB Bench'), hasLength(1));
  });

  test('migration is repeatable and retains names, sets, notes, and dates', () {
    final original = graph([
      session('Dumbbell Press', 20, 1),
      session('DB Bench Press', 22, 2),
      session('DB Press', 24, 3),
      session('  db   press ', 25, 4),
    ]);
    final migrated = ExerciseIdentityMigration.prepare(original);
    expect(migrated.plans.single.exercises.single.exerciseId, pressId);
    expect(
      migrated.sessions.take(2).map((s) => s.exercises.single.exerciseId),
      [pressId, pressId],
    );
    expect(
      migrated.sessions[2].exercises.single.exerciseId,
      migrated.sessions[3].exercises.single.exerciseId,
    );
    expect(migrated.exerciseDefinitions, hasLength(1));
    for (var i = 0; i < original.sessions.length; i++) {
      final before = original.sessions[i];
      final after = migrated.sessions[i];
      expect(after.exercises.single.name, before.exercises.single.name);
      expect(
        after.exercises.single.sets.single.toJson(),
        before.exercises.single.sets.single.toJson(),
      );
      expect(after.date, before.date);
      expect(before.exercises.single.exerciseId, isNull);
    }
    expect(
      jsonEncode(ExerciseIdentityMigration.prepare(migrated).toJson()),
      jsonEncode(migrated.toJson()),
    );
  });

  test(
    'explicit IDs separate exercises even when display names are identical',
    () {
      final sessions = [
        session('Press', 20, 1, exerciseId: customId),
        session('Press', 80, 2, exerciseId: otherId),
        session('Renamed press', 22, 3, exerciseId: customId),
      ];
      final lifts = analytics.liftSummaries(
        sessions,
        ExerciseMetric.bestWeight,
      );
      expect(lifts, hasLength(2));
      expect(
        lifts
            .singleWhere((l) => l.exerciseId == customId)
            .progress
            .points
            .map((p) => p.value),
        [20, 22],
      );
      expect(
        lifts
            .singleWhere((l) => l.exerciseId == otherId)
            .progress
            .points
            .single
            .value,
        80,
      );
    },
  );

  test(
    'custom creation reuses exact names and survives reopening Hive',
    () async {
      final first = await ExerciseCatalog.createCustom('My cable press');
      final reused = await ExerciseCatalog.createCustom('  my   CABLE press ');
      expect(reused.id, first.id);
      expect(first.id, isNot(ExerciseCatalog.legacyId(first.name)));
      await Hive.box<dynamic>(ExerciseCatalog.boxName).close();
      await ExerciseCatalog.open();
      expect(ExerciseCatalog.search('my cable').single.id, first.id);
    },
  );

  test(
    'merging combines strength, records, weekly volume and previous sets',
    () async {
      await ExerciseCatalog.put(
        const ExerciseDefinition(id: customId, name: 'DB Press'),
      );
      final sessions = [
        session('DB Press', 20, 1, exerciseId: customId),
        session('Dumbbell Press', 25, 2, exerciseId: pressId),
      ];
      await ExerciseCatalog.merge(customId, pressId);
      expect(analytics.exerciseDirectory(sessions), {
        pressId: 'Dumbbell Press',
      });
      final lift =
          analytics.liftSummaries(sessions, ExerciseMetric.bestWeight).single;
      expect(lift.progress.points.map((p) => p.value), [20, 25]);
      expect(
        analytics.recordEvents(sessions).map((e) => e.exerciseId).toSet(),
        {pressId},
      );
      expect(
        analytics
            .weeklyVolume(
              sessions,
              exerciseName: pressId,
              now: DateTime(2026, 11, 3),
            )
            .fold<double>(0, (sum, week) => sum + week.volumeLoad),
        360,
      );
      expect(previousExerciseSets(sessions, pressId).single.weight, 25);
      expect(
        PRTrackingService.checkAgainstHistory([
          Exercise(
            name: 'Dumbbell Press',
            exerciseId: pressId,
            sets: [set(19)],
          ),
        ], sessions),
        isEmpty,
      );
      expect(sessions.first.exercises.single.name, 'DB Press');
      expect(sessions.first.exercises.single.exerciseId, customId);
      expect(
        ExerciseCatalog.search('DB Press').map((d) => d.id),
        contains(pressId),
      );
    },
  );

  test(
    'merged duplicates in one session contribute all sets to one record event',
    () async {
      await ExerciseCatalog.put(
        const ExerciseDefinition(id: customId, name: 'DB Press'),
      );
      await ExerciseCatalog.merge(customId, pressId);
      final original = session('DB Press', 20, 1, exerciseId: customId);
      final data = [
        original.copyWith(
          exercises: [
            ...original.exercises,
            Exercise(
              name: 'Dumbbell Press',
              exerciseId: pressId,
              sets: [set(25)],
            ),
          ],
        ),
      ];
      expect(analytics.recordEvents(data), hasLength(1));
      expect(
        analytics
            .exerciseProgress(data, pressId, ExerciseMetric.sessionVolume)
            .points
            .single
            .value,
        360,
      );
    },
  );

  test(
    'initialization matches identity after a rename and retains occurrences',
    () {
      final source = session('Old label', 30, 1, exerciseId: customId);
      final plan = WorkoutPlan(
        id: 'plan',
        splitId: 'split',
        name: 'Push',
        exercises: [
          ExerciseTemplate(name: 'New label', exerciseId: customId, sets: 1),
        ],
      );
      final initialized = WorkoutSessionInitializer.initialize(
        plan: plan,
        week: TrainingWeek(
          id: 'week',
          splitId: 'split',
          blockId: 'block',
          number: 2,
          createdAt: DateTime(2026),
        ),
        previousSession: source,
      );
      expect(initialized.exercises.single.name, 'New label');
      expect(initialized.exercises.single.exerciseId, customId);
      expect(initialized.exercises.single.sets.single.weight, 30);
    },
  );

  test(
    'opposing offline merges have a deterministic visible representative',
    () async {
      await ExerciseCatalog.put(
        const ExerciseDefinition(
          id: customId,
          name: 'One',
          mergedIntoId: otherId,
        ),
      );
      await ExerciseCatalog.put(
        const ExerciseDefinition(
          id: otherId,
          name: 'Two',
          mergedIntoId: customId,
        ),
      );
      expect(ExerciseCatalog.canonicalId(customId), customId);
      expect(ExerciseCatalog.canonicalId(otherId), customId);
      expect(
        ExerciseCatalog.active.where((d) => [customId, otherId].contains(d.id)),
        hasLength(1),
      );
    },
  );

  test(
    'restoring an older graph cannot remove an existing merge redirect',
    () async {
      const source = ExerciseDefinition(id: customId, name: 'DB Press');
      final original = TrainingBlockMigration.prepareGraph(
        graph([
          session('DB Press', 20, 1, exerciseId: customId),
        ]).copyWith(exerciseDefinitions: [source]),
      );
      await TrainingBlockRestore().replace(graph: original);
      await ExerciseCatalog.merge(customId, pressId);
      await TrainingBlockRestore().replace(graph: original);
      expect(ExerciseCatalog.canonicalId(customId), pressId);
      final restored = HiveService.getCompletedSessions().single;
      expect(restored.exercises.single.name, 'DB Press');
      expect(restored.exercises.single.sets.single.weight, 20);
    },
  );

  test(
    'first sign-in adopts offline custom definitions without changing IDs',
    () async {
      await ExerciseCatalog.put(
        const ExerciseDefinition(id: customId, name: 'My custom press'),
      );
      await AdoptLocalData.prepareLocalForUser('exercise-adoption-owner');
      final adopted = ExerciseCatalog.getById(customId)!;
      expect(adopted.userId, 'exercise-adoption-owner');
      expect(adopted.dirty, isTrue);
      expect(adopted.id, customId);
    },
  );

  test(
    'account handover clears the previous account exercise catalog',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastUserId', 'previous-exercise-owner');
      await ExerciseCatalog.put(
        const ExerciseDefinition(
          id: customId,
          name: 'Private custom press',
          userId: 'previous-exercise-owner',
        ),
      );
      await AdoptLocalData.prepareLocalForUser('next-exercise-owner');
      expect(ExerciseCatalog.stored, isEmpty);
      expect(ExerciseCatalog.findByName('Private custom press'), isNull);
    },
  );

  test(
    'v6 backup retains custom IDs and redirects; foreign restore remaps both',
    () async {
      await ExerciseCatalog.put(
        const ExerciseDefinition(id: customId, name: 'DB Press'),
      );
      await ExerciseCatalog.merge(customId, pressId);
      final input = graph([session('DB Press', 20, 1, exerciseId: customId)]);
      final exported = BackupService.exportData(
        splits: input.splits,
        activeSplitId: 'split',
        plans: input.plans,
        sessions: input.sessions,
        settings: {},
        exerciseDefinitions: ExerciseCatalog.stored,
      );
      final parsed = jsonDecode(exported.jsonString) as Map<String, dynamic>;
      expect(parsed['version'], 6);
      final imported = BackupService.importData(
        exported.jsonString,
        userId: 'another-owner',
      );
      expect(imported.success, isTrue, reason: imported.errorMessage);
      final d = imported.graph!.exerciseDefinitions.single;
      expect(d.id, isNot(customId));
      expect(d.mergedIntoId, pressId);
      expect(imported.sessions!.single.exercises.single.exerciseId, d.id);
      expect(imported.sessions!.single.exercises.single.sets.single.weight, 20);
      parsed['exerciseDefinitions'] = [];
      expect(
        BackupService.importData(jsonEncode(parsed), userId: null).success,
        isFalse,
      );
    },
  );
  test('migration and backup retain long legacy custom names', () {
    final name = List.filled(20, 'Legacy custom press').join(' ');
    final input = graph([session(name, 20, 1)]);
    final migrated = ExerciseIdentityMigration.prepare(input);
    final definition = migrated.exerciseDefinitions.single;
    expect(definition.name, name);
    expect(ExerciseDefinition.fromJson(definition.toJson()).name, name);
    final exported = BackupService.exportData(
      splits: input.splits,
      activeSplitId: 'split',
      plans: input.plans,
      sessions: input.sessions,
      settings: {},
    );
    final imported = BackupService.importData(
      exported.jsonString,
      userId: null,
    );
    expect(imported.success, isTrue, reason: imported.errorMessage);
    expect(imported.sessions!.single.exercises.single.name, name);
  });
}
