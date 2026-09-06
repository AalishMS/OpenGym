import 'package:uuid/uuid.dart';

import '../data/exercise_library.dart';
import '../data/plan_colors.dart';
import '../data/workout_presets.dart';
import '../models/split.dart';
import '../models/split_preference.dart';
import '../models/workout_plan.dart';
import '../utils/split_identity.dart';
import 'hive_service.dart';
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

    final result = await SyncService.instance.runExclusiveLocalMutation(() async {
      final activeSplits = HiveService.getSplits();
      final originalPreference = HiveService.getSplitPreference(userId);
      final preferenceSnapshot =
          originalPreference == null
              ? null
              : SplitPreference(
                userId: originalPreference.userId,
                activeSplitId: originalPreference.activeSplitId,
                updatedAt: originalPreference.updatedAt,
                dirty: originalPreference.dirty,
              );
      final activeId = HiveService.getActiveSplitId(userId);
      final activeSplit =
          activeId == null ? null : HiveService.getSplitById(activeId);
      final reusable = _isUntouchedDefault(activeSplit, userId);
      if (!reusable && activeSplits.length >= maxSplits) {
        throw StateError(
          'You can have at most $maxSplits splits. Delete one in Manage splits.',
        );
      }

      final now = DateTime.now();
      final splitId = reusable ? activeSplit!.id : _uuid.v4();
      final splitName = _uniqueName(
        preset.installName,
        activeSplits,
        exceptId: reusable ? splitId : null,
      );
      final originalSplit = reusable ? activeSplit!.copyWith() : null;
      final installedSplit =
          reusable
              ? activeSplit!.copyWith(
                name: splitName,
                userId: userId,
                updatedAt: now,
                dirty: true,
              )
              : Split(
                id: splitId,
                name: splitName,
                userId: userId,
                createdAt: now,
                updatedAt: now,
                dirty: true,
              );

      final planMap = <String, WorkoutPlan>{};
      for (var index = 0; index < preset.plans.length; index++) {
        final source = preset.plans[index];
        final id = _uuid.v4();
        planMap[id] = WorkoutPlan(
          id: id,
          userId: userId,
          splitId: splitId,
          updatedAt: now,
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
        await HiveService.putSplitRaw(installedSplit);
        await installHook?.call(PresetInstallStage.splitWritten);
        await HiveService.putSplitPreferenceRaw(
          SplitPreference(
            userId: userId,
            activeSplitId: splitId,
            updatedAt: now,
            dirty: true,
          ),
        );
        await installHook?.call(PresetInstallStage.preferenceWritten);
      } catch (error) {
        await HiveService.deletePlansRaw(planMap.keys);
        if (originalSplit == null) {
          await HiveService.deleteSplitRaw(splitId);
        } else {
          await HiveService.putSplitRaw(originalSplit);
        }
        if (preferenceSnapshot == null) {
          await HiveService.deleteSplitPreferenceRaw(userId);
        } else {
          await HiveService.putSplitPreferenceRaw(preferenceSnapshot);
        }
        rethrow;
      }

      return PresetInstallResult(
        splitId: splitId,
        splitName: splitName,
        reusedDefaultSplit: reusable,
      );
    });

    SyncService.instance.scheduleSync();
    return result;
  }

  bool _isUntouchedDefault(Split? split, String userId) {
    if (split == null ||
        split.id != defaultSplitIdForUser(userId) ||
        split.name != 'My Split') {
      return false;
    }
    return HiveService.getPlans(splitId: split.id).isEmpty &&
        HiveService.getSessions(splitId: split.id).isEmpty;
  }

  String _uniqueName(String requested, List<Split> splits, {String? exceptId}) {
    final existing = {
      for (final split in splits.where((split) => split.id != exceptId))
        split.name.toLowerCase(),
    };
    if (!existing.contains(requested.toLowerCase())) return requested;
    var suffix = 2;
    while (true) {
      final tail = ' ($suffix)';
      final keep = 24 - tail.length;
      final candidate =
          '${requested.substring(0, requested.length.clamp(0, keep))}$tail';
      if (!existing.contains(candidate.toLowerCase())) return candidate;
      suffix++;
    }
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
