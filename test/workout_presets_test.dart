import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/data/exercise_library.dart';
import 'package:gymapp/data/workout_presets.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/workout_progression_service.dart';
import 'package:gymapp/repositories/training_block_repository.dart';

import 'support/hive_test_harness.dart';
import 'package:gymapp/services/workout_preset_installer.dart';
import 'package:gymapp/utils/split_identity.dart';

void main() {
  final hiveHarness = HiveTestHarness();
  const userId = 'preset-user';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open(includeSplits: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HiveService.clearTrainingData();
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  test(
    'catalog contains all researched programs and expanded workout days',
    () {
      expect(workoutPresets, hasLength(10));
      expect(workoutPresets.map((preset) => preset.id).toSet(), hasLength(10));
      expect(workoutPresets.expand((preset) => preset.plans), hasLength(46));
      expect(
        workoutPresets
            .expand((preset) => preset.plans)
            .expand((plan) => plan.exercises),
        hasLength(269),
      );

      final library = ExerciseLibrary.allExercises.toSet();
      for (final preset in workoutPresets) {
        expect(preset.installName.length, lessThanOrEqualTo(24));
        for (final slot in preset.scheduleSlots.whereType<int>()) {
          expect(slot, inInclusiveRange(0, preset.plans.length - 1));
        }
        for (final plan in preset.plans) {
          expect(plan.colorSlot, inInclusiveRange(0, 9));
          for (final exercise in plan.exercises) {
            expect(library, contains(exercise.name));
            expect(exercise.seedReps, isNotEmpty);
            final template = exercise.toTemplate();
            expect(template.sets, exercise.seedReps.length);
            expect(template.setTargets, hasLength(template.sets));
            expect(
              template.setTargets!.every((target) => target.weight == 0),
              isTrue,
            );
          }
        }
      }
    },
  );

  test('shared days are expanded and special notes retain research cues', () {
    final ppl = _preset('HYP-PPL-6');
    final arnold = _preset('HYP-ARNOLD-6');
    expect(
      arnold.plans[2].exercises.map((exercise) => exercise.name),
      ppl.plans[2].exercises.map((exercise) => exercise.name),
    );

    final strength = _preset('STR-UL-4');
    final descending = strength.plans.first.exercises.first;
    expect(descending.seedReps, [1, 3, 5]);
    expect(descending.note, contains('not a max'));
    final pullUps = strength.plans.first.exercises.firstWhere(
      (exercise) => exercise.name == 'Pull-ups',
    );
    expect(pullUps.note, contains('added load'));
  });

  test('position and exercise note survive plan JSON', () {
    final plan = WorkoutPlan(
      id: 'plan',
      splitId: 'split',
      name: 'Ordered',
      position: 4,
      exercises: [
        ExerciseTemplate(
          name: 'Bench Press',
          sets: 1,
          note: 'Controlled practice.',
          setTargets: [SetTemplate(reps: 3, weight: 0)],
        ),
      ],
    );
    final restored = WorkoutPlan.fromJson(plan.toJson());
    expect(restored.position, 4);
    expect(restored.exercises.single.note, 'Controlled practice.');
  });

  test(
    'positioned plans sort before legacy plans regardless of arrival order',
    () async {
      await HiveService.putPlanRaw(
        WorkoutPlan(
          id: 'late',
          splitId: 's',
          name: 'Late',
          position: 2,
          exercises: [],
        ),
      );
      await HiveService.putPlanRaw(
        WorkoutPlan(
          id: 'legacy-a',
          splitId: 's',
          name: 'Legacy A',
          exercises: [],
        ),
      );
      await HiveService.putPlanRaw(
        WorkoutPlan(
          id: 'first',
          splitId: 's',
          name: 'First',
          position: 0,
          exercises: [],
        ),
      );
      await HiveService.putPlanRaw(
        WorkoutPlan(
          id: 'legacy-b',
          splitId: 's',
          name: 'Legacy B',
          exercises: [],
        ),
      );
      await HiveService.putPlanRaw(
        WorkoutPlan(
          id: 'middle',
          splitId: 's',
          name: 'Middle',
          position: 1,
          exercises: [],
        ),
      );

      expect(HiveService.getPlans(splitId: 's').map((plan) => plan.id), [
        'first',
        'middle',
        'late',
        'legacy-a',
        'legacy-b',
      ]);
    },
  );

  test('installation reuses only untouched deterministic My Split', () async {
    final defaultId = await _seedDefault(userId);
    final result = await const WorkoutPresetInstaller().install(
      preset: _preset('HYP-FB-3'),
      userId: userId,
      maxSplits: 5,
    );

    expect(result.splitId, defaultId);
    expect(result.reusedDefaultSplit, isTrue);
    expect(HiveService.getSplits().single.name, 'Full body hypertrophy');
    expect(HiveService.getSplits().single.dirty, isTrue);
    expect(HiveService.getSplitPreference(userId)?.activeSplitId, defaultId);
    expect(HiveService.getSplitPreference(userId)?.dirty, isTrue);
    final plans = HiveService.getPlans(splitId: defaultId);
    expect(plans.map((plan) => plan.position), [0, 1, 2]);
    expect(plans.every((plan) => plan.dirty == true), isTrue);
    expect(HiveService.getAllTrainingWeeksRaw(), hasLength(1));
    expect(HiveService.getAllWorkoutProgressRaw(), hasLength(plans.length));
    expect(
      HiveService.getAllWorkoutProgressRaw().every((p) => p.userId == userId),
      isTrue,
    );
  });

  test('custom empty training structure prevents default reuse', () async {
    final id = await _seedDefault(userId);
    await TrainingBlockMigration().normalize(ownerId: userId);
    final repo = TrainingBlockRepository(ownerId: () => userId);
    final block = repo.blocksForSplit(id).single;
    await repo.renameBlock(id, block.id, 'Recovery');
    final result = await const WorkoutPresetInstaller().install(
      preset: _preset('STR-FB-3'),
      userId: userId,
      maxSplits: 5,
    );
    expect(result.reusedDefaultSplit, isFalse);
    expect(repo.blocksForSplit(id).single.name, 'Recovery');
  });

  for (final preset in workoutPresets) {
    test('${preset.id} starts Block 1 with four intended weeks', () async {
      final result = await const WorkoutPresetInstaller().install(
        preset: preset,
        userId: userId,
        maxSplits: 5,
      );
      final repo = TrainingBlockRepository(ownerId: () => userId);
      final block = repo.blocksForSplit(result.splitId).single;
      expect(block.name, 'Block 1');
      expect(block.plannedWeekCount, 4);
      final first = repo.weeksForBlock(result.splitId, block.id).single;
      expect(first.number, 1);
      for (final plan in HiveService.getPlans(splitId: result.splitId)) {
        final progress = repo.progressForPlan(result.splitId, plan.id!)!;
        expect(progress.activeWeekId, first.id);
        expect(progress.availableWeekIds, [first.id]);
        expect(progress.state, WorkoutProgressState.ready);
      }
    });
  }

  test('reused bootstrap block gets the four-week preset length', () async {
    final id = await _seedDefault(userId);
    await TrainingBlockMigration().normalize(ownerId: userId);
    final original = HiveService.blocksForSplit(id).single;
    expect(original.plannedWeekCount, 1);
    final result = await const WorkoutPresetInstaller().install(
      preset: _preset('HYP-FB-3'),
      userId: userId,
      maxSplits: 5,
    );
    expect(result.reusedDefaultSplit, isTrue);
    final block = HiveService.blocksForSplit(id).single;
    expect(block.id, original.id);
    expect(block.plannedWeekCount, 4);
    expect(block.dirty, isTrue);
    expect(HiveService.weeksForBlock(id, block.id), hasLength(1));
  });

  for (final createBlock in [false, true]) {
    test(
      'preset advances four weeks then ${createBlock ? 'creates a block' : 'adds a week'}',
      () async {
        final result = await const WorkoutPresetInstaller().install(
          preset: _preset('HYP-FB-3'),
          userId: userId,
          maxSplits: 5,
        );
        final repo = TrainingBlockRepository(ownerId: () => userId);
        final block = repo.blocksForSplit(result.splitId).single;
        final plans = HiveService.getPlans(splitId: result.splitId);
        final plan = plans.first;
        final otherBefore =
            repo.progressForPlan(result.splitId, plans.last.id!)!.toJson();
        final service = WorkoutProgressionService(ownerId: () => userId);
        for (var number = 1; number <= 4; number++) {
          final progress = repo.progressForPlan(result.splitId, plan.id!)!;
          final week = HiveService.getTrainingWeekById(progress.activeWeekId)!;
          expect(week.number, number);
          final session = WorkoutSession(
            id: 'logged-$number',
            userId: userId,
            splitId: result.splitId,
            planId: plan.id,
            planName: plan.name,
            trainingWeekId: week.id,
            weekNumber: number,
            date: DateTime(2026),
            isCompleted: false,
            startedAt: DateTime(2026),
            durationSeconds: 300,
            exercises: [],
          );
          await HiveService.putSessionRaw(session);
          await service.complete(session.id!);
          expect(
            repo.progressForPlan(result.splitId, plan.id!)!.state,
            number == 4
                ? WorkoutProgressState.awaitingBoundary
                : WorkoutProgressState.ready,
          );
          expect(
            repo.weeksForBlock(result.splitId, block.id),
            hasLength(number == 4 ? 4 : number + 1),
          );
        }
        final boundary = repo.progressForPlan(result.splitId, plan.id!)!;
        if (createBlock) {
          final next = await service.createBoundary(
            planId: plan.id!,
            expectedRevision: boundary.revision,
            name: 'Block 2',
            weekCount: 4,
          );
          final week = repo.weeksForBlock(result.splitId, next.id).single;
          expect(week.number, 1);
          expect(
            repo.progressForPlan(result.splitId, plan.id!)!.activeWeekId,
            week.id,
          );
          expect(
            HiveService.getTrainingBlockById(block.id)!.plannedWeekCount,
            4,
          );
        } else {
          final next = await service.extendBoundary(
            planId: plan.id!,
            expectedRevision: boundary.revision,
          );
          expect(next.number, 5);
          expect(next.blockId, block.id);
          expect(
            repo.progressForPlan(result.splitId, plan.id!)!.activeWeekId,
            next.id,
          );
          expect(
            HiveService.getTrainingBlockById(block.id)!.plannedWeekCount,
            5,
          );
        }
        expect(
          repo.progressForPlan(result.splitId, plan.id!)!.state,
          WorkoutProgressState.ready,
        );
        expect(
          repo.progressForPlan(result.splitId, plans.last.id!)!.toJson(),
          otherBefore,
        );
      },
    );
  }

  test('an intentionally created empty split is preserved', () async {
    final now = DateTime(2026);
    final split = Split(
      id: 'custom',
      name: 'Travel',
      userId: userId,
      createdAt: now,
      updatedAt: now,
      dirty: false,
    );
    await HiveService.putSplitRaw(split);
    await HiveService.putSplitPreferenceRaw(
      SplitPreference(userId: userId, activeSplitId: split.id, dirty: false),
    );
    final result = await const WorkoutPresetInstaller().install(
      preset: _preset('STR-FB-3'),
      userId: userId,
      maxSplits: 5,
    );
    expect(result.reusedDefaultSplit, isFalse);
    expect(HiveService.getSplits().map((value) => value.name), [
      'Travel',
      'Full body strength',
    ]);
  });

  test(
    'five active splits block installation unless My Split is reusable',
    () async {
      final now = DateTime(2026);
      for (var index = 0; index < 5; index++) {
        await HiveService.putSplitRaw(
          Split(
            id: 'split-$index',
            name: 'Split $index',
            userId: userId,
            createdAt: now.add(Duration(days: index)),
          ),
        );
      }
      await HiveService.putSplitPreferenceRaw(
        SplitPreference(userId: userId, activeSplitId: 'split-0'),
      );
      await expectLater(
        const WorkoutPresetInstaller().install(
          preset: _preset('HYP-UL-4'),
          userId: userId,
          maxSplits: 5,
        ),
        throwsA(isA<StateError>()),
      );
      expect(HiveService.getSplits(), hasLength(5));
      expect(HiveService.getPlans(), isEmpty);
    },
  );

  test('duplicate install names receive a bounded suffix', () async {
    final now = DateTime(2026);
    for (final split in [
      Split(id: 'active', name: 'Travel', userId: userId, createdAt: now),
      Split(
        id: 'existing',
        name: 'Full body hypertrophy',
        userId: userId,
        createdAt: now.add(const Duration(days: 1)),
      ),
    ]) {
      await HiveService.putSplitRaw(split);
    }
    await HiveService.putSplitPreferenceRaw(
      SplitPreference(userId: userId, activeSplitId: 'active'),
    );
    final result = await const WorkoutPresetInstaller().install(
      preset: _preset('HYP-FB-3'),
      userId: userId,
      maxSplits: 5,
    );
    expect(result.splitName, 'Full body hypertroph (2)');
    expect(result.splitName.length, lessThanOrEqualTo(24));
  });

  for (final failureStage in PresetInstallStage.values) {
    test('rollback restores raw state after $failureStage failure', () async {
      final defaultId = await _seedDefault(userId);
      await TrainingBlockMigration().normalize(ownerId: userId);
      final originalBlock =
          HiveService.blocksForSplit(defaultId).single.toJson();
      final originalSplit = HiveService.getSplitById(defaultId)!;
      final originalPreference = HiveService.getSplitPreference(userId)!;
      final installer = WorkoutPresetInstaller(
        installHook: (stage) async {
          if (stage == failureStage) throw StateError('Injected failure');
        },
      );

      await expectLater(
        installer.install(
          preset: _preset('HYB-UL-4'),
          userId: userId,
          maxSplits: 5,
        ),
        throwsA(isA<StateError>()),
      );

      expect(HiveService.getPlans(), isEmpty);
      final restoredSplit = HiveService.getSplitById(defaultId)!;
      expect(restoredSplit.name, originalSplit.name);
      expect(restoredSplit.deletedAt, isNull);
      expect(restoredSplit.dirty, originalSplit.dirty);
      final restoredPreference = HiveService.getSplitPreference(userId)!;
      expect(
        restoredPreference.activeSplitId,
        originalPreference.activeSplitId,
      );
      expect(restoredPreference.dirty, originalPreference.dirty);
      expect(
        HiveService.blocksForSplit(defaultId).single.toJson(),
        originalBlock,
      );
    });
  }
}

WorkoutPreset _preset(String id) =>
    workoutPresets.firstWhere((preset) => preset.id == id);

Future<String> _seedDefault(String userId) async {
  final id = defaultSplitIdForUser(userId);
  final now = DateTime(2026);
  await HiveService.putSplitRaw(
    Split(
      id: id,
      name: 'My Split',
      userId: userId,
      createdAt: now,
      updatedAt: now,
      dirty: false,
    ),
  );
  await HiveService.putSplitPreferenceRaw(
    SplitPreference(
      userId: userId,
      activeSplitId: id,
      updatedAt: now,
      dirty: false,
    ),
  );
  return id;
}
