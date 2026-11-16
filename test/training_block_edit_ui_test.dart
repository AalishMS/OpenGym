import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/training_block_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/training_block_dialogs.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

void main() {
  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
  });

  final now = DateTime(2026);
  TrainingBlock block({int? planned = 3}) => TrainingBlock(
    id: 'b',
    splitId: 's',
    name: 'Strength',
    position: 0,
    createdAt: now,
    plannedWeekCount: planned,
  );

  String weeksText(WidgetTester tester) =>
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(TextFormField).last,
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text;

  group('block dialogs', () {
    Future<void> open(
      WidgetTester tester,
      Future<void> Function(BuildContext) show,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => show(context),
                    child: const Text('Open'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('create starts at the default four weeks', (tester) async {
      (String, int)? saved;
      await open(
        tester,
        (c) => TrainingBlockDialogs.create(
          c,
          onSave: (name, count) async {
            saved = (name, count);
            return block();
          },
        ),
      );
      expect(kDefaultBlockWeeks, 4);
      expect(weeksText(tester), '4');
      await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(saved, ('Power', 4));
    });

    testWidgets('edit pre-fills, enforces the minimum and saves name + count', (
      tester,
    ) async {
      (String, int)? saved;
      await open(
        tester,
        (c) => TrainingBlockDialogs.edit(
          c,
          block(),
          currentWeekCount: 3,
          onSave: (name, count) async {
            saved = (name, count);
            return block();
          },
        ),
      );
      expect(find.text('Edit block'), findsOneWidget);
      expect(find.textContaining('add weeks but not remove'), findsOneWidget);
      expect(find.textContaining('logged workouts stay'), findsOneWidget);
      expect(weeksText(tester), '3');
      IconButton button(String tip) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tip),
          matching: find.byType(IconButton),
        ),
      );
      expect(button('Fewer weeks').onPressed, isNull);
      expect(button('More weeks').onPressed, isNotNull);

      await tester.enterText(find.bySemanticsLabel('Weeks'), '2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.textContaining('Weeks can only be added'), findsOneWidget);

      await tester.tap(find.byTooltip('More weeks'));
      await tester.pumpAndSettle();
      expect(weeksText(tester), '3');
      await tester.tap(find.byTooltip('More weeks'));
      await tester.pumpAndSettle();
      expect(weeksText(tester), '4');
      await tester.tap(find.byTooltip('Fewer weeks'));
      await tester.pumpAndSettle();
      expect(weeksText(tester), '3');
      await tester.tap(find.byTooltip('More weeks'));
      await tester.pumpAndSettle();
      await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, ('Power', 4));
    });

    testWidgets('edit says the block changed when its values are refused', (
      tester,
    ) async {
      await open(
        tester,
        (c) => TrainingBlockDialogs.edit(
          c,
          block(),
          currentWeekCount: 3,
          // What the repository does when a sync made the block longer than
          // the minimum this dialog opened with.
          onSave: (name, count) async => throw ArgumentError.value(count),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('This block changed. Close and open it again.'),
        findsOneWidget,
      );
      expect(find.text('Edit block'), findsOneWidget);
    });
  });

  group('plan editor', () {
    final storage = HiveTestHarness();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await storage.open(includeSplits: true);
      await HiveService.putSplitRaw(
        gym.Split(id: 's', name: 'Training', createdAt: now),
      );
      await TrainingBlockMigration().normalize(ownerId: null);
    });

    void editorTest(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          try {
            await body(tester);
          } finally {
            await closeStorageWithFrames(tester, storage.close);
          }
        });

    Future<void> pumpEditor(WidgetTester tester, {WorkoutPlan? plan}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 880);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => SplitProvider(userIdProvider: () => null),
            ),
            ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
            ChangeNotifierProvider(
              create:
                  (c) => TrainingBlockProvider(
                    splitProvider: c.read<SplitProvider>(),
                    ownerId: () => null,
                  ),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
            home:
                plan == null
                    ? const PlanEditorScreen.create()
                    : PlanEditorScreen.edit(plan),
          ),
        ),
      );
      await pumpWithStorage(tester);
    }

    Future<TrainingBlock> seed(
      WidgetTester tester,
      String name,
      int weeks,
    ) async {
      final created = await tester.runAsync(
        () => TrainingBlockRepository(
          ownerId: () => null,
        ).createBlock(splitId: 's', name: name, weekCount: weeks),
      );
      return created!;
    }

    editorTest(
      'create mode: make a block in the sheet, pick a later week, save the plan',
      (tester) async {
        await pumpEditor(tester);
        await tester.enterText(find.byType(TextField).first, 'Pull');
        await tester.tap(find.text('Add exercise'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chest'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bench Press'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        // From a category, Done first returns to the groups.
        if (find.text('Done').evaluate().isNotEmpty) {
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Starting week'));
        await tester.pumpAndSettle();
        expect(find.text('Training blocks'), findsNothing);
        expect(find.textContaining('shared by every workout'), findsOneWidget);

        await tester.tap(find.text('Create block'));
        await tester.pumpAndSettle();
        expect(weeksText(tester), '4');
        await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
        await tester.tap(find.text('Create'));
        await pumpWithStorage(tester);
        // The new block is selected at Week 1 and offers its planned weeks.
        expect(find.text('Week 4'), findsOneWidget);
        await tester.tap(find.text('Week 3'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this week'));
        await tester.pumpAndSettle();
        expect(find.text('Power · Week 3'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await pumpWithStorage(tester);
        final saved = HiveService.getPlans().single;
        final progress = HiveService.progressForPlan('s', saved.id!)!;
        final week = HiveService.getTrainingWeekById(progress.activeWeekId)!;
        expect(HiveService.getTrainingBlockById(week.blockId)!.name, 'Power');
        expect(week.number, 3);
        expect(progress.state, WorkoutProgressState.ready);
        expect(
          HiveService.readTrainingGraph(ownerId: null).validate,
          returnsNormally,
        );
      },
    );

    editorTest(
      'edit mode: shows the current block and week, extends it, stays clean',
      (tester) async {
        final strength = await seed(tester, 'Strength', 4);
        final plan = WorkoutPlan(
          id: 'p',
          splitId: 's',
          name: 'Push',
          exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
        );
        await tester.runAsync(() async {
          await HiveService.createPlan(
            plan,
            startingWeekId:
                HiveService.startingWeeksForBlock('s', strength.id)[1].id,
          );
        });
        await pumpEditor(tester, plan: HiveService.getPlanById('p'));
        expect(find.text('Training block'), findsOneWidget);
        expect(find.text('Strength · Week 2 of 4'), findsOneWidget);

        await tester.tap(find.text('Training block'));
        await tester.pumpAndSettle();
        expect(find.text('Training blocks'), findsOneWidget);
        expect(find.text('Current block'), findsOneWidget);
        expect(find.text('4 weeks'), findsOneWidget);
        expect(find.text('Use this week'), findsNothing);
        expect(find.text('Week 2'), findsNothing);
        await tester.tap(find.byTooltip('Edit Strength'));
        await tester.pumpAndSettle();
        expect(weeksText(tester), '4');
        await tester.tap(find.byTooltip('More weeks'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: find.byType(Dialog), matching: find.text('Save')),
        );
        await pumpWithStorage(tester);
        expect(find.text('5 weeks'), findsOneWidget);
        expect(
          HiveService.getTrainingBlockById(strength.id)!.plannedWeekCount,
          5,
        );

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Strength · Week 2 of 5'), findsOneWidget);
        // Block edits are saved already: leaving never asks to discard.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsNothing);
      },
    );

    editorTest(
      'home duplicate plan: make a block in the sheet, pick a week, copy into it',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 880);
        addTearDown(tester.view.reset);
        final original = WorkoutPlan(
          id: 'p',
          splitId: 's',
          name: 'Push',
          exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
        );
        await tester.runAsync(() => HiveService.createPlan(original));
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => SplitProvider(userIdProvider: () => null),
              ),
              ChangeNotifierProvider(
                create: (c) => WorkoutPlanProvider(c.read<SplitProvider>()),
              ),
              ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
              ChangeNotifierProvider(
                create:
                    (c) => TrainingBlockProvider(
                      splitProvider: c.read<SplitProvider>(),
                      ownerId: () => null,
                    ),
              ),
            ],
            child: MaterialApp(
              theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
              home: const HomeScreen(),
            ),
          ),
        );
        await pumpWithStorage(tester);
        await tester.tap(find.text('Manage'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Plan actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Duplicate plan'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Create block'));
        await tester.pumpAndSettle();
        await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
        await tester.tap(find.text('Create'));
        await pumpWithStorage(tester);
        expect(find.text('Week 4'), findsOneWidget);
        await tester.tap(find.text('Week 3'));
        await tester.pumpAndSettle();
        // Choosing the week starts the copy at once, behind a progress dialog.
        await tester.runAsync(() async {
          await tester.tap(find.text('Use this week'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await pumpWithStorage(tester);
        final copy = HiveService.getPlans(
          splitId: 's',
        ).singleWhere((p) => p.name == 'Push (Copy)');
        final progress = HiveService.progressForPlan('s', copy.id!)!;
        final week = HiveService.getTrainingWeekById(progress.activeWeekId)!;
        expect(HiveService.getTrainingBlockById(week.blockId)!.name, 'Power');
        expect(week.number, 3);
        expect(progress.state, WorkoutProgressState.ready);
        expect(
          HiveService.readTrainingGraph(ownerId: null).validate,
          returnsNormally,
        );
      },
    );

    editorTest('edit mode hides the block field without a split', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 880);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PlanEditorScreen.edit(
            WorkoutPlan(
              name: 'Loose',
              exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Training block'), findsNothing);
    });
  });
}
