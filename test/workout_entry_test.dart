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
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open();
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
    expect(find.bySemanticsLabel('Delete set'), findsNothing);
    expect(find.text('Add set'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    final addSetGap =
        tester.getTopLeft(find.text('Add set')).dy -
        tester.getBottomLeft(find.bySemanticsLabel('Set 2 Reps')).dy;
    await tester.tap(find.bySemanticsLabel('Set 1 Kg').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Add set')).dy -
          tester.getBottomLeft(find.bySemanticsLabel('Set 2 Reps')).dy,
      closeTo(addSetGap, .1),
      reason:
          'Opening the keypad must not insert blank space inside an exercise',
    );
    await tester.tap(find.text('RPE').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Set 1 Kg').last);
    await tester.pumpAndSettle();
    for (final key in ['5', '0', 'Next', '6', 'Next', '4', '5', 'Save']) {
      await tester.tap(find.text(key).last);
      await pumpWithStorage(tester);
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
    await pumpWithStorage(tester);
    final duplicated =
        HiveService.getSessionForPlanAndWeek('Push', 2, plan.splitId)!;
    expect(duplicated.exercises.single.sets, hasLength(3));
    expect(duplicated.exercises.single.sets.last.weight, 45);
    expect(duplicated.exercises.single.sets.last.reps, 10);
    expect(duplicated.exercises.single.sets.last.rpe, 9);
    await tester.ensureVisible(find.bySemanticsLabel('Set 2 Reps'));
    await tester.longPress(find.bySemanticsLabel('Set 2 Reps'));
    await tester.pumpAndSettle();
    expect(find.text('Delete set'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        2,
        plan.splitId,
      )!.exercises.single.sets,
      hasLength(3),
    );
    Future<void> deleteSet(int number) async {
      await tester.ensureVisible(find.bySemanticsLabel('Set $number Kg'));
      await tester.longPress(find.bySemanticsLabel('Set $number Kg'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('Delete set'));
      await pumpWithStorage(tester);
    }

    await deleteSet(3);
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        2,
        plan.splitId,
      )!.exercises.single.sets.length,
      2,
    );
    await deleteSet(2);
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        2,
        plan.splitId,
      )!.exercises.single.sets.single.weight,
      50,
    );
    expect(
      HiveService.getSessionForPlanAndWeek(
        'Push',
        2,
        plan.splitId,
      )!.exercises.single.sets.length,
      1,
    );
    await deleteSet(1);
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
    final sessions = _RecordingSessions();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
          ChangeNotifierProvider<WorkoutSessionProvider>.value(value: sessions),
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
    await tester.pump();
    expect(find.text('Selected (1)'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await pumpWithStorage(tester);
    final saved = sessions.saved;
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

class _RecordingSessions extends WorkoutSessionProvider {
  WorkoutSession? saved;

  @override
  Future<void> upsertSession(WorkoutSession session) async {
    saved = session;
  }
}
