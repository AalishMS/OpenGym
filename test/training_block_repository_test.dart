import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/completion_transition.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/services/training_block_lifecycle.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:hive/hive.dart';

import 'support/hive_test_harness.dart';

void main() {
  final storage = HiveTestHarness();
  final now = DateTime.utc(2026, 10, 28);
  const splitId = '05120ff6-66b5-48cd-9808-141bcb949f24';
  late TrainingBlockRepository repository;

  setUp(() async {
    await storage.open(includeSplits: true);
    await HiveService.putSplitRaw(
      Split(id: splitId, name: 'A', createdAt: now),
    );
    repository = TrainingBlockRepository(ownerId: () => null);
  });
  tearDown(storage.close);

  test(
    'intended duration persists while weeks allocate lazily; adapters round trip',
    () async {
      final block = await repository.createBlock(
        splitId: splitId,
        name: ' Build ',
        weekCount: 3,
      );
      expect(block.name, 'Build');
      expect(repository.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
      ]);
      expect(block.plannedWeekCount, 3);
      expect(HiveService.getAllSessionsRaw(), isEmpty);
      await Hive.box<TrainingBlock>(HiveService.trainingBlocksBox).close();
      await Hive.openBox<TrainingBlock>(HiveService.trainingBlocksBox);
      expect(
        repository.blocksForSplit(splitId).single.toJson(),
        block.toJson(),
      );
      expect(TrainingBlock.fromJson(block.toJson()).toJson(), block.toJson());
      final week = repository.weeksForBlock(splitId, block.id).first;
      expect(TrainingWeek.fromJson(week.toJson()).toJson(), week.toJson());
      expect((await repository.appendWeek(splitId, block.id)).number, 2);
    },
  );

  test(
    'mutations reject invalid owner, split, names, counts and reorder sets',
    () async {
      for (final name in ['', ' ' * 3, 'a' * 41]) {
        await expectLater(
          repository.createBlock(splitId: splitId, name: name, weekCount: 1),
          throwsArgumentError,
        );
      }
      for (final count in [0, 53]) {
        await expectLater(
          repository.createBlock(splitId: splitId, name: 'A', weekCount: count),
          throwsArgumentError,
        );
      }
      await expectLater(
        repository.createBlock(splitId: 'missing', name: 'A', weekCount: 1),
        throwsStateError,
      );
      await HiveService.putSplitRaw(
        Split(id: 'foreign', name: 'Foreign', createdAt: now, userId: 'other'),
      );
      await expectLater(
        repository.createBlock(splitId: 'foreign', name: 'A', weekCount: 1),
        throwsStateError,
      );
      final a = await repository.createBlock(
        splitId: splitId,
        name: 'A',
        weekCount: 1,
      );
      final b = await repository.createBlock(
        splitId: splitId,
        name: 'B',
        weekCount: 1,
      );
      await expectLater(repository.appendWeek('other', a.id), throwsStateError);
      await expectLater(
        repository.reorderBlocks(splitId, [a.id, a.id]),
        throwsArgumentError,
      );
      await repository.reorderBlocks(splitId, [b.id, a.id]);
      expect(repository.blocksForSplit(splitId).map((b) => b.id), [b.id, a.id]);
      await repository.renameBlock(splitId, a.id, ' Renamed ');
      expect(repository.blocksForSplit(splitId).last.name, 'Renamed');
    },
  );

  test(
    'interrupted creation retries the fixed IDs without a second block',
    () async {
      final b = TrainingBlock(
        id: 'fixed-block',
        splitId: splitId,
        name: 'Build',
        position: 0,
        createdAt: now,
        dirty: true,
      );
      final w = TrainingWeek(
        id: 'fixed-week',
        splitId: splitId,
        blockId: b.id,
        number: 1,
        createdAt: now,
        dirty: true,
      );
      await Hive.box<dynamic>(HiveService.trainingOperationsBox).put('create', {
        'ownerId': null,
        'block': b.toJson(),
        'weeks': [w.toJson()],
      });
      final result = await repository.createBlock(
        splitId: splitId,
        name: 'Build',
        weekCount: 1,
      );
      expect(result.id, b.id);
      expect(repository.blocksForSplit(splitId), hasLength(1));
      expect(repository.weeksForBlock(splitId, b.id).single.id, w.id);
    },
  );

  test(
    'completion evidence survives Hive and clears without clearing other fields',
    () async {
      final evidence = CompletionTransition(
        expectedRevision: 'old',
        sourceWeekId: 'w',
        nextWeekId: null,
        resultRevision: 's',
        committedAt: now,
      );
      final session = WorkoutSession(
        id: 's',
        date: now,
        planName: 'Push',
        exercises: [],
        splitId: splitId,
        trainingWeekId: 'w',
        completionTransition: evidence.toJson(),
        deletedAt: now,
        userId: 'owner',
      );
      await HiveService.putSessionRaw(session);
      await Hive.box<WorkoutSession>(HiveService.sessionsBox).close();
      await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
      final saved = HiveService.getSessionById('s')!;
      expect(saved.completionTransition, evidence.toJson());
      expect(
        saved.copyWith(completionTransition: null).completionTransition,
        isNull,
      );
      expect(saved.copyWith().completionTransition, evidence.toJson());
      expect(saved.copyWith(deletedAt: null, userId: null).deletedAt, isNull);
      expect(saved.copyWith(deletedAt: null, userId: null).userId, isNull);
      expect(
        () => WorkoutSession.fromJson({
          ...saved.toJson(),
          'completionTransition': {'sourceWeekId': 'w'},
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'slot queries retain multiple session IDs and nullable fields clear explicitly',
    () async {
      final b = await repository.createBlock(
        splitId: splitId,
        name: 'A',
        weekCount: 1,
      );
      final w = repository.weeksForBlock(splitId, b.id).single;
      for (final id in ['one', 'two']) {
        await HiveService.putSessionRaw(
          WorkoutSession(
            id: id,
            date: now,
            planName: 'Push',
            planId: 'p',
            splitId: splitId,
            trainingWeekId: w.id,
            exercises: [],
          ),
        );
      }
      expect(
        repository
            .sessionsForPlanWeek(splitId, 'p', w.id)
            .map((s) => s.id)
            .toSet(),
        {'one', 'two'},
      );
      final s = HiveService.getSessionById('one')!;
      expect(WorkoutSession.fromJson(s.toJson()).trainingWeekId, w.id);
      expect(s.copyWith().trainingWeekId, w.id);
      expect(s.copyWith(trainingWeekId: null).trainingWeekId, isNull);
      expect(s.copyWith(planId: null).planId, isNull);
      expect(
        () => WorkoutSession.fromJson({
          ...s.toJson(),
          'trainingSchemaVersion': 99,
        }),
        throwsFormatException,
      );
      final progress = WorkoutProgress(
        id: 'progress',
        splitId: splitId,
        planId: 'p',
        activeWeekId: w.id,
        revision: 'r',
        state: WorkoutProgressState.ready,
      );
      expect(
        WorkoutProgress.fromJson(progress.toJson()).toJson(),
        progress.toJson(),
      );
      await HiveService.putWorkoutProgressRaw(progress);
      await Hive.box<WorkoutProgress>(HiveService.workoutProgressBox).close();
      await Hive.openBox<WorkoutProgress>(HiveService.workoutProgressBox);
      expect(repository.progressForPlan(splitId, 'p')!.revision, 'r');
    },
  );

  group('the duration clock', () {
    test(
      'creating a block and appending a week stamp it; renames do not',
      () async {
        final block = await repository.createBlock(
          splitId: splitId,
          name: 'Clocked',
          weekCount: 2,
        );
        final created = HiveService.getTrainingBlockById(block.id)!;
        expect(created.plannedWeekCountUpdatedAt, created.createdAt);
        // The clock survives a trip through the Hive adapter.
        await Hive.box<TrainingBlock>(HiveService.trainingBlocksBox).close();
        await Hive.openBox<TrainingBlock>(HiveService.trainingBlocksBox);
        expect(
          HiveService.getTrainingBlockById(block.id)!.plannedWeekCountUpdatedAt,
          created.createdAt,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repository.renameBlock(splitId, block.id, 'Renamed');
        expect(
          HiveService.getTrainingBlockById(block.id)!.plannedWeekCountUpdatedAt,
          created.createdAt,
        );
        await repository.appendWeek(splitId, block.id);
        await repository.appendWeek(splitId, block.id);
        final extended = HiveService.getTrainingBlockById(block.id)!;
        expect(extended.plannedWeekCount, 3);
        expect(
          extended.plannedWeekCountUpdatedAt!.isAfter(created.createdAt),
          isTrue,
        );
        final stamped = extended.plannedWeekCountUpdatedAt;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repository.reorderBlocks(splitId, [
          for (final b in repository.blocksForSplit(splitId).reversed) b.id,
        ]);
        expect(
          HiveService.getTrainingBlockById(block.id)!.plannedWeekCountUpdatedAt,
          stamped,
        );
      },
    );
  });

  group('deleting a block on local-only data', () {
    late TrainingBlock keep;
    late TrainingBlock target;
    late TrainingWeek targetWeek;

    setUp(() async {
      await HiveService.putPlanRaw(
        WorkoutPlan(id: 'plan', name: 'Push', exercises: [], splitId: splitId),
      );
      keep = await repository.createBlock(
        splitId: splitId,
        name: 'Keep',
        weekCount: 3,
      );
      target = await repository.createBlock(
        splitId: splitId,
        name: 'Target',
        weekCount: 4,
      );
      await repository.appendWeek(splitId, target.id);
      targetWeek = repository.weeksForBlock(splitId, target.id).first;
      // The plan sits in the kept block.
      final week = repository.weeksForBlock(splitId, keep.id).first;
      await HiveService.putWorkoutProgressRaw(
        WorkoutProgress(
          id: workoutProgressId(splitId, 'plan'),
          splitId: splitId,
          planId: 'plan',
          activeWeekId: week.id,
          availableWeekIds: [week.id],
          state: WorkoutProgressState.ready,
          revision: 'rev',
        ),
      );
    });

    String snapshot() => jsonEncode({
      'blocks':
          HiveService.getAllTrainingBlocksRaw().map((b) => b.toJson()).toList(),
      'weeks':
          HiveService.getAllTrainingWeeksRaw().map((w) => w.toJson()).toList(),
      'dirty': [
        ...HiveService.getAllTrainingBlocksRaw().map((b) => b.dirty),
        ...HiveService.getAllTrainingWeeksRaw().map((w) => w.dirty),
      ],
    });

    test(
      'tombstones the block and its weeks and leaves the rest alone',
      () async {
        final others = {
          for (final b in HiveService.getAllTrainingBlocksRaw())
            if (b.id != target.id) b.id: jsonEncode(b.toJson()),
        };
        await repository.deleteBlock(splitId: splitId, blockId: target.id);
        final gone = HiveService.getTrainingBlockById(target.id)!;
        expect(gone.deletedAt, isNotNull);
        expect(gone.dirty, isTrue);
        expect(gone.position, target.position);
        final weeks = HiveService.getAllTrainingWeeksRaw().where(
          (w) => w.blockId == target.id,
        );
        expect(weeks, hasLength(2));
        for (final w in weeks) {
          expect(w.deletedAt, isNotNull);
          expect(w.dirty, isTrue);
        }
        expect(
          repository.blocksForSplit(splitId).map((b) => b.id),
          contains(keep.id),
        );
        expect(
          repository.blocksForSplit(splitId).map((b) => b.id),
          isNot(contains(target.id)),
        );
        expect(repository.weeksForBlock(splitId, target.id), isEmpty);
        for (final entry in others.entries) {
          expect(
            jsonEncode(HiveService.getTrainingBlockById(entry.key)!.toJson()),
            entry.value,
          );
        }
        expect(
          HiveService.readTrainingGraph(ownerId: null).validate,
          returnsNormally,
        );
      },
    );

    test('is refused for the last block', () async {
      await repository.deleteBlock(splitId: splitId, blockId: target.id);
      // The first block created with the split is still live too.
      for (final b in repository.blocksForSplit(splitId).skip(1)) {
        await repository.deleteBlock(splitId: splitId, blockId: b.id);
      }
      final last = repository.blocksForSplit(splitId).single;
      final before = snapshot();
      await expectLater(
        repository.deleteBlock(splitId: splitId, blockId: last.id),
        throwsA(
          isA<TrainingBlockDeletionException>().having(
            (e) => e.reason,
            'reason',
            TrainingBlockDeletionReason.lastBlock,
          ),
        ),
      );
      expect(snapshot(), before);
    });

    for (final completed in [true, false]) {
      test('is refused when a ${completed ? 'completed' : 'draft'} workout '
          'is in it, leaving data untouched', () async {
        await HiveService.putSessionRaw(
          WorkoutSession(
            id: 'log',
            date: now,
            planName: 'Push',
            planId: 'plan',
            splitId: splitId,
            trainingWeekId: targetWeek.id,
            weekNumber: targetWeek.number,
            isCompleted: completed,
            exercises: [],
          ),
        );
        final before = snapshot();
        await expectLater(
          repository.deleteBlock(splitId: splitId, blockId: target.id),
          throwsA(
            isA<TrainingBlockDeletionException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  TrainingBlockDeletionReason.inUse,
                )
                .having(
                  (e) => e.blocker,
                  'blocker',
                  BlockDeletionBlocker.hasWorkouts,
                ),
          ),
        );
        expect(snapshot(), before);
        expect(
          repository.deleteBlocker(splitId, target.id),
          BlockDeletionBlocker.hasWorkouts,
        );
      });
    }

    test('is refused while a plan is positioned in it', () async {
      await HiveService.putWorkoutProgressRaw(
        repository
            .progressForPlan(splitId, 'plan')!
            .copyWith(
              activeWeekId: targetWeek.id,
              availableWeekIds: [targetWeek.id],
            ),
      );
      final before = snapshot();
      await expectLater(
        repository.deleteBlock(splitId: splitId, blockId: target.id),
        throwsA(
          isA<TrainingBlockDeletionException>().having(
            (e) => e.blocker,
            'blocker',
            BlockDeletionBlocker.workoutInBlock,
          ),
        ),
      );
      expect(snapshot(), before);
    });

    test('lists of available weeks do not stop a delete', () async {
      final keepWeek = repository.weeksForBlock(splitId, keep.id).first;
      await HiveService.putWorkoutProgressRaw(
        repository
            .progressForPlan(splitId, 'plan')!
            .copyWith(
              activeWeekId: keepWeek.id,
              availableWeekIds: [targetWeek.id, keepWeek.id],
            ),
      );
      expect(repository.deleteBlocker(splitId, target.id), isNull);
      await repository.deleteBlock(splitId: splitId, blockId: target.id);
      expect(HiveService.getTrainingBlockById(target.id)!.deletedAt, isNotNull);
      expect(
        HiveService.readTrainingGraph(ownerId: null).validate,
        returnsNormally,
      );
    });

    test('is idempotent', () async {
      await repository.deleteBlock(splitId: splitId, blockId: target.id);
      await expectLater(
        repository.deleteBlock(splitId: splitId, blockId: target.id),
        throwsStateError,
      );
    });

    test('drains pending structural intents first', () async {
      final pending = TrainingBlock(
        id: 'pending',
        splitId: splitId,
        name: 'Pending',
        position: 9,
        createdAt: now,
        plannedWeekCount: 2,
      );
      final pendingWeek = TrainingWeek(
        id: 'pending-week',
        splitId: splitId,
        blockId: 'pending',
        number: 1,
        createdAt: now,
      );
      await Hive.box<dynamic>(HiveService.trainingOperationsBox).put('create', {
        'ownerId': null,
        'block': pending.toJson(),
        'weeks': [pendingWeek.toJson()],
      });
      await repository.deleteBlock(splitId: splitId, blockId: target.id);
      expect(HiveService.getTrainingBlockById('pending'), isNotNull);
      expect(
        Hive.box<dynamic>(HiveService.trainingOperationsBox).isEmpty,
        isTrue,
      );
    });
  });
}
