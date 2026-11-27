import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/theme/app_theme.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

/// History has no details page: a row opens the workout where it was logged,
/// at its own block and week, and Back comes back to History.
void main() {
  final harness = HiveTestHarness();

  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });
  setUp(() => harness.open(includeSplits: true));
  tearDownAll(() async {
    await harness.close();
    await Supabase.instance.dispose();
  });

  /// The logger writes from inside the test, and Hive's queue keeps that
  /// zone, so storage closes while the test can still pump frames.
  void historyTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        try {
          await body(tester);
        } finally {
          await closeStorageWithFrames(tester, harness.close);
        }
      });

  WorkoutSession log(
    String id, {
    required String planId,
    required String planName,
    required String weekId,
    required int week,
    required DateTime date,
    required String exercise,
  }) => WorkoutSession(
    id: id,
    planId: planId,
    planName: planName,
    splitId: 's',
    trainingWeekId: weekId,
    weekNumber: week,
    date: date,
    isCompleted: true,
    exercises: [
      Exercise(name: exercise, sets: [gym.Set(weight: 60, reps: 5)]),
    ],
  );

  /// One plan, Push, logged in Block 1 and in a second block, Strength; and a
  /// log whose plan has since been deleted.
  Future<void> seed() async {
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await HiveService.clearTrainingData();
    await HiveService.putSplitRaw(
      gym.Split(id: 's', name: 'Training', createdAt: DateTime(2026)),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: 'push',
        splitId: 's',
        name: 'Push',
        exercises: [ExerciseTemplate(name: 'Bench press', sets: 1)],
      ),
    );
    await TrainingBlockMigration().normalize(ownerId: null);
    final repository = TrainingBlockRepository(ownerId: () => null);
    final first = repository.blocksForSplit('s').first;
    final firstWeek = repository.weeksForBlock('s', first.id).first;
    final strength = await repository.createBlock(
      splitId: 's',
      name: 'Strength',
      weekCount: 1,
    );
    final strengthWeek = repository.weeksForBlock('s', strength.id).single;
    for (final session in [
      log(
        'block-one',
        planId: 'push',
        planName: 'Push',
        weekId: firstWeek.id,
        week: firstWeek.number,
        date: DateTime(2026, 9, 1),
        exercise: 'Incline press',
      ),
      log(
        'strength',
        planId: 'push',
        planName: 'Push',
        weekId: strengthWeek.id,
        week: strengthWeek.number,
        date: DateTime(2026, 9, 8),
        exercise: 'Front squat',
      ),
      log(
        'orphan',
        planId: 'deleted-plan',
        planName: 'Old plan',
        weekId: firstWeek.id,
        week: firstWeek.number,
        date: DateTime(2026, 8, 25),
        exercise: 'Deadlift',
      ),
    ]) {
      await HiveService.putSessionRaw(session);
    }
  }

  Future<WorkoutSessionProvider> pumpHistory(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.runAsync(seed);
    final sessions = WorkoutSessionProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>(
            create: (_) => WorkoutPlanProvider(),
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>.value(value: sessions),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
          home: const HistoryScreen(),
        ),
      ),
    );
    await pumpWithStorage(tester);
    return sessions;
  }

  Finder row(String day) =>
      find.ancestor(of: find.text(day), matching: find.byType(InkWell));

  historyTest(
    'a log opens in its plan at its own block and week, and Back returns',
    (tester) async {
      await pumpHistory(tester);
      final squat = ExerciseCatalog.label('Front squat', null);
      final incline = ExerciseCatalog.label('Incline press', null);
      // The ledger is names and figures, not exercise lists.
      expect(find.text(squat), findsNothing);
      expect(find.text(incline), findsNothing);

      // 8 September: the log in the second block.
      await tester.tap(row('8').first);
      await pumpWithStorage(tester);
      final workout = tester.widget<WorkoutScreen>(find.byType(WorkoutScreen));
      expect(workout.plan.id, 'push');
      expect(workout.destination?.sessionId, 'strength');
      expect(find.textContaining('Strength · Week'), findsOneWidget);
      expect(find.text(squat), findsOneWidget);
      expect(find.text(incline), findsNothing);
      expect(find.byType(HistoryScreen, skipOffstage: false), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await pumpWithStorage(tester);
      expect(find.byType(WorkoutScreen), findsNothing);
      expect(find.text('History'), findsOneWidget);

      // 1 September: the same plan, back in Block 1.
      await tester.tap(row('1').first);
      await pumpWithStorage(tester);
      expect(
        tester
            .widget<WorkoutScreen>(find.byType(WorkoutScreen))
            .destination
            ?.sessionId,
        'block-one',
      );
      expect(find.textContaining('Block 1 · Week'), findsOneWidget);
      expect(find.text(incline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  historyTest('a log whose plan is gone opens in the editor', (tester) async {
    await pumpHistory(tester);
    await tester.tap(row('25').first);
    await pumpWithStorage(tester);
    expect(find.byType(WorkoutScreen), findsNothing);
    expect(
      tester
          .widget<EditSessionScreen>(find.byType(EditSessionScreen))
          .session
          .id,
      'orphan',
    );
    expect(find.text(ExerciseCatalog.label('Deadlift', null)), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await pumpWithStorage(tester);
    expect(find.byType(EditSessionScreen), findsNothing);
    expect(find.text('History'), findsOneWidget);
  });

  historyTest('Delete workout in the logger removes the log and returns', (
    tester,
  ) async {
    final sessions = await pumpHistory(tester);
    await tester.tap(row('8').first);
    await pumpWithStorage(tester);

    await tester.tap(find.byTooltip('Workout actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit date and duration'), findsOneWidget);
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delete “Push” from 8 Sep 2026?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await pumpWithStorage(tester);

    expect(find.byType(WorkoutScreen), findsNothing);
    expect(find.text('History'), findsOneWidget);
    expect(HiveService.getSessionById('strength')?.deletedAt, isNotNull);
    expect(
      sessions.sessions.map((session) => session.id),
      unorderedEquals(['block-one', 'orphan']),
    );
    expect(row('8'), findsNothing);
  });
}
