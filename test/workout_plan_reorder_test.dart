import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/services/hive_service.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    hiveDirectory = await Directory.systemTemp.createTemp(
      'opengym_order_test_',
    );
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('reordered plans keep their order after reload', () async {
    final box = Hive.box<WorkoutPlan>(HiveService.plansBox);
    final plans = [
      WorkoutPlan(id: 'push', name: 'Push', exercises: []),
      WorkoutPlan(id: 'pull', name: 'Pull', exercises: []),
      WorkoutPlan(id: 'legs', name: 'Legs', exercises: []),
    ];
    for (final plan in plans) {
      await box.put(plan.id, plan);
    }

    final provider = WorkoutPlanProvider();
    final originalIds = provider.plans.map((plan) => plan.id).toList();
    expect(originalIds.toSet(), {'push', 'pull', 'legs'});
    final expectedIds = [originalIds[1], originalIds[2], originalIds[0]];

    final save = provider.reorderPlans(0, 2);
    expect(provider.plans.map((plan) => plan.id), expectedIds);
    expect(provider.plans.map((plan) => plan.position), [0, 1, 2]);
    await save;

    provider.loadPlans();
    expect(provider.plans.map((plan) => plan.id), expectedIds);
    expect(provider.plans.map((plan) => plan.position), [0, 1, 2]);
    expect(provider.plans.every((plan) => plan.dirty == true), isTrue);
    provider.dispose();
  });
}
