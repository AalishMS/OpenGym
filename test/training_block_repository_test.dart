import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/completion_transition.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
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
    'empty weeks persist without creating sessions; adapters round trip',
    () async {
      final block = await repository.createBlock(
        splitId: splitId,
        name: ' Build ',
        weekCount: 3,
      );
      expect(block.name, 'Build');
      expect(repository.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
        2,
        3,
      ]);
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
      expect((await repository.appendWeek(splitId, block.id)).number, 4);
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
}
