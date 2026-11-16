import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/workout_progression_service.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/services/training_block_restore.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/models/completion_transition.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/hive_test_harness.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/services/training_block_graph.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/services/training_plan_installer.dart';
import 'dart:convert';

void main() {
  final storage = HiveTestHarness();
  final now = DateTime.utc(2026, 10, 28);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    for (final id in ['a', 'b']) {
      await HiveService.putSplitRaw(
        Split(id: id, name: id, createdAt: now, userId: 'owner'),
      );
    }
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: 'p',
        name: 'Push',
        exercises: [],
        splitId: 'a',
        userId: 'owner',
      ),
    );
    await TrainingBlockMigration().normalize(ownerId: 'owner');
  });
  tearDown(storage.close);
  Future<void> reopen() async {
    await Hive.close();
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
    await Hive.openBox<Split>(HiveService.splitsBox);
    await Hive.openBox<SplitPreference>(HiveService.splitPreferencesBox);
    await HiveService.openTrainingBoxes();
  }

  Future<void> pendingCreation() async {
    final block = TrainingBlock(
      id: 'pending',
      splitId: 'a',
      name: 'Pending',
      position: 1,
      createdAt: now,
      userId: 'owner',
    );
    final week = TrainingWeek(
      id: 'pending-week',
      splitId: 'a',
      blockId: block.id,
      number: 1,
      createdAt: now,
      userId: 'owner',
    );
    await Hive.box<dynamic>(HiveService.trainingOperationsBox).put('create', {
      'ownerId': 'owner',
      'block': block.toJson(),
      'weeks': [week.toJson()],
    });
  }

  test(
    'split deletion finishes earlier pending creation before tombstoning it',
    () async {
      await pendingCreation();
      await HiveService.softDeleteSplit(
        userId: 'owner',
        splitId: 'a',
        replacementSplitId: 'b',
      );
      await reopen();
      await TrainingBlockMigration().normalize(ownerId: 'owner');
      expect(HiveService.getTrainingBlockById('pending')!.deletedAt, isNotNull);
      expect(
        Hive.box<dynamic>(HiveService.trainingOperationsBox).isEmpty,
        isTrue,
      );
    },
  );

  test(
    'an installer completes earlier pending structure rather than discarding it',
    () async {
      await pendingCreation();
      await installTrainingPlansUnderGate(
        ownerId: 'owner',
        plans: {
          'new': WorkoutPlan(
            id: 'new',
            name: 'Pull',
            exercises: [],
            splitId: 'a',
            userId: 'owner',
          ),
        },
      );
      expect(HiveService.getTrainingBlockById('pending')!.deletedAt, isNull);
      expect(
        Hive.box<dynamic>(HiveService.trainingOperationsBox).isEmpty,
        isTrue,
      );
    },
  );
  test(
    'explicit replacement rollback restores the original pending operation',
    () async {
      final desired = HiveService.readTrainingGraph(
        ownerId: 'owner',
      ).remap(ownerId: 'owner', remapExerciseIds: false);
      await pendingCreation();
      final writer = TrainingBlockRestore(
        onPhase: (phase) async {
          if (phase == 'parents') throw StateError('disk');
        },
      );
      await expectLater(writer.replace(graph: desired), throwsStateError);
      expect(
        Hive.box<dynamic>(HiveService.trainingOperationsBox).isEmpty,
        isTrue,
      );
      await writer.rollbackUnderGate('owner');
      expect(
        Hive.box<dynamic>(
          HiveService.trainingOperationsBox,
        ).containsKey('create'),
        isTrue,
      );
      await reopen();
      await TrainingBlockMigration().normalize(ownerId: 'owner');
      expect(HiveService.getTrainingBlockById('pending')!.deletedAt, isNull);
    },
  );
  test('restore supersedes pending creation for replaced split', () async {
    final desired = HiveService.readTrainingGraph(
      ownerId: 'owner',
    ).remap(ownerId: 'owner', remapExerciseIds: false);
    final block = TrainingBlock(
      id: 'pending',
      splitId: 'a',
      name: 'Pending',
      position: 1,
      createdAt: now,
      userId: 'owner',
    );
    final week = TrainingWeek(
      id: 'pending-week',
      splitId: 'a',
      blockId: 'pending',
      number: 1,
      createdAt: now,
      userId: 'owner',
    );
    await Hive.box<dynamic>(HiveService.trainingOperationsBox).put('create', {
      'ownerId': 'owner',
      'block': block.toJson(),
      'weeks': [week.toJson()],
    });
    await TrainingBlockRestore().replace(graph: desired);
    await reopen();
    await TrainingBlockRestore().recover(ownerId: 'owner');
    await TrainingBlockMigration().normalize(ownerId: 'owner');
    HiveService.readTrainingGraph(ownerId: 'owner').validate();
  });
  test(
    'split deletion persists preference then parent before descendants and restarts mid-cascade',
    () async {
      await HiveService.setActiveSplit('owner', 'a');
      final parentAtChild = <bool>[];
      TrainingBlockGraph? interrupted;
      final childEvents = Hive.box<TrainingBlock>(
        HiveService.trainingBlocksBox,
      ).watch().listen((event) {
        final block = event.value as TrainingBlock?;
        if (block?.splitId == 'a' && block?.deletedAt != null) {
          parentAtChild.add(HiveService.getSplitById('a')!.deletedAt != null);
        }
      });
      final parentEvents = Hive.box<Split>(
        HiveService.splitsBox,
      ).watch(key: 'a').listen((event) {
        if ((event.value as Split?)?.deletedAt != null) {
          expect(HiveService.getActiveSplitId('owner'), 'b');
          interrupted = TrainingBlockGraph.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(
                    jsonEncode(
                      HiveService.readTrainingGraph(ownerId: 'owner').toJson(),
                    ),
                  )
                  as Map,
            ),
          );
        }
      });
      await HiveService.softDeleteSplit(
        userId: 'owner',
        splitId: 'a',
        replacementSplitId: 'b',
      );
      await Future<void>.delayed(Duration.zero);
      await childEvents.cancel();
      await parentEvents.cancel();
      expect(parentAtChild, isNotEmpty);
      expect(parentAtChild, everyElement(isTrue));
      final snapshot = interrupted!;
      expect(
        snapshot.blocks.any((b) => b.splitId == 'a' && b.deletedAt == null),
        isTrue,
      );
      for (final p in snapshot.plans) {
        await HiveService.putPlanRaw(p);
      }
      for (final b in snapshot.blocks) {
        await HiveService.putTrainingBlockRaw(b);
      }
      for (final w in snapshot.weeks) {
        await HiveService.putTrainingWeekRaw(w);
      }
      for (final p in snapshot.progress) {
        await HiveService.putWorkoutProgressRaw(p);
      }
      await reopen();
      await TrainingBlockMigration().normalize(ownerId: 'owner');
      HiveService.readTrainingGraph(ownerId: 'owner').validate();
      expect(HiveService.blocksForSplit('a'), isEmpty);
    },
  );
  test('stale draft save after completion leaves graph recoverable', () async {
    final week = HiveService.getAllTrainingWeeksRaw().firstWhere(
      (w) => w.splitId == 'a',
    );
    final p = HiveService.progressForPlan('a', 'p')!;
    final stale = WorkoutSession(
      id: 'log',
      date: now,
      planName: 'Push',
      exercises: [],
      splitId: 'a',
      planId: 'p',
      userId: 'owner',
      trainingWeekId: week.id,
      weekNumber: week.number,
      isCompleted: false,
      startedAt: now,
      timerStartedAt: now,
      durationSeconds: 0,
    );
    await HiveService.putSessionRaw(
      stale.copyWith(
        isCompleted: true,
        timerStartedAt: null,
        completionTransition:
            CompletionTransition(
              expectedRevision: p.revision,
              sourceWeekId: week.id,
              nextWeekId: null,
              resultRevision: 'log',
              committedAt: now,
            ).toJson(),
      ),
    );
    await expectLater(HiveService.upsertSession(stale), throwsStateError);
    await reopen();
    await TrainingBlockMigration().normalize(ownerId: 'owner');
    HiveService.readTrainingGraph(ownerId: 'owner').validate();
  });

  test('the installer stamps the duration clock when it sets or raises a '
      'block length', () async {
    SyncService.instance.setNegotiatedSchema('owner', 4);
    addTearDown(SyncService.instance.forgetNegotiatedSchemas);
    final before = DateTime.now();
    // Split b exists with its default block and nothing in it: a raise.
    final existing = HiveService.blocksForSplit('b').single;
    expect(existing.plannedWeekCount, lessThan(6));
    await installTrainingPlansUnderGate(
      ownerId: 'owner',
      split: HiveService.getSplitById('b'),
      initialBlockWeekCount: 6,
      plans: {
        'x': WorkoutPlan(
          id: 'x',
          name: 'X',
          exercises: [],
          splitId: 'b',
          userId: 'owner',
        ),
      },
    );
    final raised = HiveService.blocksForSplit('b').single;
    expect(raised.plannedWeekCount, 6);
    expect(raised.plannedWeekCountUpdatedAt, isNotNull);
    expect(
      raised.plannedWeekCountUpdatedAt!.isBefore(
        before.subtract(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    // A split with no block yet gets a stamped one.
    final fresh = Split(id: 'c', name: 'c', createdAt: now, userId: 'owner');
    await installTrainingPlansUnderGate(
      ownerId: 'owner',
      split: fresh,
      initialBlockWeekCount: 5,
      plans: {
        'y': WorkoutPlan(
          id: 'y',
          name: 'Y',
          exercises: [],
          splitId: 'c',
          userId: 'owner',
        ),
      },
    );
    final created = HiveService.blocksForSplit('c').single;
    expect(created.plannedWeekCount, 5);
    expect(created.plannedWeekCountUpdatedAt, isNotNull);
  });

  test('below schema 4 the installer and the boundary writers stamp no clock, '
      'and an intent stamped earlier loses its clock on recovery', () async {
    final repo = TrainingBlockRepository(ownerId: () => 'owner');
    await installTrainingPlansUnderGate(
      ownerId: 'owner',
      split: HiveService.getSplitById('b'),
      initialBlockWeekCount: 6,
      plans: {
        'x': WorkoutPlan(
          id: 'x',
          name: 'X',
          exercises: [],
          splitId: 'b',
          userId: 'owner',
        ),
      },
    );
    expect(HiveService.blocksForSplit('b').single.plannedWeekCount, 6);
    expect(
      HiveService.blocksForSplit('b').single.plannedWeekCountUpdatedAt,
      isNull,
    );
    final fresh = Split(id: 'c', name: 'c', createdAt: now, userId: 'owner');
    await installTrainingPlansUnderGate(
      ownerId: 'owner',
      split: fresh,
      initialBlockWeekCount: 5,
      plans: {
        'y': WorkoutPlan(
          id: 'y',
          name: 'Y',
          exercises: [],
          splitId: 'c',
          userId: 'owner',
        ),
      },
    );
    expect(
      HiveService.blocksForSplit('c').single.plannedWeekCountUpdatedAt,
      isNull,
    );
    final block = await repo.createBlock(
      splitId: 'a',
      name: 'Short',
      weekCount: 1,
    );
    final first = repo.weeksForBlock('a', block.id).single;
    Future<String> awaitBoundary() async {
      await HiveService.putWorkoutProgressRaw(
        repo
            .progressForPlan('a', 'p')!
            .copyWith(
              activeWeekId: first.id,
              availableWeekIds: [first.id],
              state: WorkoutProgressState.awaitingBoundary,
            ),
      );
      return HiveService.progressForPlan('a', 'p')!.revision;
    }

    final service = WorkoutProgressionService(ownerId: () => 'owner');
    await service.extendBoundary(
      planId: 'p',
      expectedRevision: await awaitBoundary(),
    );
    expect(HiveService.getTrainingBlockById(block.id)!.plannedWeekCount, 2);
    expect(
      HiveService.getTrainingBlockById(block.id)!.plannedWeekCountUpdatedAt,
      isNull,
    );
    final solo = await repo.createBlock(
      splitId: 'a',
      name: 'Solo',
      weekCount: 1,
    );
    final soloWeek = repo.weeksForBlock('a', solo.id).single;
    await HiveService.putWorkoutProgressRaw(
      repo
          .progressForPlan('a', 'p')!
          .copyWith(
            activeWeekId: soloWeek.id,
            availableWeekIds: [soloWeek.id],
            state: WorkoutProgressState.awaitingBoundary,
          ),
    );
    final created = await service.createBoundary(
      planId: 'p',
      expectedRevision: HiveService.progressForPlan('a', 'p')!.revision,
      name: 'Next',
      weekCount: 3,
    );
    expect(created.plannedWeekCountUpdatedAt, isNull);

    // An extension journaled while the account was at 4, recovered after it
    // is known to be below.
    SyncService.instance.setNegotiatedSchema('owner', 4);
    final other = await repo.createBlock(
      splitId: 'a',
      name: 'Journaled',
      weekCount: 1,
    );
    final otherFirst = repo.weeksForBlock('a', other.id).single;
    await HiveService.putWorkoutProgressRaw(
      repo
          .progressForPlan('a', 'p')!
          .copyWith(
            activeWeekId: otherFirst.id,
            availableWeekIds: [otherFirst.id],
            state: WorkoutProgressState.awaitingBoundary,
          ),
    );
    final crashing = WorkoutProgressionService(
      ownerId: () => 'owner',
      writeProgress: (_) async => throw StateError('disk'),
    );
    await expectLater(
      crashing.extendBoundary(
        planId: 'p',
        expectedRevision: HiveService.progressForPlan('a', 'p')!.revision,
      ),
      throwsStateError,
    );
    expect(
      HiveService.getTrainingBlockById(other.id)!.plannedWeekCountUpdatedAt,
      isNotNull,
    );
    await HiveService.putTrainingBlockRaw(
      HiveService.getTrainingBlockById(
        other.id,
      )!.copyWith(plannedWeekCount: 1, plannedWeekCountUpdatedAt: now),
    );
    SyncService.instance.setNegotiatedSchema('owner', 3);
    addTearDown(SyncService.instance.forgetNegotiatedSchemas);
    await WorkoutProgressionService.recoverBoundaryUnderGate(ownerId: 'owner');
    final saved = HiveService.getTrainingBlockById(other.id)!;
    expect(saved.plannedWeekCount, 2);
    expect(saved.plannedWeekCountUpdatedAt, isNull);
  });

  group('boundary choices and the duration clock', () {
    final tExtend = DateTime.utc(2026, 11, 20, 9);
    setUp(() {
      // These account for a server which resolves length on the clock.
      SyncService.instance.setNegotiatedSchema('owner', 4);
      addTearDown(SyncService.instance.forgetNegotiatedSchemas);
    });
    late TrainingBlock block;
    late TrainingWeek first;

    Future<void> awaitBoundaryAtFirstWeek() async {
      final repo = TrainingBlockRepository(ownerId: () => 'owner');
      block = await repo.createBlock(splitId: 'a', name: 'Short', weekCount: 1);
      first = repo.weeksForBlock('a', block.id).single;
      await HiveService.putWorkoutProgressRaw(
        repo
            .progressForPlan('a', 'p')!
            .copyWith(
              activeWeekId: first.id,
              availableWeekIds: [first.id],
              state: WorkoutProgressState.awaitingBoundary,
            ),
      );
    }

    test(
      'extendBoundary stamps the clock, in the block and in the intent',
      () async {
        await awaitBoundaryAtFirstWeek();
        final revision = HiveService.progressForPlan('a', 'p')!.revision;
        final crashing = WorkoutProgressionService(
          ownerId: () => 'owner',
          clock: () => tExtend,
          writeProgress: (_) async => throw StateError('disk'),
        );
        await expectLater(
          crashing.extendBoundary(planId: 'p', expectedRevision: revision),
          throwsStateError,
        );
        final saved = HiveService.getTrainingBlockById(block.id)!;
        expect(saved.plannedWeekCount, 2);
        expect(saved.plannedWeekCountUpdatedAt, tExtend);
        final intent = Map<String, dynamic>.from(
          Hive.box<dynamic>(HiveService.trainingOperationsBox).get('boundary')
              as Map,
        );
        expect(
          (intent['block'] as Map)['plannedWeekCountUpdatedAt'],
          tExtend.toIso8601String(),
        );
      },
    );

    test('recovering an extension copies the clock from the intent', () async {
      await awaitBoundaryAtFirstWeek();
      final revision = HiveService.progressForPlan('a', 'p')!.revision;
      await expectLater(
        WorkoutProgressionService(
          ownerId: () => 'owner',
          clock: () => tExtend,
          writeProgress: (_) async => throw StateError('disk'),
        ).extendBoundary(planId: 'p', expectedRevision: revision),
        throwsStateError,
      );
      // The crash happened before the block write reached disk.
      await HiveService.putTrainingBlockRaw(
        HiveService.getTrainingBlockById(
          block.id,
        )!.copyWith(plannedWeekCount: 1, plannedWeekCountUpdatedAt: now),
      );
      await WorkoutProgressionService.recoverBoundaryUnderGate(
        ownerId: 'owner',
      );
      final saved = HiveService.getTrainingBlockById(block.id)!;
      expect(saved.plannedWeekCount, 2);
      expect(saved.plannedWeekCountUpdatedAt, tExtend);
    });

    test('createBoundary stamps the new block', () async {
      await awaitBoundaryAtFirstWeek();
      final revision = HiveService.progressForPlan('a', 'p')!.revision;
      final created = await WorkoutProgressionService(
        ownerId: () => 'owner',
        clock: () => tExtend,
      ).createBoundary(
        planId: 'p',
        expectedRevision: revision,
        name: 'Next',
        weekCount: 3,
      );
      expect(created.plannedWeekCount, 3);
      expect(created.plannedWeekCountUpdatedAt, tExtend);
    });

    test('an append for a block deleted elsewhere is dropped, not thrown, and '
        'the plan is rescued at startup', () async {
      await awaitBoundaryAtFirstWeek();
      final progress = HiveService.progressForPlan('a', 'p')!;
      final week2 = TrainingWeek(
        id: lazyTrainingWeekId('a', block.id, 2),
        splitId: 'a',
        blockId: block.id,
        number: 2,
        createdAt: now,
        userId: 'owner',
        dirty: true,
      );
      await Hive.box<dynamic>(HiveService.trainingOperationsBox).put(
        'boundary',
        {
          'ownerId': 'owner',
          'action': 'append',
          'planId': 'p',
          'expectedRevision': progress.revision,
          'sourceWeekId': first.id,
          'block': block.copyWith(plannedWeekCount: 2).toJson(),
          'weeks': [week2.toJson()],
          'progress':
              progress
                  .copyWith(
                    activeWeekId: week2.id,
                    availableWeekIds: [first.id, week2.id],
                    state: WorkoutProgressState.ready,
                    revision: 'moved',
                  )
                  .toJson(),
        },
      );
      // Another device deleted the block and its weeks.
      await HiveService.putTrainingBlockRaw(
        block.copyWith(deletedAt: now, updatedAt: now, dirty: false),
      );
      await HiveService.putTrainingWeekRaw(
        first.copyWith(deletedAt: now, updatedAt: now, dirty: false),
      );
      expect(
        await WorkoutProgressionService.recoverBoundaryUnderGate(
          ownerId: 'owner',
        ),
        isNull,
      );
      expect(
        Hive.box<dynamic>(HiveService.trainingOperationsBox).isEmpty,
        isTrue,
      );
      expect(HiveService.getTrainingWeekById(week2.id), isNull);
      expect(
        HiveService.progressForPlan('a', 'p')!.state,
        WorkoutProgressState.awaitingBoundary,
      );
      await TrainingBlockMigration().normalize(ownerId: 'owner');
      final moved = HiveService.progressForPlan('a', 'p')!;
      final active = HiveService.getTrainingWeekById(moved.activeWeekId)!;
      expect(active.deletedAt, isNull);
      expect(active.blockId, rescuedTrainingBlockId(block.id));
      expect(moved.state, WorkoutProgressState.awaitingBoundary);
      expect(
        HiveService.readTrainingGraph(ownerId: 'owner').validate,
        returnsNormally,
      );
    });
  });
}
