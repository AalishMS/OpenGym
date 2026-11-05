import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_definition.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/screens/exercise_management_screen.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/exercise_picker_sheet.dart';

import 'support/hive_test_harness.dart';
import 'support/test_fonts.dart';

void main() {
  final storage = HiveTestHarness();
  const customId = '11111111-1111-4111-8111-111111111111';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadTestFonts();
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    await storage.open();
    await ExerciseCatalog.put(
      const ExerciseDefinition(id: customId, name: 'DB Press'),
    );
  });
  tearDown(storage.close);

  Widget host(Widget child) => MaterialApp(
    theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
    home: child,
  );

  Future<void> chooseMergeTarget(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Actions for DB Press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge into another exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Dumbbell Press');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dumbbell Press').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'merge requires confirmation, preserves sets, and updates analytics',
    (tester) async {
      final log = WorkoutSession(
        date: DateTime(2026),
        planName: 'Push',
        exercises: [
          Exercise(
            name: 'DB Press',
            exerciseId: customId,
            sets: [gym.Set(reps: 8, weight: 20)],
          ),
          Exercise(
            name: 'Dumbbell Press',
            exerciseId: 'builtin:dumbbell-press',
            sets: [gym.Set(reps: 8, weight: 25)],
          ),
        ],
      );
      const analytics = StatisticsAnalyticsService();
      expect(
        analytics.liftSummaries([log], ExerciseMetric.bestWeight),
        hasLength(2),
      );
      await tester.pumpWidget(
        host(const ExerciseManagementScreen(userId: null)),
      );
      await tester.pumpAndSettle();
      await chooseMergeTarget(tester);
      expect(find.text('Merge exercises?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(ExerciseCatalog.getById(customId)!.mergedIntoId, isNull);
      await chooseMergeTarget(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Merge'));
        await SyncService.instance.runExclusiveLocalMutation(() async {});
      });
      await tester.pumpAndSettle();
      expect(ExerciseCatalog.canonicalId(customId), 'builtin:dumbbell-press');
      expect(
        analytics.liftSummaries([log], ExerciseMetric.bestWeight),
        hasLength(1),
      );
      expect(log.exercises.map((e) => e.name), ['DB Press', 'Dumbbell Press']);
      expect(log.exercises.expand((e) => e.sets), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom rename retains identity and its old name as a search alias',
    (tester) async {
      await tester.pumpWidget(
        host(const ExerciseManagementScreen(userId: null)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions for DB Press'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'My dumbbell press');
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await SyncService.instance.runExclusiveLocalMutation(() async {});
      });
      await tester.pumpAndSettle();
      expect(ExerciseCatalog.getById(customId)!.name, 'My dumbbell press');
      expect(ExerciseCatalog.findByName('DB Press')!.id, customId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ambiguous abbreviations suggest movements without automatically combining them',
    (tester) async {
      // Use an unregistered abbreviation so the dialog offers a real choice.
      await tester.runAsync(ExerciseCatalog.clear);
      String? chosenId;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showExercisePickerSheet(
                          context,
                          selectedExerciseNames: [],
                          onAdd: (_) {},
                          onRemove: (_) {},
                          onAddIdentified: (_, id) => chosenId = id,
                        ),
                    child: const Text('Open picker'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Create custom exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'DB Press');
      await tester.pumpAndSettle();
      expect(find.text('Use an existing exercise?'), findsOneWidget);
      expect(find.text('Dumbbell Press'), findsOneWidget);
      expect(chosenId, isNull);
      await tester.tap(find.text('Dumbbell Press'));
      await tester.pumpAndSettle();
      expect(chosenId, 'builtin:dumbbell-press');
      expect(ExerciseCatalog.stored, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
