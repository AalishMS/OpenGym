import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/backup_service.dart';
import 'package:gymapp/providers/training_block_provider.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:gymapp/services/workout_progression_service.dart';
import 'package:gymapp/services/workout_session_initializer.dart';
import 'package:gymapp/utils/training_block_identity.dart';

import 'support/hive_test_harness.dart';

void main() {
  final storage = HiveTestHarness();
  final now = DateTime.utc(2026, 10, 29);
  const splitId = '8c221550-21ae-4a8e-a059-5545e14d1000';
  late TrainingBlockRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    await HiveService.putSplitRaw(
      Split(id: splitId, name: 'Training', createdAt: now),
    );
    for (final id in ['push', 'pull']) {
      await HiveService.putPlanRaw(
        WorkoutPlan(id: id, name: id, splitId: splitId, exercises: []),
      );
    }
    repo = TrainingBlockRepository(ownerId: () => null);
  });
  tearDown(storage.close);

  test(
    'intended block length survives JSON and Hive without eager weeks',
    () async {
      final block = TrainingBlock.fromJson({
        'id': 'block',
        'splitId': splitId,
        'name': 'Build',
        'position': 0,
        'createdAt': now.toIso8601String(),
        'plannedWeekCount': 4,
      });
      await HiveService.putTrainingBlockRaw(block);
      await Hive.box<TrainingBlock>(HiveService.trainingBlocksBox).close();
      await Hive.openBox<TrainingBlock>(HiveService.trainingBlocksBox);
      expect(
        HiveService.getTrainingBlockById('block')!.toJson()['plannedWeekCount'],
        4,
      );
      expect(HiveService.getAllTrainingWeeksRaw(), isEmpty);
    },
  );

  test('per-workout available week IDs survive JSON and Hive', () async {
    final progress = WorkoutProgress.fromJson({
      'id': 'progress',
      'splitId': splitId,
      'planId': 'push',
      'activeWeekId': 'w2',
      'state': 'ready',
      'revision': 'revision',
      'availableWeekIds': ['w1', 'w2'],
    });
    await HiveService.putWorkoutProgressRaw(progress);
    await Hive.box<WorkoutProgress>(HiveService.workoutProgressBox).close();
    await Hive.openBox<WorkoutProgress>(HiveService.workoutProgressBox);
    expect(
      HiveService.getWorkoutProgressById(
        'progress',
      )!.toJson()['availableWeekIds'],
      ['w1', 'w2'],
    );
  });

  test('a four-week block allocates only its first week', () async {
    final block = await repo.createBlock(
      splitId: splitId,
      name: 'Build',
      weekCount: 4,
    );
    expect(repo.weeksForBlock(splitId, block.id).map((w) => w.number), [1]);
    expect(block.toJson()['plannedWeekCount'], 4);
    expect(HiveService.getAllSessionsRaw(), isEmpty);
  });
  test(
    'legacy normalization hides empty future weeks separately per plan',
    () async {
      final block = TrainingBlock(
        id: 'legacy',
        splitId: splitId,
        name: 'Build',
        position: 0,
        createdAt: now,
      );
      await HiveService.putTrainingBlockRaw(block);
      for (var n = 1; n <= 4; n++) {
        await HiveService.putTrainingWeekRaw(
          TrainingWeek(
            id: 'w$n',
            splitId: splitId,
            blockId: block.id,
            number: n,
            createdAt: now,
          ),
        );
      }
      for (final plan in ['push', 'pull']) {
        await HiveService.putWorkoutProgressRaw(
          WorkoutProgress(
            id: plan,
            splitId: splitId,
            planId: plan,
            activeWeekId: plan == 'push' ? 'w2' : 'w1',
            state: WorkoutProgressState.ready,
            revision: plan,
          ),
        );
      }
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(
        HiveService.getTrainingBlockById(
          'legacy',
        )!.toJson()['plannedWeekCount'],
        4,
      );
      expect(
        repo.progressForPlan(splitId, 'push')!.toJson()['availableWeekIds'],
        ['w1', 'w2'],
      );
      expect(
        repo.progressForPlan(splitId, 'pull')!.toJson()['availableWeekIds'],
        ['w1'],
      );
      final before = HiveService.readTrainingGraph(ownerId: null).toJson();
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(HiveService.readTrainingGraph(ownerId: null).toJson(), before);
    },
  );

  Future<TrainingBlock> setupBlock({int count = 4}) async {
    final block = await repo.createBlock(
      splitId: splitId,
      name: 'Build',
      weekCount: count,
    );
    await TrainingBlockMigration().normalize(ownerId: null);
    return block;
  }

  WorkoutProgress progress(String plan) => repo.progressForPlan(splitId, plan)!;
  Future<void> logWeek(
    String plan,
    String id, {
    WorkoutProgressionService? service,
  }) async {
    final p = progress(plan);
    final week = HiveService.getTrainingWeekById(p.activeWeekId)!;
    await HiveService.putSessionRaw(
      WorkoutSession(
        id: id,
        planId: plan,
        planName: plan,
        splitId: splitId,
        trainingWeekId: week.id,
        weekNumber: week.number,
        date: now,
        isCompleted: false,
        startedAt: now.subtract(const Duration(minutes: 5)),
        durationSeconds: 300,
        exercises: [],
      ),
    );
    await (service ?? WorkoutProgressionService(ownerId: () => null)).complete(
      id,
    );
  }

  test(
    'completing Push allocates and reveals only Push next week; Pull reuses it',
    () async {
      final block = await setupBlock();
      final pullBefore = progress('pull').toJson();
      await logWeek('push', 'push-1');
      final weeks = repo.weeksForBlock(splitId, block.id);
      expect(weeks.map((w) => w.number), [1, 2]);
      expect(progress('push').activeWeekId, weeks.last.id);
      expect(progress('push').toJson()['availableWeekIds'], [
        weeks.first.id,
        weeks.last.id,
      ]);
      expect(progress('pull').toJson(), pullBefore);
      await logWeek('pull', 'pull-1');
      expect(repo.weeksForBlock(splitId, block.id), hasLength(2));
      expect(progress('pull').activeWeekId, weeks.last.id);
    },
  );

  test(
    'four weeks advance without choices and stop at the intended limit',
    () async {
      final block = await setupBlock();
      for (var n = 1; n <= 4; n++) {
        expect(
          HiveService.getTrainingWeekById(
            progress('push').activeWeekId,
          )!.number,
          n,
        );
        await logWeek('push', 'push-$n');
        expect(
          progress('push').state,
          n == 4
              ? WorkoutProgressState.awaitingBoundary
              : WorkoutProgressState.ready,
        );
        expect(
          repo.weeksForBlock(splitId, block.id),
          hasLength(n == 4 ? 4 : n + 1),
        );
      }
      final pullBefore = progress('pull').toJson();
      final fifth = await WorkoutProgressionService(
        ownerId: () => null,
      ).extendBoundary(
        planId: 'push',
        expectedRevision: progress('push').revision,
      );
      expect(fifth.number, 5);
      expect(HiveService.getTrainingBlockById(block.id)!.plannedWeekCount, 5);
      expect(progress('push').activeWeekId, fifth.id);
      expect(progress('pull').toJson(), pullBefore);
    },
  );

  test(
    'progress write failure replays one lazy successor and its availability',
    () async {
      final block = await setupBlock();
      final failing = WorkoutProgressionService(
        ownerId: () => null,
        writeProgress: (_) async => throw StateError('disk'),
      );
      await logWeek('push', 'push-1', service: failing);
      expect(HiveService.getSessionById('push-1')!.isCompleted, isTrue);
      expect(repo.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
        2,
      ]);
      await TrainingBlockMigration().normalize(ownerId: null);
      final weeks = repo.weeksForBlock(splitId, block.id);
      expect(progress('push').activeWeekId, weeks.last.id);
      expect(progress('push').availableWeekIds, [
        weeks.first.id,
        weeks.last.id,
      ]);
      await WorkoutProgressionService(ownerId: () => null).complete('push-1');
      expect(repo.weeksForBlock(splitId, block.id), hasLength(2));
      expect(progress('pull').activeWeekId, weeks.first.id);
    },
  );

  test(
    'a new workout can start at intended Week 3 without revealing it for others',
    () async {
      final block = await setupBlock();
      final pushBefore = progress('push').toJson();
      final third = lazyTrainingWeekId(splitId, block.id, 3);
      await HiveService.createPlan(
        WorkoutPlan(id: 'legs', name: 'Legs', splitId: splitId, exercises: []),
        startingWeekId: third,
      );
      expect(repo.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
        3,
      ]);
      expect(progress('legs').activeWeekId, third);
      expect(progress('legs').availableWeekIds, [third]);
      expect(progress('push').toJson(), pushBefore);
      expect(HiveService.getAllSessionsRaw(), isEmpty);
      await TrainingBlockMigration().normalize(ownerId: null);
      await Hive.box<WorkoutProgress>(HiveService.workoutProgressBox).close();
      await Hive.openBox<WorkoutProgress>(HiveService.workoutProgressBox);
      expect(progress('legs').activeWeekId, third);
      expect(progress('legs').availableWeekIds, [third]);
      final provider = TrainingBlockProvider(
        splitIdProvider: () => splitId,
        ownerId: () => null,
      );
      addTearDown(provider.dispose);
      expect(
        provider.weeksByBlockForPlan('legs')[block.id]!.map((w) => w.number),
        [3],
      );
      expect(
        provider.weeksByBlockForPlan('push')[block.id]!.map((w) => w.number),
        [1],
      );
      await logWeek('legs', 'legs-3');
      provider.reload();
      expect(
        provider.weeksByBlockForPlan('legs')[block.id]!.map((w) => w.number),
        [3, 4],
      );
      expect(
        HiveService.getTrainingWeekById(progress('legs').activeWeekId)!.number,
        4,
      );
      await logWeek('push', 'push-1');
      expect(
        HiveService.getTrainingWeekById(progress('push').activeWeekId)!.number,
        2,
      );
    },
  );

  test(
    'a new workout starts with only its chosen week in a later block',
    () async {
      final first = await setupBlock();
      final later = await repo.createBlock(
        splitId: splitId,
        name: 'Strength',
        weekCount: 4,
      );
      final third = lazyTrainingWeekId(splitId, later.id, 3);
      await HiveService.createPlan(
        WorkoutPlan(id: 'legs', name: 'Legs', splitId: splitId, exercises: []),
        startingWeekId: third,
      );
      expect(progress('legs').activeWeekId, third);
      expect(progress('legs').availableWeekIds, [third]);
      final provider = TrainingBlockProvider(
        splitIdProvider: () => splitId,
        ownerId: () => null,
      );
      addTearDown(provider.dispose);
      expect(
        provider.weeksByBlockForPlan('legs')[later.id]!.map((w) => w.number),
        [3],
      );
      // Unvisited blocks retain an entry point for explicit browsing.
      expect(
        provider.weeksByBlockForPlan('legs')[first.id]!.map((w) => w.number),
        [1],
      );
      expect(
        progress('push').activeWeekId,
        repo.weeksForBlock(splitId, first.id).first.id,
      );
    },
  );

  test(
    'backup and graph cloning preserve duration and independent available weeks',
    () async {
      final block = await setupBlock();
      await logWeek('push', 'push-1');
      final graph = HiveService.readTrainingGraph(ownerId: null);
      final exported = BackupService.exportData(
        splits: graph.splits,
        activeSplitId: splitId,
        plans: graph.plans,
        sessions: graph.sessions,
        blocks: graph.blocks,
        weeks: graph.weeks,
        progress: graph.progress,
        settings: {},
      );
      final imported = BackupService.importData(
        exported.jsonString,
        userId: null,
      );
      expect(imported.success, isTrue, reason: imported.errorMessage);
      expect(imported.version, 5);
      expect(imported.graph!.blocks.single.plannedWeekCount, 4);
      final copied = imported.graph!;
      final push = copied.progress.singleWhere(
        (p) =>
            copied.plans.singleWhere((plan) => plan.id == p.planId).name ==
            'push',
      );
      final pull = copied.progress.singleWhere(
        (p) =>
            copied.plans.singleWhere((plan) => plan.id == p.planId).name ==
            'pull',
      );
      expect(push.availableWeekIds, hasLength(2));
      expect(pull.availableWeekIds, hasLength(1));
      expect(push.activeWeekId, isNot(pull.activeWeekId));
      expect(
        push.availableWeekIds!.every(
          (id) => copied.weeks.any((w) => w.id == id),
        ),
        isTrue,
      );
      final provider = TrainingBlockProvider(
        splitIdProvider: () => splitId,
        ownerId: () => null,
      );
      expect(
        provider.weeksByBlockForPlan('push')[block.id]!.map((w) => w.number),
        [1, 2],
      );
      expect(
        provider.weeksByBlockForPlan('pull')[block.id]!.map((w) => w.number),
        [1],
      );
      provider.dispose();
    },
  );

  test(
    'failed completion leaves its allocated successor hidden and the source unfinished',
    () async {
      final block = await setupBlock();
      final before = progress('push').toJson();
      final failing = WorkoutProgressionService(
        ownerId: () => null,
        writeSession: (_) async => throw StateError('disk'),
      );
      await expectLater(
        logWeek('push', 'push-1', service: failing),
        throwsStateError,
      );
      expect(HiveService.getSessionById('push-1')!.isCompleted, isFalse);
      expect(progress('push').toJson(), before);
      final provider = TrainingBlockProvider(
        splitIdProvider: () => splitId,
        ownerId: () => null,
      );
      expect(
        provider.weeksByBlockForPlan('push')[block.id]!.map((w) => w.number),
        [1],
      );
      expect(
        provider.weeksByBlockForPlan('pull')[block.id]!.map((w) => w.number),
        [1],
      );
      await WorkoutProgressionService(ownerId: () => null).complete('push-1');
      provider.reload();
      expect(
        provider.weeksByBlockForPlan('push')[block.id]!.map((w) => w.number),
        [1, 2],
      );
      expect(repo.weeksForBlock(splitId, block.id), hasLength(2));
      provider.dispose();
    },
  );

  test(
    'new block Week 1 copies prior Week 1, then Week 2 copies the new completed values',
    () async {
      await setupBlock(count: 1);
      final plan = HiveService.getPlanById('push')!.copyWith(
        exercises: [
          ExerciseTemplate(
            name: 'Bench',
            sets: 1,
            setTargets: [SetTemplate(weight: 30, reps: 5)],
          ),
        ],
      );
      await HiveService.putPlanRaw(plan);
      final oldFirst =
          HiveService.getTrainingWeekById(progress('push').activeWeekId)!;
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'old-first',
          planId: 'push',
          planName: 'push',
          splitId: splitId,
          trainingWeekId: oldFirst.id,
          date: now,
          isCompleted: false,
          startedAt: now,
          durationSeconds: 60,
          exercises: [
            Exercise(
              name: 'Bench',
              sets: [gym.Set(weight: 40, reps: 6, rpe: 7)],
            ),
          ],
        ),
      );
      final service = WorkoutProgressionService(ownerId: () => null);
      await service.complete('old-first');
      final pullBefore = progress('pull').toJson();
      final block = await service.createBoundary(
        planId: 'push',
        expectedRevision: progress('push').revision,
        name: 'Next',
        weekCount: 4,
      );
      expect(block.plannedWeekCount, 4);
      expect(repo.weeksForBlock(splitId, block.id).map((w) => w.number), [1]);
      expect(progress('pull').toJson(), pullBefore);
      final provider = TrainingBlockProvider(
        splitIdProvider: () => splitId,
        ownerId: () => null,
      );
      final first =
          HiveService.getTrainingWeekById(progress('push').activeWeekId)!;
      final preview = WorkoutSessionInitializer.initialize(
        plan: plan,
        week: first,
        previousSession: provider.source('push', first.id),
      );
      expect(preview.exercises.single.sets.single.weight, 40);
      final draft = preview.copyWith(
        startedAt: now,
        durationSeconds: 60,
        exercises: [
          Exercise(
            name: 'Bench',
            sets: [
              gym.Set(weight: 55, reps: 9, rpe: 8),
              gym.Set(weight: 50, reps: 7, rpe: 9),
            ],
          ),
        ],
      );
      await HiveService.putSessionRaw(draft);
      await service.complete(draft.id!);
      provider.reload();
      final second =
          HiveService.getTrainingWeekById(progress('push').activeWeekId)!;
      final next = WorkoutSessionInitializer.initialize(
        plan: plan,
        week: second,
        previousSession: provider.source('push', second.id),
      );
      expect(second.number, 2);
      expect(next.exercises.single.sets.map((s) => (s.weight, s.reps, s.rpe)), [
        (55.0, 9, 8),
        (50.0, 7, 9),
      ]);
      expect(next.isCompleted, isFalse);
      expect(next.hasStarted, isFalse);
      expect(next.completionTransition, isNull);
      provider.dispose();
    },
  );

  test('explicit availability must include the workout active week', () async {
    await setupBlock();
    final graph = HiveService.readTrainingGraph(ownerId: null);
    expect(
      () =>
          graph
              .copyWith(
                progress: [
                  for (final p in graph.progress)
                    p.planId == 'push' ? p.copyWith(availableWeekIds: []) : p,
                ],
              )
              .validate(),
      throwsFormatException,
    );
  });

  test(
    'v5 backup cannot silently omit intended duration or availability',
    () async {
      await setupBlock();
      final graph = HiveService.readTrainingGraph(ownerId: null);
      final exported = BackupService.exportData(
        splits: graph.splits,
        activeSplitId: splitId,
        plans: graph.plans,
        sessions: graph.sessions,
        blocks: graph.blocks,
        weeks: graph.weeks,
        progress: graph.progress,
        settings: {},
      );
      for (final (table, field) in [
        ('trainingBlocks', 'plannedWeekCount'),
        ('workoutProgress', 'availableWeekIds'),
      ]) {
        final data = jsonDecode(exported.jsonString) as Map<String, dynamic>;
        ((data[table] as List).first as Map).remove(field);
        expect(
          BackupService.importData(jsonEncode(data), userId: null).success,
          isFalse,
        );
      }
    },
  );
  test(
    'extending a boundary reuses a retained next-number slot beyond the limit',
    () async {
      final block = await setupBlock(count: 1);
      await HiveService.putTrainingWeekRaw(
        TrainingWeek(
          id: 'retained-week',
          splitId: splitId,
          blockId: block.id,
          number: 2,
          createdAt: now,
        ),
      );
      await logWeek('push', 'push-1');
      expect(progress('push').state, WorkoutProgressState.awaitingBoundary);
      final next = await WorkoutProgressionService(
        ownerId: () => null,
      ).extendBoundary(
        planId: 'push',
        expectedRevision: progress('push').revision,
      );
      expect(next.id, 'retained-week');
      expect(repo.weeksForBlock(splitId, block.id), hasLength(2));
      expect(HiveService.getTrainingBlockById(block.id)!.plannedWeekCount, 2);
      HiveService.readTrainingGraph(ownerId: null).validate();
    },
  );
  test(
    'restoring an earlier backup leaves future lazy weeks allocatable',
    () async {
      final block = await setupBlock(count: 1);
      final snapshot = HiveService.readTrainingGraph(ownerId: null);
      final removed = await repo.appendWeek(splitId, block.id);
      await TrainingBlockRestore().replace(graph: snapshot);
      final plan = HiveService.getAllPlansRaw().singleWhere(
        (p) => p.name == 'push' && p.deletedAt == null,
      );
      final p = HiveService.progressForPlan(plan.splitId!, plan.id!)!;
      final week = HiveService.getTrainingWeekById(p.activeWeekId)!;
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'after-restore',
          planId: plan.id,
          planName: plan.name,
          splitId: plan.splitId,
          trainingWeekId: week.id,
          weekNumber: week.number,
          date: now,
          isCompleted: false,
          startedAt: now,
          durationSeconds: 60,
          exercises: [],
        ),
      );
      final service = WorkoutProgressionService(ownerId: () => null);
      await service.complete('after-restore');
      final current = HiveService.progressForPlan(plan.splitId!, plan.id!)!;
      final next = await service.extendBoundary(
        planId: plan.id!,
        expectedRevision: current.revision,
      );
      expect(next.number, 2);
      expect(next.id, isNot(removed.id));
      expect(HiveService.getTrainingWeekById(removed.id)!.deletedAt, isNotNull);
      HiveService.readTrainingGraph(ownerId: null).validate();
    },
  );
}
