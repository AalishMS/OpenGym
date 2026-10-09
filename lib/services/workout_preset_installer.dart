import 'package:uuid/uuid.dart';

import '../data/exercise_library.dart';
import '../data/plan_colors.dart';
import '../data/workout_presets.dart';
import '../models/workout_plan.dart';
import 'hive_service.dart';
import 'split_install_target.dart';
import 'sync_service.dart';

enum PresetInstallStage { plansWritten, splitWritten, preferenceWritten }

typedef PresetInstallHook = Future<void> Function(PresetInstallStage stage);

class PresetInstallResult {
  final String splitId;
  final String splitName;
  final bool reusedDefaultSplit;

  const PresetInstallResult({
    required this.splitId,
    required this.splitName,
    required this.reusedDefaultSplit,
  });
}

class WorkoutPresetInstaller {
  static const Uuid _uuid = Uuid();

  final PresetInstallHook? installHook;

  const WorkoutPresetInstaller({this.installHook});

  Future<PresetInstallResult> install({
    required WorkoutPreset preset,
    required String userId,
    required int maxSplits,
  }) async {
    _validate(preset);

    final result = await SyncService.instance.runExclusiveLocalMutation(
      () async {
        final target = SplitInstallTarget.prepare(
          requestedName: preset.installName,
          userId: userId,
          maxSplits: maxSplits,
          now: DateTime.now(),
        );
        final splitId = target.splitId;

        final planMap = <String, WorkoutPlan>{};
        for (var index = 0; index < preset.plans.length; index++) {
          final source = preset.plans[index];
          final id = _uuid.v4();
          planMap[id] = WorkoutPlan(
            id: id,
            userId: userId,
            splitId: splitId,
            updatedAt: target.now,
            dirty: true,
            name: source.name,
            position: index,
            planColor: kPlanColors[source.colorSlot],
            exercises: [
              for (final exercise in source.exercises) exercise.toTemplate(),
            ],
          );
        }

        try {
          await HiveService.putPlansRaw(planMap);
          await installHook?.call(PresetInstallStage.plansWritten);
          await target.writeSplit();
          await installHook?.call(PresetInstallStage.splitWritten);
          await target.writePreference();
          await installHook?.call(PresetInstallStage.preferenceWritten);
        } catch (error) {
          await HiveService.deletePlansRaw(planMap.keys);
          await target.rollback();
          rethrow;
        }

        return PresetInstallResult(
          splitId: splitId,
          splitName: target.splitName,
          reusedDefaultSplit: target.reusedDefaultSplit,
        );
      },
    );

    SyncService.instance.scheduleSync();
    return result;
  }

  void _validate(WorkoutPreset preset) {
    if (preset.id.isEmpty ||
        preset.version < 1 ||
        preset.installName.isEmpty ||
        preset.installName.length > 24 ||
        preset.scheduleSlots.isEmpty ||
        preset.plans.isEmpty) {
      throw const FormatException('Preset metadata is incomplete.');
    }
    final library = ExerciseLibrary.allExercises.toSet();
    for (var index = 0; index < preset.plans.length; index++) {
      final plan = preset.plans[index];
      if (plan.name.isEmpty ||
          plan.colorSlot < 0 ||
          plan.colorSlot >= kPlanColors.length ||
          plan.exercises.isEmpty) {
        throw FormatException('Preset plan $index is invalid.');
      }
      for (final exercise in plan.exercises) {
        final straightSetCount = RegExp(
          r'^(\d+)\s*x',
        ).firstMatch(exercise.prescription);
        final countMatches =
            exercise.prescription.contains('+') ||
            straightSetCount == null ||
            int.parse(straightSetCount.group(1)!) == exercise.seedReps.length;
        if (!library.contains(exercise.name) ||
            exercise.seedReps.isEmpty ||
            exercise.seedReps.any((reps) => reps <= 0) ||
            exercise.rir.isEmpty ||
            exercise.rest.isEmpty ||
            !countMatches) {
          throw FormatException('Preset exercise ${exercise.name} is invalid.');
        }
      }
    }
    for (final planIndex in preset.scheduleSlots.whereType<int>()) {
      if (planIndex < 0 || planIndex >= preset.plans.length) {
        throw const FormatException('Preset schedule is invalid.');
      }
    }
  }
}
