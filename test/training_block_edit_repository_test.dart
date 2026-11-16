import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/workout_progression_service.dart';
import 'package:gymapp/utils/training_block_identity.dart';

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

    test('without lifecycle support shrinking is rejected and leaves the block '
        'alone', () async {
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

  group('shortening with lifecycle support', () {
    late TrainingBlockRepository lifecycle;
    setUp(() {
      lifecycle = TrainingBlockRepository(
        ownerId: () => 'owner',
        lifecycleAvailable: (_) => true,
      );
    });

    Future<TrainingBlock> shorten(TrainingBlock block, int count) =>
        lifecycle.updateBlock(
          splitId: splitId,
          blockId: block.id,
          name: block.name,
          weekCount: count,
        );

    Future<void> tombstone(String weekId) async {
      final week = HiveService.getTrainingWeekById(weekId)!;
      await HiveService.putTrainingWeekRaw(
        week.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      );
    }

    /// A 6-week block whose Week 4 row exists but is hidden, so the only thing
    /// holding the floor at 4 is what the test attaches to it.
    Future<(TrainingBlock, String)> blockWithHiddenWeek4() async {
      final block = await newBlock(weeks: 6);
      for (var n = 2; n <= 4; n++) {
        await repo.appendWeek(splitId, block.id);
      }
      // appendWeek only grows the count; put it back to 6 for the test.
      await HiveService.putTrainingBlockRaw(
        stored(block.id).copyWith(plannedWeekCount: 6),
      );
      final week4 = repo.weeksForBlock(splitId, block.id).last;
      expect(week4.number, 4);
      return (stored(block.id), week4.id);
    }

    Future<void> expectFloor(TrainingBlock block, int floor) async {
      expect(lifecycle.minimumWeekCount(splitId, block.id), floor);
      await expectLater(
        shorten(block, floor - 1),
        throwsArgumentError,
        reason: 'below the floor',
      );
      expect(stored(block.id).plannedWeekCount, 6);
      final changed = await shorten(block, floor);
      expect(changed.plannedWeekCount, floor);
    }

    test(
      'an unused block shortens to its allocated weeks and stamps the clock',
      () async {
        final block = await newBlock(weeks: 6);
        expect(lifecycle.lifecycleAvailable, isTrue);
        expect(lifecycle.minimumWeekCount(splitId, block.id), 1);
        final before = stored(block.id).plannedWeekCountUpdatedAt!;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final shorter = await shorten(block, 2);
        expect(shorter.plannedWeekCount, 2);
        expect(
          stored(block.id).plannedWeekCountUpdatedAt!.isAfter(before),
          isTrue,
        );
        expect(stored(block.id).dirty, isTrue);
        expect(repo.weeksForBlock(splitId, block.id), hasLength(1));
        // And it can be lengthened again afterwards.
        expect((await shorten(block, 5)).plannedWeekCount, 5);
      },
    );

    test('the default repository keeps the grow-only rule', () async {
      final block = await newBlock(weeks: 6);
      expect(repo.lifecycleAvailable, isFalse);
      expect(repo.minimumWeekCount(splitId, block.id), 6);
      await expectLater(
        repo.updateBlock(
          splitId: splitId,
          blockId: block.id,
          name: block.name,
          weekCount: 2,
        ),
        throwsArgumentError,
      );
      expect(stored(block.id).plannedWeekCount, 6);
    });

    test('rename and unchanged saves leave the duration clock alone', () async {
      final block = await newBlock(weeks: 6);
      final clock = stored(block.id).plannedWeekCountUpdatedAt;
      expect(clock, isNotNull);
      await lifecycle.updateBlock(
        splitId: splitId,
        blockId: block.id,
        name: 'Renamed',
        weekCount: 6,
      );
      expect(stored(block.id).name, 'Renamed');
      expect(stored(block.id).plannedWeekCountUpdatedAt, clock);
      await repo.renameBlock(splitId, block.id, 'Again');
      expect(stored(block.id).plannedWeekCountUpdatedAt, clock);
    });

    test('live week rows hold the floor', () async {
      final (block, _) = await blockWithHiddenWeek4();
      await expectFloor(block, 4);
    });

    test('live progress on an active week holds the floor', () async {
      final (block, week4) = await blockWithHiddenWeek4();
      await HiveService.putWorkoutProgressRaw(
        repo
            .progressForPlan(splitId, 'push')!
            .copyWith(activeWeekId: week4, availableWeekIds: [week4]),
      );
      await tombstone(week4);
      await expectFloor(block, 4);
    });

    test('an available week of live progress holds the floor', () async {
      final (block, week4) = await blockWithHiddenWeek4();
      final first = repo.weeksForBlock(splitId, block.id).first;
      await HiveService.putWorkoutProgressRaw(
        repo
            .progressForPlan(splitId, 'push')!
            .copyWith(
              activeWeekId: first.id,
              availableWeekIds: [first.id, week4],
            ),
      );
      await tombstone(week4);
      await expectFloor(block, 4);
    });

    for (final completed in [true, false]) {
      test(
        'a ${completed ? 'completed' : 'draft'} session holds the floor',
        () async {
          final (block, week4) = await blockWithHiddenWeek4();
          await HiveService.putSessionRaw(
            WorkoutSession(
              id: 'log',
              date: now,
              planName: 'Push',
              planId: 'push',
              splitId: splitId,
              userId: 'owner',
              weekNumber: 4,
              trainingWeekId: week4,
              isCompleted: completed,
              exercises: [],
            ),
          );
          await tombstone(week4);
          await expectFloor(block, 4);
        },
      );
    }

    test('completion evidence naming a later week holds the floor', () async {
      final (block, week4) = await blockWithHiddenWeek4();
      final first = repo.weeksForBlock(splitId, block.id).first;
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'log',
          date: now,
          planName: 'Push',
          planId: 'push',
          splitId: splitId,
          userId: 'owner',
          weekNumber: 1,
          trainingWeekId: first.id,
          isCompleted: true,
          exercises: [],
          completionTransition: {
            'expectedRevision': 'r',
            'sourceWeekId': first.id,
            'nextWeekId': week4,
            'resultRevision': 'log',
            'committedAt': now.toIso8601String(),
          },
        ),
      );
      await tombstone(week4);
      final floor = lifecycle.minimumWeekCount(splitId, block.id);
      expect(floor, 4);
    });

    test(
      'the floor is recomputed after an interrupted write is recovered',
      () async {
        final block = await newBlock(weeks: 6);
        final first = repo.weeksForBlock(splitId, block.id).first;
        // A boundary extension was persisted but not yet applied: it will add
        // Week 2 to this block when recovered.
        final progress = repo.progressForPlan(splitId, 'push')!;
        await HiveService.putWorkoutProgressRaw(
          progress.copyWith(
            activeWeekId: first.id,
            availableWeekIds: [first.id],
            state: WorkoutProgressState.awaitingBoundary,
          ),
        );
        final week2 = TrainingWeek(
          id: lazyTrainingWeekId(splitId, block.id, 2),
          splitId: splitId,
          blockId: block.id,
          number: 2,
          createdAt: now,
          userId: 'owner',
          dirty: true,
        );
        final target = repo
            .progressForPlan(splitId, 'push')!
            .copyWith(
              activeWeekId: week2.id,
              availableWeekIds: [first.id, week2.id],
              state: WorkoutProgressState.ready,
              revision: 'moved',
            );
        await Hive.box<dynamic>(HiveService.trainingOperationsBox).put(
          'boundary',
          {
            'ownerId': 'owner',
            'action': 'append',
            'planId': 'push',
            'expectedRevision': progress.revision,
            'sourceWeekId': first.id,
            'block': stored(block.id).copyWith(plannedWeekCount: 6).toJson(),
            'weeks': [week2.toJson()],
            'progress': target.toJson(),
          },
        );
        expect(lifecycle.minimumWeekCount(splitId, block.id), 1);
        await expectLater(shorten(block, 1), throwsArgumentError);
        expect(stored(block.id).plannedWeekCount, 6);
        expect((await shorten(block, 2)).plannedWeekCount, 2);
      },
    );
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
