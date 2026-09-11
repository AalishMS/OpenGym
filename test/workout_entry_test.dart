import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    hiveDirectory = await Directory.systemTemp.createTemp(
      'opengym_plan_editor_test_',
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

  testWidgets('workout keypad keeps history separate and autosaves on save', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 880);
    addTearDown(tester.view.reset);
    final plan = WorkoutPlan(
      id: 'plan-entry',
      name: 'Push',
      exercises: [ExerciseTemplate(name: 'Bench Press', sets: 2)],
    );
    await tester.runAsync(() async {
      await Hive.box<WorkoutPlan>(HiveService.plansBox).put(plan.id, plan);
      await Hive.box<WorkoutSession>(HiveService.sessionsBox).put(
        'previous',
        WorkoutSession(
          id: 'previous',
          planId: plan.id,
          planName: plan.name,
          date: DateTime(2026, 1, 1),
          weekNumber: 1,
          exercises: [
            Exercise(
              name: 'Bench Press',
              sets: [
                Set(weight: 80, reps: 8, rpe: 7, note: 'steady'),
                Set(weight: 75, reps: 10, rpe: 9),
              ],
            ),
          ],
        ),
      );
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
          ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
        ],
        child: MaterialApp(home: WorkoutScreen(plan: plan, planIndex: 0)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('80 × 8'), findsOneWidget);
    expect(find.text('75 × 10'), findsOneWidget);
    expect(find.text('steady'), findsNothing);
    expect(find.textContaining('TARGET'), findsNothing);
    expect(find.bySemanticsLabel('Set details'), findsNothing);
    expect(find.bySemanticsLabel('Delete set'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Set 1 Kg').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Set 1 RPE 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Set 1 Kg').last);
    await tester.pumpAndSettle();
    for (final key in ['5', '0', 'Next', '6', 'Next', '4', '5', 'Save']) {
      await tester.tap(find.text(key).last);
      await tester.pumpAndSettle();
    }
    final saved =
        HiveService.getSessionForPlanAndWeek('Push', 2, plan.splitId)!;
    expect(saved.exercises.single.sets[0].weight, 50);
    expect(saved.exercises.single.sets[0].reps, 6);
    expect(saved.exercises.single.sets[0].rpe, 8);
    expect(saved.exercises.single.sets[0].note, 'steady');
    expect(saved.exercises.single.sets[1].weight, 45);
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        1,
        plan.splitId,
      )!.exercises.single.sets[0].weight,
      80,
    );
    expect(find.text('80 × 8'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Add set'));
    await tester.pump();
    final duplicated =
        HiveService.getSessionForPlanAndWeek('Push', 2, plan.splitId)!;
    expect(duplicated.exercises.single.sets, hasLength(3));
    expect(duplicated.exercises.single.sets.last.weight, 45);
    expect(duplicated.exercises.single.sets.last.reps, 10);
    expect(duplicated.exercises.single.sets.last.rpe, 9);
    await tester.tap(find.bySemanticsLabel('Delete set').last);
    await tester.pumpAndSettle();
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        2,
        plan.splitId,
      )!.exercises.single.sets.length,
      2,
    );
    await tester.tap(find.bySemanticsLabel('Delete set').last);
    await tester.pumpAndSettle();
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        2,
        plan.splitId,
      )!.exercises.single.sets.length,
      1,
    );
    await tester.tap(find.bySemanticsLabel('Delete set'));
    await tester.pumpAndSettle();
    expect(find.text('No sets added yet'), findsOneWidget);
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        2,
        plan.splitId,
      )!.exercises.single.sets,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('workout add exercise opens the library picker and autosaves', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 880);
    addTearDown(tester.view.reset);
    final plan = WorkoutPlan(
      id: 'plan-library-picker',
      name: 'Library picker',
      exercises: [ExerciseTemplate(name: 'Bench Press', sets: 1)],
    );
    await tester.runAsync(() async {
      await Hive.box<WorkoutPlan>(HiveService.plansBox).put(plan.id, plan);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
          ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
        ],
        child: MaterialApp(home: WorkoutScreen(plan: plan, planIndex: 0)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Add exercises'), findsOneWidget);
    expect(find.text('Selected (0)'), findsOneWidget);
    expect(find.text('Create custom exercise'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'lat pulldown',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lat Pulldown'));
    await tester.pumpAndSettle();
    expect(find.text('Selected (1)'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    final saved = HiveService.getSessionForPlanAndWeek(
      plan.name,
      1,
      plan.splitId,
    );
    expect(saved, isNotNull);
    expect(
      saved!.exercises.map((exercise) => exercise.name),
      contains('Lat Pulldown'),
    );

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Selected (0)'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'lat pulldown',
    );
    await tester.pumpAndSettle();
    expect(find.text('Added'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
