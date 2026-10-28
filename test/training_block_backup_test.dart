import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/completion_transition.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:hive/hive.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/backup_service.dart';
import 'package:gymapp/services/adopt_local_data.dart';
import 'package:gymapp/services/sample_data_seeder.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/hive_test_harness.dart';

const owner = '00000000-0000-4000-8000-000000000011';
const splitId = '00000000-0000-4000-8000-000000000012';
const planId = '00000000-0000-4000-8000-000000000013';
final stamp = DateTime.utc(2026, 1, 1);

class InterruptedRestore extends TrainingBlockRestore {
  final String stopAfter;
  InterruptedRestore(this.stopAfter);
  @override
  Future<void> checkpoint(Map<String, dynamic> journal, String phase) async {
    await super.checkpoint(journal, phase);
    if (phase == stopAfter) throw StateError('Interrupted replacement');
  }
}

void main() {
  final storage = HiveTestHarness();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    await HiveService.putSplitRaw(
      Split(
        id: splitId,
        name: 'A',
        createdAt: stamp,
        userId: owner,
        updatedAt: stamp,
      ),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: planId,
        name: 'Push',
        exercises: [],
        splitId: splitId,
        userId: owner,
        updatedAt: stamp,
      ),
    );
    await TrainingBlockMigration().normalize(ownerId: owner);
  });
  tearDown(storage.close);

  test('new plan starts at a supplied week with no fake session', () async {
    final repo = TrainingBlockRepository(ownerId: () => owner);
    final block = await repo.createBlock(
      splitId: splitId,
      name: 'Next',
      weekCount: 3,
    );
    final week = repo.weeksForBlock(splitId, block.id).last;
    final plan = WorkoutPlan(
      id: 'added',
      name: 'Pull',
      splitId: splitId,
      exercises: [],
    );
    await HiveService.createPlan(plan, startingWeekId: week.id);
    expect(repo.progressForPlan(splitId, 'added')!.activeWeekId, week.id);
    expect(
      repo.progressForPlan(splitId, 'added')!.revision,
      isNot(initialProgressRevision(splitId, 'added')),
    );
    expect(HiveService.getSessions(), isEmpty);
    expect(HiveService.getPlanById('added')!.userId, owner);
  });

  test(
    'sample replacement scopes fresh weeks and logs to the selected split',
    () async {
      final before = HiveService.getAllTrainingWeeksRaw().single.id;
      await HiveService.putSplitRaw(
        Split(id: 'other', name: 'Other', createdAt: stamp, userId: owner),
      );
      await TrainingBlockMigration().normalize(ownerId: owner);
      final other = HiveService.blocksForSplit('other').single.toJson();
      await SampleDataSeeder.seedSampleData(splitId: splitId);
      expect(HiveService.blocksForSplit('other').single.toJson(), other);
      final weeks =
          HiveService.getAllTrainingWeeksRaw()
              .where((w) => w.splitId == splitId && w.deletedAt == null)
              .toList();
      expect(weeks.map((w) => w.number).toSet(), {1, 2, 3, 4, 5});
      expect(weeks.map((w) => w.id), isNot(contains(before)));
      expect(
        HiveService.getSessions().every(
          (s) => weeks.any(
            (w) => w.id == s.trainingWeekId && w.number == s.weekNumber,
          ),
        ),
        isTrue,
      );
      HiveService.readTrainingGraph(ownerId: owner).validate();
    },
  );

  test(
    'failed replacement blocks data exposure until recovery succeeds',
    () async {
      final graph = HiveService.readTrainingGraph(ownerId: owner);
      await expectLater(
        InterruptedRestore('parents').replace(graph: graph),
        throwsStateError,
      );
      expect(TrainingBlockRestore.recoveryFailure.value, isNotNull);
      await TrainingBlockRestore().recover(ownerId: owner);
      expect(TrainingBlockRestore.recoveryFailure.value, isNull);
    },
  );

  test(
    'first adoption finishes unowned pending creation before stamping ownership',
    () async {
      await HiveService.clearAllPlans();
      await HiveService.clearAllSessions();
      await HiveService.clearSplitData();
      await HiveService.clearTrainingData();
      await HiveService.putSplitRaw(
        Split(id: splitId, name: 'Offline', createdAt: stamp),
      );
      final block = TrainingBlock(
        id: 'pending-block',
        splitId: splitId,
        name: 'Recovery',
        position: 0,
        createdAt: stamp,
      );
      final week = TrainingWeek(
        id: 'pending-week',
        splitId: splitId,
        blockId: block.id,
        number: 1,
        createdAt: stamp,
      );
      await Hive.box<dynamic>(HiveService.trainingOperationsBox).put('create', {
        'ownerId': null,
        'block': block.toJson(),
        'weeks': [week.toJson()],
      });
      await AdoptLocalData.prepareLocalForUser('first-adoption');
      expect(
        HiveService.getTrainingBlockById(block.id)!.userId,
        'first-adoption',
      );
      expect(
        HiveService.getTrainingWeekById(week.id)!.userId,
        'first-adoption',
      );
      expect(
        Hive.box<dynamic>(HiveService.trainingOperationsBox).isEmpty,
        isTrue,
      );
    },
  );

  test(
    'handover removes previous pending restore and owner safety copies',
    () async {
      final graph = HiveService.readTrainingGraph(ownerId: owner);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastUserId', owner);
      await expectLater(
        InterruptedRestore('plans').replace(graph: graph),
        throwsStateError,
      );
      final oldPath = TrainingBlockRestore().snapshotPath(owner);
      await AdoptLocalData.prepareLocalForUser('account-b');
      expect(await File(oldPath).exists(), isFalse);
      expect(HiveService.getAllPlansRaw(), isEmpty);
      expect(
        HiveService.getAllTrainingBlocksRaw().every(
          (b) => b.userId == 'account-b',
        ),
        isTrue,
      );
      expect(prefs.getString('training_restore_pending_$owner'), isNull);
    },
  );

  ExportResult backup() => BackupService.exportData(
    sourceAccountId: owner,
    splits: HiveService.getAllSplitsRaw(),
    activeSplitId: splitId,
    plans: HiveService.getAllPlansRaw(),
    sessions: HiveService.getAllSessionsRaw(),
    blocks: HiveService.getAllTrainingBlocksRaw(),
    weeks: HiveService.getAllTrainingWeeksRaw(),
    progress: HiveService.getAllWorkoutProgressRaw(),
    settings: const {'themeMode': 0},
  );
  Future<void> restore(ImportResult result) =>
      HiveService.replaceAllWorkoutData(
        userId: owner,
        splits: result.splits!,
        activeSplitId: result.activeSplitId!,
        plans: result.plans!,
        sessions: result.sessions!,
        blocks: result.blocks!,
        weeks: result.weeks!,
        progress: result.progress!,
        operationId: result.operationId,
        settings: result.settings!,
      );

  test(
    'restoring a deleted graph copies it without reviving tombstone IDs',
    () async {
      final saved = BackupService.importData(
        backup().jsonString,
        userId: owner,
      );
      await HiveService.softDeleteAllWorkoutData();
      await restore(saved);
      final live = HiveService.getPlans().single;
      expect(live.name, 'Push');
      expect(live.id, isNot(planId));
      expect(HiveService.getPlanById(planId)!.deletedAt, isNotNull);
      expect(
        HiveService.getAllWorkoutProgressRaw()
            .where((p) => p.deletedAt == null)
            .single
            .planId,
        live.id,
      );
    },
  );

  test(
    'incomplete v4 progress and duplicate live week numbers are rejected',
    () {
      final exported = backup();
      for (final key in ['workoutProgress', 'trainingWeeks']) {
        final data = jsonDecode(exported.jsonString) as Map<String, dynamic>;
        if (key == 'workoutProgress') {
          data[key] = [];
        } else {
          final week = Map<String, dynamic>.from(
            (data[key] as List).single as Map,
          );
          data[key] = [
            week,
            {...week, 'id': 'duplicate-slot'},
          ];
        }
        expect(
          BackupService.importData(jsonEncode(data), userId: owner).success,
          isFalse,
        );
      }
    },
  );

  test(
    'v4 round trip preserves empty structure, duplicate logs, evidence and boundary state',
    () async {
      final repository = TrainingBlockRepository(ownerId: () => owner);
      await repository.createBlock(
        splitId: splitId,
        name: 'Empty block',
        weekCount: 3,
      );
      final week = HiveService.getAllTrainingWeeksRaw().first;
      for (final id in [
        '00000000-0000-4000-8000-000000000021',
        '00000000-0000-4000-8000-000000000022',
      ]) {
        final transition = CompletionTransition(
          expectedRevision: initialProgressRevision(splitId, planId),
          sourceWeekId: week.id,
          nextWeekId: null,
          resultRevision: id,
          committedAt: stamp,
        );
        await HiveService.putSessionRaw(
          WorkoutSession(
            id: id,
            date: stamp,
            planName: 'Push',
            planId: planId,
            splitId: splitId,
            userId: owner,
            trainingWeekId: week.id,
            weekNumber: week.number,
            completionTransition: transition.toJson(),
            exercises: [],
          ),
        );
      }
      final p = HiveService.getAllWorkoutProgressRaw().single;
      await HiveService.putWorkoutProgressRaw(
        p.copyWith(
          state: WorkoutProgressState.awaitingBoundary,
          revision: '00000000-0000-4000-8000-000000000021',
        ),
      );
      final exported = backup();
      expect((jsonDecode(exported.jsonString) as Map)['version'], 4);
      final result = BackupService.importData(
        exported.jsonString,
        userId: owner,
      );
      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.blocks, hasLength(2));
      expect(result.weeks, hasLength(4));
      expect(result.sessions, hasLength(2));
      expect(
        result.sessions!.first.completionTransition,
        HiveService.getAllSessionsRaw().first.completionTransition,
      );
      expect(
        result.progress!.single.state,
        WorkoutProgressState.awaitingBoundary,
      );
      expect(result.progress!.single.id, p.id);
    },
  );

  test(
    'foreign copies remap every entity and completion revision reference',
    () async {
      final week = HiveService.getAllTrainingWeeksRaw().single;
      const id = '00000000-0000-4000-8000-000000000021';
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: id,
          date: stamp,
          planName: 'Push',
          planId: planId,
          splitId: splitId,
          userId: owner,
          trainingWeekId: week.id,
          weekNumber: week.number,
          completionTransition:
              CompletionTransition(
                expectedRevision: initialProgressRevision(splitId, planId),
                sourceWeekId: week.id,
                nextWeekId: null,
                resultRevision: id,
                committedAt: stamp,
              ).toJson(),
          exercises: [],
        ),
      );
      final p = HiveService.getAllWorkoutProgressRaw().single;
      await HiveService.putWorkoutProgressRaw(p.copyWith(revision: id));
      final result = BackupService.importData(
        backup().jsonString,
        userId: '00000000-0000-4000-8000-000000000099',
      );
      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.splits!.single.id, isNot(splitId));
      expect(result.plans!.single.id, isNot(planId));
      expect(result.sessions!.single.id, isNot(id));
      expect(result.weeks!.single.id, isNot(week.id));
      final log = result.sessions!.single;
      expect(log.trainingWeekId, result.weeks!.single.id);
      expect(log.completionTransition!['resultRevision'], log.id);
      expect(log.completionTransition!['sourceWeekId'], log.trainingWeekId);
      expect(
        log.completionTransition!['expectedRevision'],
        initialProgressRevision(
          result.splits!.single.id,
          result.plans!.single.id!,
        ),
      );
      expect(result.progress!.single.revision, log.id);
    },
  );

  for (final version in [1, 2, 3]) {
    test(
      'v$version uses the same sparse legacy normalizer before replacement',
      () {
        final source = jsonEncode({
          'version': version,
          'settings': {},
          if (version == 3)
            'splits': [HiveService.getSplitById(splitId)!.toJson()],
          if (version == 3) 'activeSplitId': splitId,
          'workoutPlans': [HiveService.getPlanById(planId)!.toJson()],
          'workoutSessions': [
            for (final n in [3, 12])
              WorkoutSession(
                id: 'session-$n',
                date: stamp,
                planName: 'Push',
                planId: planId,
                splitId: splitId,
                weekNumber: n,
                durationSeconds: 72,
                exercises: [],
              ).toJson(),
          ],
        });
        final result = BackupService.importData(source, userId: owner);
        expect(result.success, isTrue, reason: result.errorMessage);
        expect(result.weeks!.map((w) => w.number), [3, 12]);
        expect(
          result.sessions!.every(
            (s) => s.trainingWeekId != null && s.durationSeconds == 72,
          ),
          isTrue,
        );
        expect(
          result.progress!.single.state,
          WorkoutProgressState.awaitingBoundary,
        );
        expect(result.activeSplitId, isNot(splitId));
      },
    );
  }

  test('conflicting supplied references fail before any Hive write', () {
    final source = jsonDecode(backup().jsonString) as Map<String, dynamic>;
    (source['trainingWeeks'] as List).first['splitId'] = 'unknown';
    final result = BackupService.importData(jsonEncode(source), userId: owner);
    expect(result.success, isFalse);
    expect(HiveService.getAllTrainingWeeksRaw().single.splitId, splitId);
  });

  test(
    'same-owner replacement tombstones absent records without changing imported IDs',
    () async {
      final exported = backup();
      final block = await TrainingBlockRepository(
        ownerId: () => owner,
      ).createBlock(splitId: splitId, name: 'Absent', weekCount: 1);
      final result = BackupService.importData(
        exported.jsonString,
        userId: owner,
      );
      await restore(result);
      expect(HiveService.getTrainingBlockById(block.id)!.deletedAt, isNotNull);
      expect(
        HiveService.getAllTrainingWeeksRaw()
            .where((w) => w.blockId == block.id)
            .every((w) => w.deletedAt != null),
        isTrue,
      );
      expect(
        HiveService.blocksForSplit(splitId).single.id,
        result.blocks!.single.id,
      );
    },
  );

  test('plan deletion keeps logs and tombstones only its progress', () async {
    final week = HiveService.getAllTrainingWeeksRaw().single;
    await HiveService.putSessionRaw(
      WorkoutSession(
        id: 'log',
        date: stamp,
        planName: 'Push',
        planId: planId,
        splitId: splitId,
        userId: owner,
        trainingWeekId: week.id,
        weekNumber: week.number,
        exercises: [],
      ),
    );
    await HiveService.softDeletePlan(planId);
    expect(HiveService.getAllWorkoutProgressRaw().single.deletedAt, isNotNull);
    expect(HiveService.getSessionById('log')!.deletedAt, isNull);
    expect(HiveService.getSessionById('log')!.trainingWeekId, week.id);
  });

  test(
    'clear workouts keeps profiles and allocates fresh structure IDs',
    () async {
      final previous = HiveService.getAllTrainingBlocksRaw().single;
      await HiveService.softDeleteAllWorkoutData();
      expect(HiveService.getSplits().single.id, splitId);
      expect(
        HiveService.getTrainingBlockById(previous.id)!.deletedAt,
        isNotNull,
      );
      final fresh = HiveService.blocksForSplit(splitId).single;
      expect(fresh.id, isNot(previous.id));
      expect(HiveService.weeksForBlock(splitId, fresh.id).single.number, 1);
      await TrainingBlockMigration().normalize(ownerId: owner);
      expect(HiveService.blocksForSplit(splitId).single.id, fresh.id);
    },
  );

  for (final phase in [
    'parents',
    'plans',
    'sessions',
    'progress',
    'settings',
  ]) {
    test(
      'replacement recovers after $phase using the validated fixed graph',
      () async {
        final result = BackupService.importData(
          backup().jsonString,
          userId: owner,
        );
        await expectLater(
          InterruptedRestore(phase).replace(
            graph: result.graph!,
            settings: result.settings!,
            operationId: result.operationId,
          ),
          throwsStateError,
        );
        await TrainingBlockRestore().recover(ownerId: owner);
        expect(HiveService.getPlanById(result.plans!.single.id!), isNotNull);
        expect(
          HiveService.getTrainingWeekById(result.weeks!.single.id),
          isNotNull,
        );
        expect(
          HiveService.getAllWorkoutProgressRaw().single.activeWeekId,
          result.weeks!.single.id,
        );
        expect(
          HiveService.getSplitPreference(owner)!.activeSplitId,
          result.activeSplitId,
        );
      },
    );
  }
}
