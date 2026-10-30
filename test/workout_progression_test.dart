import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/completion_transition.dart';
import 'package:gymapp/providers/training_block_provider.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:gymapp/services/workout_progression_service.dart';

import 'support/hive_test_harness.dart';

void main() {
  final storage = HiveTestHarness();
  final now = DateTime.utc(2026, 10, 28, 12);
  late TrainingBlockRepository repo;
  late String first;
  late String second;
  late WorkoutProgressionService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    await HiveService.putSplitRaw(
      Split(id: 'split', name: 'Training', userId: 'owner', createdAt: now),
    );
    for (final id in ['push', 'pull']) {
      await HiveService.putPlanRaw(
        WorkoutPlan(
          id: id,
          name: id,
          exercises: [],
          splitId: 'split',
          userId: 'owner',
        ),
      );
    }
    await TrainingBlockMigration().normalize(ownerId: 'owner');
    repo = TrainingBlockRepository(ownerId: () => 'owner');
    final block = repo.blocksForSplit('split').single;
    first = repo.weeksForBlock('split', block.id).single.id;
    second = (await repo.appendWeek('split', block.id)).id;
    service = WorkoutProgressionService(
      ownerId: () => 'owner',
      clock: () => now,
    );
  });
  tearDown(storage.close);

  WorkoutProgress progress([String plan = 'push']) =>
      repo.progressForPlan('split', plan)!;
  Future<WorkoutSession> draft({
    String id = 'log',
    String plan = 'push',
    String? week,
  }) async {
    final value = WorkoutSession(
      id: id,
      planId: plan,
      planName: plan,
      splitId: 'split',
      userId: 'owner',
      trainingWeekId: week ?? first,
      weekNumber: week == second ? 2 : 1,
      date: now,
      isCompleted: false,
      startedAt: now.subtract(const Duration(minutes: 5)),
      timerStartedAt: now.subtract(const Duration(minutes: 5)),
      durationSeconds: 0,
      exercises: [],
    );
    await HiveService.putSessionRaw(value);
    return value;
  }

  for (final recovery in ['startup', 'restore', 'deleted-evidence']) {
    test('$recovery replays pending completion before data exposure', () async {
      final value = await draft();
      final pending = value.copyWith(
        isCompleted: true,
        timerStartedAt: null,
        deletedAt: recovery == 'deleted-evidence' ? now : null,
        completionTransition:
            CompletionTransition(
              expectedRevision: progress().revision,
              sourceWeekId: first,
              nextWeekId: second,
              resultRevision: 'log',
              committedAt: now,
            ).toJson(),
      );
      await HiveService.putSessionRaw(pending);
      if (recovery == 'restore') {
        await TrainingBlockRestore().replace(
          graph: HiveService.readTrainingGraph(ownerId: 'owner'),
        );
      } else {
        await TrainingBlockMigration().normalize(ownerId: 'owner');
      }
      expect(progress().activeWeekId, second);
      expect(progress().revision, 'log');
      if (recovery != 'restore') expect(progress().updatedAt, now);
    });
  }

  test(
    'provider indexes one split snapshot including duplicate saved destinations',
    () async {
      await draft(id: 'one');
      await draft(id: 'two');
      final provider = TrainingBlockProvider(
        splitIdProvider: () => 'split',
        ownerId: () => 'owner',
      );
      expect(provider.sessionsForSlot('push', first), hasLength(2));
      expect(provider.weekById[second]!.number, 2);
      expect(provider.progressByPlan.keys.toSet(), {'push', 'pull'});
      final before = provider.sessionsForSlot('push', first);
      await draft(id: 'three');
      expect(provider.sessionsForSlot('push', first), same(before));
      provider.reload();
      expect(provider.sessionsForSlot('push', first), hasLength(3));
      provider.dispose();
    },
  );

  test(
    'deleting the active week moves Push back without touching Pull',
    () async {
      await draft();
      await service.complete('log');
      await draft(id: 'push-2', week: second);
      await draft(id: 'pull-2', plan: 'pull', week: second);
      final before = progress();
      final pull = progress('pull');

      await service.removeWeek(planId: 'push', weekId: second);

      expect(HiveService.getSessionById('push-2')!.deletedAt, isNotNull);
      expect(HiveService.getSessionById('pull-2')!.deletedAt, isNull);
      expect(HiveService.getSessionById('log')!.deletedAt, isNull);
      expect(progress().activeWeekId, first);
      expect(progress().availableWeekIds, [first]);
      expect(progress().state, WorkoutProgressState.ready);
      expect(progress().revision, isNot(before.revision));
      expect(progress('pull').revision, pull.revision);
      expect(HiveService.getTrainingWeekById(second)!.deletedAt, isNull);
    },
  );

  test('deleting an earlier week keeps the active week', () async {
    await draft();
    await service.complete('log');

    await service.removeWeek(planId: 'push', weekId: first);

    expect(HiveService.getSessionById('log')!.deletedAt, isNotNull);
    expect(progress().activeWeekId, second);
    expect(progress().availableWeekIds, [second]);
    expect(progress().state, WorkoutProgressState.ready);
  });

  test('the only reached week and unreached weeks cannot be deleted', () async {
    await draft();
    final before = progress();
    await expectLater(
      service.removeWeek(planId: 'push', weekId: first),
      throwsStateError,
    );
    await expectLater(
      service.removeWeek(planId: 'push', weekId: second),
      throwsStateError,
    );
    expect(HiveService.getSessionById('log')!.deletedAt, isNull);
    expect(progress().revision, before.revision);
  });

  test(
    'completing Push advances only Push and retry creates no new log or PR',
    () async {
      await draft();
      final result = await service.complete('log');
      expect(result.session.isCompleted, isTrue);
      expect(result.session.isTimerRunning, isFalse);
      expect(result.session.durationSeconds, 300);
      expect(progress().activeWeekId, second);
      expect(progress('pull').activeWeekId, first);
      expect(progress().revision, 'log');
      expect(progress().updatedAt, now);
      expect((await service.complete('log')).personalRecords, isEmpty);
      expect(HiveService.getAllSessionsRaw(), hasLength(1));
    },
  );

  test('editing a completed log preserves its recorded outcome', () async {
    await draft();
    final result = await service.complete('log');
    await HiveService.upsertSession(
      result.session.copyWith(completionTransition: null),
    );
    expect(
      HiveService.getSessionById('log')!.completionTransition,
      result.session.completionTransition,
    );
  });

  test(
    'calendar passage and discarding a draft never advance progress',
    () async {
      final before = progress().toJson();
      await draft();
      await HiveService.softDeleteSession('log');
      await service.replay();
      expect(progress().toJson(), before);
    },
  );

  test(
    'a completion write failure preserves the running draft and progress',
    () async {
      final original = await draft();
      final before = progress().toJson();
      final failing = WorkoutProgressionService(
        ownerId: () => 'owner',
        clock: () => now,
        writeSession: (_) async => throw StateError('disk'),
      );
      await expectLater(failing.complete('log'), throwsStateError);
      expect(HiveService.getSessionById('log')!.toJson(), original.toJson());
      expect(progress().toJson(), before);
    },
  );

  test(
    'progress failure leaves successful completion and replay uses original time once',
    () async {
      await draft();
      final failing = WorkoutProgressionService(
        ownerId: () => 'owner',
        clock: () => now,
        writeProgress: (_) async => throw StateError('disk'),
      );
      final result = await failing.complete('log');
      expect(result.session.isCompleted, isTrue);
      expect(result.progressPending, isTrue);
      expect((await failing.complete('log')).session.isCompleted, isTrue);
      expect(progress().activeWeekId, first);
      final later = WorkoutProgressionService(
        ownerId: () => 'owner',
        clock: () => now.add(const Duration(days: 2)),
      );
      await later.replay();
      final applied = progress().toJson();
      expect(progress().updatedAt, now);
      await later.replay();
      expect(progress().toJson(), applied);
    },
  );

  test(
    'last supplied week enters boundary; a later explicit choice defeats old replay',
    () async {
      await HiveService.putWorkoutProgressRaw(
        progress().copyWith(
          availableWeekIds: [first, second],
          activeWeekId: second,
        ),
      );
      await draft(week: second);
      await service.complete('log');
      expect(progress().state, WorkoutProgressState.awaitingBoundary);
      final block = await repo.createBlock(
        splitId: 'split',
        name: 'Next',
        weekCount: 2,
      );
      final destination = repo.weeksForBlock('split', block.id).first.id;
      await service.chooseBoundary(
        planId: 'push',
        expectedRevision: 'log',
        destinationWeekId: destination,
      );
      final moved = progress().toJson();
      await service.replay();
      expect(progress().toJson(), moved);
      expect(progress().activeWeekId, destination);
      expect(progress('pull').activeWeekId, first);
    },
  );

  test(
    'boundary extension is reused; stale revision or reordered choice is rejected',
    () async {
      await HiveService.putWorkoutProgressRaw(
        progress().copyWith(
          availableWeekIds: [first, second],
          activeWeekId: second,
          state: WorkoutProgressState.awaitingBoundary,
        ),
      );
      final revision = progress().revision;
      final old = await repo.createBlock(
        splitId: 'split',
        name: 'Old next',
        weekCount: 1,
      );
      final next = await repo.createBlock(
        splitId: 'split',
        name: 'New next',
        weekCount: 1,
      );
      await repo.reorderBlocks('split', [
        repo.blocksForSplit('split').first.id,
        next.id,
        old.id,
      ]);
      await expectLater(
        service.chooseBoundary(
          planId: 'push',
          expectedRevision: revision,
          destinationWeekId: repo.weeksForBlock('split', old.id).single.id,
        ),
        throwsStateError,
      );
      final extension = await repo.appendWeek(
        'split',
        repo.blocksForSplit('split').first.id,
      );
      await service.chooseBoundary(
        planId: 'push',
        expectedRevision: revision,
        destinationWeekId: extension.id,
      );
      await expectLater(
        service.chooseBoundary(
          planId: 'push',
          expectedRevision: revision,
          destinationWeekId: extension.id,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'a changed revision at the same source week rejects stale evidence',
    () async {
      final value = await draft();
      final event = CompletionTransition(
        expectedRevision: progress().revision,
        sourceWeekId: first,
        nextWeekId: second,
        resultRevision: 'log',
        committedAt: now,
      );
      final changed = progress().copyWith(revision: 'newer', updatedAt: now);
      expect(
        WorkoutProgressionService.applyCompletion(
          changed,
          value.copyWith(
            isCompleted: true,
            completionTransition: event.toJson(),
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'competing completions apply only one event and explicit Continue does not log again',
    () async {
      final before = progress();
      for (final id in ['a', 'b']) {
        final value = await draft(id: id);
        await HiveService.putSessionRaw(
          value.copyWith(
            isCompleted: true,
            timerStartedAt: null,
            completionTransition:
                CompletionTransition(
                  expectedRevision: before.revision,
                  sourceWeekId: first,
                  nextWeekId: second,
                  resultRevision: id,
                  committedAt: now,
                ).toJson(),
          ),
        );
      }
      await service.replay();
      expect(progress().revision, 'a');
      await HiveService.putWorkoutProgressRaw(
        progress().copyWith(activeWeekId: first, revision: 'remote-choice'),
      );
      await service.continueCompleted(
        sessionId: 'b',
        expectedRevision: 'remote-choice',
      );
      expect(progress().activeWeekId, second);
      expect(HiveService.getAllSessionsRaw(), hasLength(2));
    },
  );

  test(
    'explicit Continue cannot pass an unfinished slot or another revision',
    () async {
      await draft();
      await expectLater(
        service.continueCompleted(
          sessionId: 'log',
          expectedRevision: progress().revision,
        ),
        throwsStateError,
      );
      await HiveService.putSessionRaw(
        HiveService.getSessionById('log')!.copyWith(isCompleted: true),
      );
      await expectLater(
        service.continueCompleted(sessionId: 'log', expectedRevision: 'stale'),
        throwsStateError,
      );
    },
  );

  test(
    'finishing a nonactive timer saves history without moving active progress',
    () async {
      await HiveService.putWorkoutProgressRaw(
        progress().copyWith(
          availableWeekIds: [first, second],
          activeWeekId: second,
          revision: 'moved',
        ),
      );
      await draft();
      final before = progress().toJson();
      final result = await service.complete('log');
      expect(result.session.isCompleted, isTrue);
      expect(result.session.completionTransition, isNull);
      expect(progress().toJson(), before);
    },
  );
  test(
    'boundary create retries its fixed structure and move after progress failure',
    () async {
      await HiveService.putWorkoutProgressRaw(
        progress().copyWith(
          availableWeekIds: [first, second],
          activeWeekId: second,
          state: WorkoutProgressState.awaitingBoundary,
        ),
      );
      final revision = progress().revision;
      final failing = WorkoutProgressionService(
        ownerId: () => 'owner',
        clock: () => now,
        writeProgress: (_) async => throw StateError('disk'),
      );
      await expectLater(
        failing.createBoundary(
          planId: 'push',
          expectedRevision: revision,
          name: 'Next',
          weekCount: 3,
        ),
        throwsStateError,
      );
      await expectLater(
        service.createBoundary(
          planId: 'push',
          expectedRevision: revision,
          name: 'Changed',
          weekCount: 4,
        ),
        throwsStateError,
      );
      final created = repo.blocksForSplit('split').last.id;
      final result = await service.createBoundary(
        planId: 'push',
        expectedRevision: revision,
        name: 'Next',
        weekCount: 3,
      );
      expect(result.id, created);
      expect(repo.blocksForSplit('split'), hasLength(2));
      expect(
        progress().activeWeekId,
        repo.weeksForBlock('split', created).first.id,
      );
      expect(progress('pull').activeWeekId, first);
    },
  );
  test(
    'stale create cannot allocate a block; an existing extension is reused on append',
    () async {
      await HiveService.putWorkoutProgressRaw(
        progress().copyWith(
          availableWeekIds: [first, second],
          activeWeekId: second,
          state: WorkoutProgressState.awaitingBoundary,
        ),
      );
      final revision = progress().revision;
      final extended = await repo.appendWeek(
        'split',
        repo.blocksForSplit('split').single.id,
      );
      await expectLater(
        service.createBoundary(
          planId: 'push',
          expectedRevision: revision,
          name: 'Extra',
          weekCount: 2,
        ),
        throwsStateError,
      );
      expect(repo.blocksForSplit('split'), hasLength(1));
      await service.extendBoundary(planId: 'push', expectedRevision: revision);
      expect(progress().activeWeekId, extended.id);
      expect(
        repo.weeksForBlock('split', repo.blocksForSplit('split').single.id),
        hasLength(3),
      );
    },
  );
}
