import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/data/exercise_library.dart';
import 'package:gymapp/data/workout_presets.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/workout_preset_installer.dart';
import 'package:gymapp/utils/split_identity.dart';

void main() {
  late Directory hiveDirectory;
  const userId = 'preset-user';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    hiveDirectory = await Directory.systemTemp.createTemp('opengym_presets_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    Hive.registerAdapter(SplitAdapter());
    Hive.registerAdapter(SplitPreferenceAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
    await Hive.openBox<Split>(HiveService.splitsBox);
    await Hive.openBox<SplitPreference>(HiveService.splitPreferencesBox);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
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
  });

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
