import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/adopt_local_data.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';

import 'support/hive_test_harness.dart';

const splitId = '05120ff6-66b5-48cd-9808-141bcb949f24';
const planId = '00000000-0000-4000-8000-000000000001';
final stamp = DateTime.utc(2025, 1, 1);

class InterruptedMigration extends TrainingBlockMigration {
  final String stopAfter;
  InterruptedMigration(this.stopAfter);

  @override
  Future<void> checkpoint(
    String owner,
    Map<String, dynamic> journal,
    String phase,
  ) async {
    await super.checkpoint(owner, journal, phase);
    if (phase == stopAfter) throw const FileSystemException('Interrupted');
  }
}

void main() {
  final storage = HiveTestHarness();
  final repository = TrainingBlockRepository();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    await HiveService.putSplitRaw(
      Split(id: splitId, name: 'A', createdAt: stamp),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(id: planId, name: 'Push', exercises: [], splitId: splitId),
    );
  });
  tearDown(storage.close);

  Future<void> session(
    String id,
    int week, {
    bool completed = true,
    bool running = false,
    String? plan = planId,
    String name = 'Push',
    bool deleted = false,
  }) => HiveService.putSessionRaw(
    WorkoutSession(
      id: id,
      date: stamp.add(Duration(days: week)),
      planName: name,
      planId: plan,
      splitId: splitId,
      weekNumber: week,
      isCompleted: completed,
      updatedAt: stamp,
      dirty: false,
      deletedAt: deleted ? stamp : null,
      startedAt: running ? stamp : null,
      timerStartedAt: running ? stamp : null,
      durationSeconds: 72,
      exercises: [
        Exercise(
          name: 'Squat',
          sets: [Set(reps: 8, weight: 80, rpe: 7, note: 'Keep me')],
        ),
      ],
    ),
  );

  test('frozen URL UUID vectors canonicalize UUID case', () {
    expect(
      legacyTrainingBlockId(splitId.toUpperCase()),
      '9dcb7f75-fb0d-5c2b-8cec-c66b46a9386d',
    );
    expect(
      legacyTrainingWeekId(splitId, 3),
      '39e7f177-288f-5c49-bdcc-e0ccf45671de',
    );
    expect(
      workoutProgressId(splitId, planId),
      'fe40b608-43e5-566a-ba8f-1a71159cd1a7',
    );
    expect(
      initialProgressRevision(splitId, planId),
      'f4b5039f-16e7-5024-b662-bf6b0b6f4b01',
    );
  });

  test(
    'sparse union includes tombstones and preserves complete exercise/timer payload',
    () async {
      await session('one', 1);
      await session('three', 3, running: true, completed: false);
      await session('twelve', 12, deleted: true, plan: null, name: 'Removed');
      final before = {
        for (final s in HiveService.getAllSessionsRaw())
          s.id: jsonEncode(s.toJson()),
      };
      await TrainingBlockMigration().normalize(ownerId: null);
      final block = repository.blocksForSplit(splitId).single;
      expect(repository.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
        3,
        12,
      ]);
      for (final s in HiveService.getAllSessionsRaw()) {
        final old = jsonDecode(before[s.id]!) as Map<String, dynamic>;
        final current = s.toJson()..remove('trainingWeekId');
        old.remove('trainingWeekId');
        expect(jsonEncode(current), jsonEncode(old));
        expect(s.updatedAt, stamp);
        expect(s.dirty, isFalse);
      }
      expect(
        repository.progressForPlan(splitId, planId)!.activeWeekId,
        legacyTrainingWeekId(splitId, 3),
      );
      final snapshot = jsonEncode(
        repository.progressForPlan(splitId, planId)!.toJson(),
      );
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(
        jsonEncode(repository.progressForPlan(splitId, planId)!.toJson()),
        snapshot,
      );
      expect(repository.blocksForSplit(splitId), hasLength(1));
      await session('late', 22);
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(repository.weeksForBlock(splitId, block.id).last.number, 22);
      expect(
        jsonEncode(repository.progressForPlan(splitId, planId)!.toJson()),
        snapshot,
      );
    },
  );

  test(
    'migration bootstrap metadata is distinguishable from a structural edit',
    () async {
      await HiveService.putSplitRaw(
        HiveService.getSplitById(
          splitId,
        )!.copyWith(updatedAt: DateTime.utc(2030)),
      );
      await HiveService.putPlanRaw(
        HiveService.getPlanById(
          planId,
        )!.copyWith(updatedAt: DateTime.utc(2030)),
      );
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(repository.blocksForSplit(splitId).single.updatedAt, isNull);
      expect(HiveService.getAllTrainingWeeksRaw().single.updatedAt, isNull);
      expect(repository.progressForPlan(splitId, planId)!.updatedAt, isNull);
    },
  );

  test('empty split starts at Week 1 without fake history', () async {
    await TrainingBlockMigration().normalize(ownerId: null);
    final b = repository.blocksForSplit(splitId).single;
    expect(repository.weeksForBlock(splitId, b.id).single.number, 1);
    expect(HiveService.getAllSessionsRaw(), isEmpty);
  });

  test(
    'unambiguous missing plan resolves; ambiguous and dangling IDs stay historical',
    () async {
      await session('resolved', 1, plan: null);
      await session('dangling', 3, plan: 'gone');
      await HiveService.putPlanRaw(
        WorkoutPlan(id: 'p2', name: 'Pull', exercises: [], splitId: splitId),
      );
      await HiveService.putPlanRaw(
        WorkoutPlan(id: 'p3', name: 'Pull', exercises: [], splitId: splitId),
      );
      await session('ambiguous', 12, plan: null, name: 'Pull');
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(HiveService.getSessionById('resolved')!.planId, planId);
      expect(HiveService.getSessionById('dangling')!.planId, 'gone');
      expect(HiveService.getSessionById('ambiguous')!.planId, isNull);
    },
  );

  test(
    'running draft outranks later draft; without drafts completion uses next supplied week',
    () async {
      await session('running', 1, completed: false, running: true);
      await session('future', 12, completed: false);
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(
        repository.progressForPlan(splitId, planId)!.activeWeekId,
        legacyTrainingWeekId(splitId, 1),
      );
      expect(HiveService.getSessionById('future'), isNotNull);
    },
  );

  test(
    'highest completed final week awaits boundary, deleted logs do not advance',
    () async {
      await session('done', 3);
      await session('deleted', 12, deleted: true);
      await TrainingBlockMigration().normalize(ownerId: null);
      final p = repository.progressForPlan(splitId, planId)!;
      expect(p.activeWeekId, legacyTrainingWeekId(splitId, 12));
      expect(p.state, WorkoutProgressState.ready);
    },
  );

  test(
    'invalid weeks are recoverable; foreign cache is never migrated',
    () async {
      await session('bad', 0);
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: null),
        throwsA(isA<TrainingPreparationException>()),
      );
      expect(repository.blocksForSplit(splitId), isEmpty);
      await HiveService.putSplitRaw(
        Split(id: 'foreign', name: 'B', userId: 'B', createdAt: stamp),
      );
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: 'B'),
        throwsA(isA<TrainingPreparationException>()),
      );
      expect(repository.blocksForSplit('foreign'), isEmpty);
    },
  );

  test(
    'offline preparation assigns missing splits before training migration',
    () async {
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'unscoped',
          date: stamp,
          planName: 'Removed',
          exercises: [],
          weekNumber: 3,
        ),
      );
      await AdoptLocalData.prepareOffline();
      final saved = HiveService.getSessionById('unscoped')!;
      expect(saved.splitId, isNotNull);
      expect(saved.trainingWeekId, legacyTrainingWeekId(saved.splitId!, 3));
    },
  );

  test(
    'supplied conflicting week links fail before structure is mutated',
    () async {
      await session('linked', 1);
      final linked = HiveService.getSessionById(
        'linked',
      )!.copyWith(trainingWeekId: 'missing');
      await HiveService.putSessionRaw(linked);
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: null),
        throwsA(isA<TrainingPreparationException>()),
      );
      expect(repository.blocksForSplit(splitId), isEmpty);
      expect(HiveService.getSessionById('linked')!.trainingWeekId, 'missing');
    },
  );

  test(
    'late legacy labels reserve original numbers and rebase random additions with saved values',
    () async {
      await session('one', 1);
      await TrainingBlockMigration().normalize(ownerId: null);
      final block = repository.blocksForSplit(splitId).single;
      final randomWeek = await TrainingBlockRepository(
        ownerId: () => null,
      ).appendWeek(splitId, block.id);
      final randomSession = WorkoutSession(
        id: 'random',
        date: stamp,
        planName: 'Push',
        exercises: [
          Exercise(name: 'Squat', sets: [Set(reps: 9, weight: 100)]),
        ],
        planId: planId,
        splitId: splitId,
        trainingWeekId: randomWeek.id,
        weekNumber: 2,
      );
      await HiveService.putSessionRaw(randomSession);
      await session('late', 2);
      await TrainingBlockMigration().normalize(ownerId: null);
      final saved = HiveService.getSessionById('random')!;
      expect(saved.trainingWeekId, randomWeek.id);
      expect(saved.weekNumber, 3);
      expect(saved.exercises.single.sets.single.weight, 100);
      expect(
        HiveService.getSessionById('late')!.trainingWeekId,
        legacyTrainingWeekId(splitId, 2),
      );
      expect(repository.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
        2,
        3,
      ]);
    },
  );

  test(
    'latest incomplete draft wins deterministically when no timer is running',
    () async {
      await session('older', 1, completed: false);
      await session('newer', 12, completed: false);
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(
        repository.progressForPlan(splitId, planId)!.activeWeekId,
        legacyTrainingWeekId(splitId, 12),
      );
    },
  );

  test('completed last supplied week keeps a pending boundary', () async {
    await session('done', 3);
    await TrainingBlockMigration().normalize(ownerId: null);
    expect(
      repository.progressForPlan(splitId, planId)!.state,
      WorkoutProgressState.awaitingBoundary,
    );
  });

  test(
    'late normalization replaces a successful safety snapshot before touching new inputs',
    () async {
      await session('one', 1);
      await TrainingBlockMigration().normalize(ownerId: null);
      final path = TrainingBlockMigration().snapshotPath(null);
      await session('late-invalid', 0);
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: null),
        throwsA(isA<TrainingPreparationException>()),
      );
      final snapshot =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      expect(
        (snapshot['sessions'] as List).map((s) => (s as Map)['id']),
        contains('late-invalid'),
      );
    },
  );

  for (final writtenSessions in [-1, 0, 1]) {
    test(
      'pending rebase recovers after week and $writtenSessions session writes',
      () async {
        await TrainingBlockMigration().normalize(ownerId: null);
        final block = repository.blocksForSplit(splitId).single;
        final week = await TrainingBlockRepository(
          ownerId: () => null,
        ).appendWeek(splitId, block.id);
        for (final id in ['first', 'second']) {
          await HiveService.putSessionRaw(
            WorkoutSession(
              id: id,
              date: stamp,
              planName: 'Push',
              planId: planId,
              splitId: splitId,
              trainingWeekId: week.id,
              weekNumber: 2,
              durationSeconds: 72,
              exercises: [
                Exercise(name: 'Squat', sets: [Set(reps: 8, weight: 80)]),
              ],
            ),
          );
        }
        final target = week.copyWith(number: 3, dirty: true);
        final operations = Hive.box<dynamic>(HiveService.trainingOperationsBox);
        await operations.put('weekRebase', {
          'ownerId': null,
          'previousNumber': 2,
          'week': target.toJson(),
          'dirty': true,
        });
        await operations.flush();
        if (writtenSessions >= 0) await HiveService.putTrainingWeekRaw(target);
        if (writtenSessions == 1) {
          await HiveService.putSessionRaw(
            HiveService.getSessionById('first')!.copyWith(weekNumber: 3),
          );
        }
        await TrainingBlockMigration().normalize(ownerId: null);
        for (final id in ['first', 'second']) {
          final saved = HiveService.getSessionById(id)!;
          expect(saved.trainingWeekId, week.id);
          expect(saved.weekNumber, 3);
          expect(saved.durationSeconds, 72);
          expect(saved.exercises.single.sets.single.weight, 80);
        }
        expect(operations.get('weekRebase'), isNull);
        await TrainingBlockMigration().normalize(ownerId: null);
        expect(repository.weeksForBlock(splitId, block.id).last.id, week.id);
      },
    );
  }

  for (final phase in [
    'snapshot',
    'parents',
    'links',
    'progress',
    'verification',
    'complete',
  ]) {
    test(
      'restart after $phase rolls forward once, retaining original snapshot',
      () async {
        await session('draft', 3, completed: false, running: true);
        await expectLater(
          InterruptedMigration(phase).normalize(ownerId: null),
          throwsA(isA<TrainingPreparationException>()),
        );
        final path = TrainingBlockMigration().snapshotPath(null);
        final bytes = await File(path).readAsBytes();
        await TrainingBlockMigration().normalize(ownerId: null);
        expect(await File(path).readAsBytes(), bytes);
        expect(repository.blocksForSplit(splitId), hasLength(1));
        expect(
          repository.progressForPlan(splitId, planId)!.activeWeekId,
          legacyTrainingWeekId(splitId, 3),
        );
        expect(HiveService.getSessionById('draft')!.isTimerRunning, isTrue);
      },
    );
  }
}
