import 'dart:io';

import 'package:hive/hive.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';

class HiveTestHarness {
  Directory? _directory;

  Future<void> open({bool includeSplits = false}) async {
    _directory = await Directory.systemTemp.createTemp('opengym_test_');
    Hive.init(_directory!.path);
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
