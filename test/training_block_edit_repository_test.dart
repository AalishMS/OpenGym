import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/workout_progression_service.dart';

import 'support/hive_test_harness.dart';

void main() {
  final storage = HiveTestHarness();
  final now = DateTime.utc(2026, 11, 1, 12);
  const splitId = 'split';
  late TrainingBlockRepository repo;

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
      Split(id: splitId, name: 'Training', userId: 'owner', createdAt: now),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: 'push',
        name: 'Push',
        exercises: [],
        splitId: splitId,
        userId: 'owner',
      ),
    );
    await TrainingBlockMigration().normalize(ownerId: 'owner');
    repo = TrainingBlockRepository(ownerId: () => 'owner');
  });
  tearDown(storage.close);

  Future<TrainingBlock> newBlock({String name = 'Strength', int weeks = 3}) =>
      repo.createBlock(splitId: splitId, name: name, weekCount: weeks);
  TrainingBlock stored(String id) => HiveService.getTrainingBlockById(id)!;

  group('updateBlock', () {
    test('renames only', () async {
      final block = await newBlock();
      final updated = await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: ' Power ',
        weekCount: 3,
      );
      expect(updated.name, 'Power');
      expect(stored(block.id).name, 'Power');
      expect(stored(block.id).plannedWeekCount, 3);
      expect(stored(block.id).dirty, isTrue);
    });

    test('extends only, without allocating week rows', () async {
      final block = await newBlock(weeks: 2);
      final weeksBefore = repo.weeksForBlock(splitId, block.id).length;
      await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Strength',
        weekCount: 6,
      );
      expect(stored(block.id).name, 'Strength');
      expect(stored(block.id).plannedWeekCount, 6);
      expect(repo.weeksForBlock(splitId, block.id), hasLength(weeksBefore));
      expect(weeksBefore, 1);
    });

    test('renames and extends in one write', () async {
      final block = await newBlock(weeks: 2);
      await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Hypertrophy',
        weekCount: 5,
      );
      expect(stored(block.id).name, 'Hypertrophy');
      expect(stored(block.id).plannedWeekCount, 5);
    });

    test('an unchanged block is not written again', () async {
      final block = await newBlock();
      final before = stored(block.id).updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Strength',
        weekCount: 3,
      );
      expect(stored(block.id).updatedAt, before);
    });

    test('shrinking is rejected and leaves the block alone', () async {
      final block = await newBlock(weeks: 4);
      await expectLater(
        repo.updateBlock(
          splitId: splitId,
          blockId: block.id,
          name: 'Smaller',
          weekCount: 3,
        ),
        throwsArgumentError,
      );
      expect(stored(block.id).name, 'Strength');
      expect(stored(block.id).plannedWeekCount, 4);
    });

    test('growing past 52 is rejected', () async {
      final block = await newBlock(weeks: 10);
      await expectLater(
        repo.updateBlock(
          splitId: splitId,
          blockId: block.id,
          name: 'Strength',
          weekCount: 53,
        ),
        throwsArgumentError,
      );
      expect(stored(block.id).plannedWeekCount, 10);
    });

    test('a block already past 52 can be renamed at its length only', () async {
      final block = await newBlock(weeks: 52);
      // Weeks appended as the block is trained can carry it past the cap.
      final long = stored(block.id).copyWith(plannedWeekCount: 60);
      await HiveService.putTrainingBlockRaw(long);
      await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Long',
        weekCount: 60,
      );
      expect(stored(block.id).name, 'Long');
      await expectLater(
        repo.updateBlock(
          splitId: splitId,
          blockId: block.id,
          name: 'Long',
          weekCount: 61,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid names and unknown blocks', () async {
      final block = await newBlock();
      await expectLater(
        repo.updateBlock(
          splitId: splitId,
          blockId: block.id,
          name: '  ',
          weekCount: 3,
        ),
        throwsA(anything),
      );
      await expectLater(
        repo.updateBlock(
          splitId: splitId,
          blockId: 'missing',
          name: 'X',
          weekCount: 3,
        ),
        throwsStateError,
      );
    });
  });

  test(
    'extending a block lets a plan waiting at its boundary continue into the '
    'next week of the same block',
    () async {
      final block = await newBlock(name: 'Strength', weeks: 1);
      final first = repo.weeksForBlock(splitId, block.id).single;
      await HiveService.putWorkoutProgressRaw(
        repo
            .progressForPlan(splitId, 'push')!
            .copyWith(
              activeWeekId: first.id,
              availableWeekIds: [first.id],
              state: WorkoutProgressState.awaitingBoundary,
            ),
      );
      final service = WorkoutProgressionService(
        ownerId: () => 'owner',
        clock: () => now,
      );
      // Waiting at the end of a one-week block.
      expect(
        HiveService.readTrainingGraph(ownerId: 'owner').validate,
        returnsNormally,
      );

      await repo.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Strength',
        weekCount: 3,
      );

      // Stored progress is untouched: the state is a record, not derived from
      // the block length, so no replay or reconcile is needed.
      final waiting = repo.progressForPlan(splitId, 'push')!;
      expect(waiting.state, WorkoutProgressState.awaitingBoundary);
      await service.replay();
      expect(repo.progressForPlan(splitId, 'push')!.revision, waiting.revision);
      expect(
        HiveService.readTrainingGraph(ownerId: 'owner').validate,
        returnsNormally,
      );
      // No week row exists yet, so the boundary sheet offers "Add week".
      expect(repo.weeksForBlock(splitId, block.id), hasLength(1));

      final week = await service.extendBoundary(
        planId: 'push',
        expectedRevision: waiting.revision,
      );
      expect(week.blockId, block.id);
      expect(week.number, 2);
      final moved = repo.progressForPlan(splitId, 'push')!;
      expect(moved.state, WorkoutProgressState.ready);
      expect(moved.activeWeekId, week.id);
      expect(stored(block.id).plannedWeekCount, 3);
      expect(
        HiveService.readTrainingGraph(ownerId: 'owner').validate,
        returnsNormally,
      );
    },
  );

  group('saving a plan into a just-created block', () {
    Future<WorkoutProgress> save(String planId, String weekId) async {
      final provider = WorkoutPlanProvider();
      await provider.addPlan(
        WorkoutPlan(
          id: planId,
          name: 'Pull $planId',
          splitId: splitId,
          userId: 'owner',
          exercises: [ExerciseTemplate(name: 'Row', sets: 1)],
        ),
        startingWeekId: weekId,
      );
      return repo.progressForPlan(splitId, planId)!;
    }

    test('at Week 1', () async {
      final block = await newBlock(weeks: 4);
      final week = repo.weeksForBlock(splitId, block.id).first;
      final progress = await save('a', week.id);
      expect(progress.activeWeekId, week.id);
      expect(progress.state, WorkoutProgressState.ready);
      expect(
        HiveService.readTrainingGraph(ownerId: 'owner').validate,
        returnsNormally,
      );
    });

    test('at a later, not yet persisted week', () async {
      final block = await newBlock(weeks: 4);
      final lazy = HiveService.startingWeeksForBlock(
        splitId,
        block.id,
      ).firstWhere((w) => w.number == 3);
      expect(repo.weeksForBlock(splitId, block.id).map((w) => w.number), [1]);
      final progress = await save('b', lazy.id);
      final active = HiveService.getTrainingWeekById(progress.activeWeekId)!;
      expect(active.blockId, block.id);
      expect(active.number, 3);
      expect(
        HiveService.readTrainingGraph(ownerId: 'owner').validate,
        returnsNormally,
      );
    });
  });
}
