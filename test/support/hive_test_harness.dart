import 'dart:io';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/utils/training_block_identity.dart';

class HiveTestHarness {
  Directory? _directory;

  Future<void> open({bool includeSplits = false}) async {
    _directory = await Directory.systemTemp.createTemp('opengym_test_');
    Hive.init(_directory!.path);
    _register(TrainingBlockAdapter());
    _register(TrainingWeekAdapter());
    _register(WorkoutProgressAdapter());
    await Hive.openBox<TrainingBlock>(HiveService.trainingBlocksBox);
    await Hive.openBox<TrainingWeek>(HiveService.trainingWeeksBox);
    await Hive.openBox<WorkoutProgress>(HiveService.workoutProgressBox);
    await Hive.openBox<dynamic>(HiveService.trainingOperationsBox);
    _register(SetAdapter());
    _register(SetTemplateAdapter());
    _register(ExerciseAdapter());
    _register(ExerciseTemplateAdapter());
    _register(WorkoutPlanAdapter());
    _register(WorkoutSessionAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
    if (includeSplits) {
      _register(SplitAdapter());
      _register(SplitPreferenceAdapter());
      await Hive.openBox<Split>(HiveService.splitsBox);
      await Hive.openBox<SplitPreference>(HiveService.splitPreferencesBox);
    }
  }

  /// Gives older widget fixtures explicit supplied structure before mounting
  /// the logger. This is fixture setup, never an application migration on open.
  Future<void> prepareTraining(
    List<WorkoutPlan> fixtures, {
    int weekCount = 2,
  }) async {
    _register(SplitAdapter());
    _register(SplitPreferenceAdapter());
    if (!Hive.isBoxOpen(HiveService.splitsBox)) {
      await Hive.openBox<Split>(HiveService.splitsBox);
    }
    if (!Hive.isBoxOpen(HiveService.splitPreferencesBox)) {
      await Hive.openBox<SplitPreference>(HiveService.splitPreferencesBox);
    }
    for (final plan in fixtures) {
      plan.id ??= const Uuid().v4();
      plan.splitId ??= 'test-split';
      await HiveService.putPlanRaw(plan.copyWith());
    }
    final plans = HiveService.getAllPlansRaw();
    for (final plan in plans) {
      plan.splitId ??= 'test-split';
      await HiveService.putPlanRaw(plan.copyWith());
      if (HiveService.getSplitById(plan.splitId!) == null) {
        await HiveService.putSplitRaw(
          Split(
            id: plan.splitId!,
            name: 'Training ${HiveService.getSplits().length}',
            createdAt: DateTime(2026),
            userId: plan.userId,
          ),
        );
      }
    }
    for (final session in HiveService.getAllSessionsRaw()) {
      final matches =
          plans
              .where(
                (p) =>
                    session.planId != null
                        ? p.id == session.planId
                        : p.name == session.planName,
              )
              .toList();
      final plan = matches.length == 1 ? matches.single : null;
      final splitId =
          session.splitId ??
          plan?.splitId ??
          fixtures.firstOrNull?.splitId ??
          'test-split';
      if (HiveService.getSplitById(splitId) == null) {
        await HiveService.putSplitRaw(
          Split(
            id: splitId,
            name: 'Training ${HiveService.getSplits().length}',
            createdAt: DateTime(2026),
          ),
        );
      }
      session.splitId = splitId;
      session.userId = HiveService.getSplitById(splitId)!.userId;
      await HiveService.putSessionRaw(
        session.copyWith(
          splitId: splitId,
          planId: session.planId ?? plan?.id,
          userId: HiveService.getSplitById(splitId)!.userId,
          trainingWeekId: legacyTrainingWeekId(splitId, session.weekNumber),
        ),
      );
    }
    await HiveService.clearTrainingData();
    for (final split in HiveService.getSplits()) {
      final block = TrainingBlock(
        id: legacyTrainingBlockId(split.id),
        splitId: split.id,
        name: 'Block 1',
        position: 0,
        createdAt: DateTime(2026),
        userId: split.userId,
      );
      await HiveService.putTrainingBlockRaw(block);
      final numbers = {
        for (var n = 1; n <= weekCount; n++) n,
        ...HiveService.getAllSessionsRaw()
            .where((s) => s.splitId == split.id)
            .map((s) => s.weekNumber),
      };
      for (final number in numbers) {
        await HiveService.putTrainingWeekRaw(
          TrainingWeek(
            id: legacyTrainingWeekId(split.id, number),
            splitId: split.id,
            blockId: block.id,
            number: number,
            createdAt: DateTime(2026),
            userId: split.userId,
          ),
        );
      }
    }
    final owners = HiveService.getAllSplitsRaw().map((s) => s.userId).toSet();
    if (owners.length != 1) {
      throw StateError('Widget fixtures require one cache owner.');
    }
    await TrainingBlockMigration().normalize(ownerId: owners.single);
  }

  void _register<T>(TypeAdapter<T> adapter) {
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }
  }

  Future<void> close() async {
    await Hive.close();
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
