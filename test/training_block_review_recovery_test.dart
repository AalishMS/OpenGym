import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gymapp/models/training_block.dart';
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
      ).remap(ownerId: 'owner');
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
    ).remap(ownerId: 'owner');
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
}
