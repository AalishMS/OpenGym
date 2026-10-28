import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym_set;
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';

import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/training_block_strip.dart';
import 'package:gymapp/widgets/workout/training_block_dialogs.dart';
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
  List<TrainingBlock> blocks(int count) => [
    for (var i = 0; i < count; i++)
      TrainingBlock(
        id: 'b$i',
        splitId: 's',
        name: 'Block ${i + 1}',
        position: i,
        createdAt: now,
      ),
  ];
  Map<String, List<TrainingWeek>> weeks(int count, int length) => {
    for (var b = 0; b < count; b++)
      'b$b': [
        for (var n = 1; n <= length; n++)
          TrainingWeek(
            id: 'b$b-w$n',
            splitId: 's',
            blockId: 'b$b',
            number: n,
            createdAt: now,
          ),
      ],
  };
  Widget host({
    required List<TrainingBlock> structure,
    required Map<String, List<TrainingWeek>> slots,
    String selected = 'b0-w1',
    String? expanded = 'b0',
    double scale = 1,
  }) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
      home: StatefulBuilder(
        builder:
            (context, setState) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Column(
                  children: [
                    Text('Selected $selected'),
                    TrainingBlockStrip(
                      blocks: structure,
                      weeksByBlock: slots,
                      selectedWeekId: selected,
                      expandedBlockId: expanded,
                      onSelectWeek: (id) => setState(() => selected = id),
                      onExpandBlock:
                          (id) => setState(
                            () => expanded = expanded == id ? null : id,
                          ),
                      onManageBlock: (_) {},
                      onCreateBlock: () {},
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  testWidgets(
    'create validates values and retries the same form after persistence failure',
    (tester) async {
      var attempts = 0;
      final values = <(String, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => TrainingBlockDialogs.create(
                          context,
                          onSave: (name, count) async {
                            values.add((name, count));
                            attempts++;
                            if (attempts == 1) throw StateError('disk');
                            return blocks(1).single;
                          },
                        ),
                    child: const Text('Create block'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Create block'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts, 0);
      await tester.enterText(find.bySemanticsLabel('Block name'), ' Strength ');
      await tester.enterText(find.bySemanticsLabel('Weeks'), '53');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts, 0);
      await tester.enterText(find.bySemanticsLabel('Weeks'), '4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(values, [('Strength', 4), ('Strength', 4)]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'weeks reveal inline; one expanded block and collapse preserves selection',
    (tester) async {
      await tester.pumpWidget(host(structure: blocks(2), slots: weeks(2, 3)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('training-week-b0-w2')), findsOneWidget);
      expect(find.byKey(const ValueKey('training-week-b1-w2')), findsNothing);
      await tester.tap(find.text('Block 2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('training-week-b0-w2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('training-week-b1-w2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block 2'));
      await tester.pumpAndSettle();
      expect(find.text('Selected b1-w2'), findsOneWidget);
      expect(find.byKey(const ValueKey('training-week-b1-w2')), findsNothing);
      expect(find.byTooltip('Block actions for Block 2'), findsOneWidget);
    },
  );
  testWidgets(
    'entry scrolls selected slot into view and constructs only expanded weeks',
    (tester) async {
      await tester.pumpWidget(
        host(
          structure: blocks(100),
          slots: weeks(100, 52),
          selected: 'b99-w52',
          expanded: 'b99',
        ),
      );
      await tester.pumpAndSettle();
      final selected = find.byKey(const ValueKey('training-week-b99-w52'));
      final rectangle = tester.getRect(selected);
      expect(rectangle.left, greaterThanOrEqualTo(0));
      expect(
        rectangle.right,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
      expect(find.byKey(const ValueKey('training-week-b98-w1')), findsNothing);
      expect(find.byType(TrainingBlockStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'narrow large-text long-name strip supports reduced motion without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          structure: [
            blocks(
              1,
            ).single.copyWith(name: 'A very long block name for strength work'),
          ],
          slots: weeks(1, 52),
          scale: 2.4,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  group('workout location', () {
    final storage = HiveTestHarness();
    late WorkoutPlan plan;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await storage.open(includeSplits: true);
      await HiveService.putSplitRaw(
        gym.Split(id: 's', name: 'Training', createdAt: now),
      );
      plan = WorkoutPlan(
        id: 'p',
        splitId: 's',
        name: 'Push',
        exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
      );
      await HiveService.putPlanRaw(plan);
    });
    void locationTest(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          try {
            await body(tester);
          } finally {
            await closeStorageWithFrames(tester, storage.close);
          }
        });
    Future<void> open(
      WidgetTester tester, {
      WorkoutSession? exact,
      WorkoutSessionProvider? sessionProvider,
    }) async {
      await tester.runAsync(
        () => TrainingBlockMigration().normalize(ownerId: null),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
            ChangeNotifierProvider<WorkoutSessionProvider>.value(
              value: sessionProvider ?? WorkoutSessionProvider(),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
            home: WorkoutScreen(
              plan: plan,
              planIndex: 0,
              initialSession: exact,
            ),
          ),
        ),
      );
      await pumpWithStorage(tester);
    }

    locationTest('opening an empty supplied slot never invents max plus one', (
      tester,
    ) async {
      await open(tester);
      expect(HiveService.getAllTrainingWeeksRaw(), hasLength(1));
      expect(find.text('Week 2'), findsNothing);
      expect(find.text('Block 1 · Week 1'), findsOneWidget);
      expect(HiveService.getAllSessionsRaw(), isEmpty);
    });
    locationTest('failed save prevents changing the selected week ID', (
      tester,
    ) async {
      final second = await tester.runAsync(() async {
        await TrainingBlockMigration().normalize(ownerId: null);
        final repo = TrainingBlockRepository(ownerId: () => null);
        return repo.appendWeek('s', repo.blocksForSplit('s').single.id);
      });
      final failing = _FailingSessions();
      await open(tester, sessionProvider: failing);
      await tester.tap(find.text('Add set'));
      await pumpWithStorage(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('training-week-${second!.id}')));
      await pumpWithStorage(tester);
      expect(find.text('Block 1 · Week 1'), findsOneWidget);
      expect(failing.attempts, greaterThanOrEqualTo(2));
    });
    locationTest(
      'boundary appears on ordinary entry; dismissal retains saved result and explicit action',
      (tester) async {
        await tester.runAsync(
          () => HiveService.putSessionRaw(
            WorkoutSession(
              id: 'done',
              splitId: 's',
              planId: 'p',
              planName: 'Push',
              date: now,
              exercises: [],
            ),
          ),
        );
        await open(tester);
        expect(find.text('Choose next week'), findsWidgets);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(find.text('Choose next week'), findsOneWidget);
        expect(HiveService.getAllTrainingWeeksRaw(), hasLength(1));
      },
    );
    locationTest('browsing an untouched supplied week never saves a preview', (
      tester,
    ) async {
      final week = await tester.runAsync(() async {
        await TrainingBlockMigration().normalize(ownerId: null);
        final repo = TrainingBlockRepository(ownerId: () => null);
        return repo.appendWeek('s', repo.blocksForSplit('s').single.id);
      });
      await open(tester);
      await tester.tap(find.byKey(ValueKey('training-week-${week!.id}')));
      await pumpWithStorage(tester);
      expect(find.text('Block 1 · Week 2'), findsOneWidget);
      expect(HiveService.getAllSessionsRaw(), isEmpty);
    });
    locationTest(
      'an extension arriving with the boundary sheet open is reused',
      (tester) async {
        await tester.runAsync(
          () => HiveService.putSessionRaw(
            WorkoutSession(
              id: 'done',
              splitId: 's',
              planId: 'p',
              planName: 'Push',
              date: now,
              exercises: [],
            ),
          ),
        );
        final sessions = WorkoutSessionProvider();
        await open(tester, sessionProvider: sessions);
        final week = await tester.runAsync(() async {
          final repo = TrainingBlockRepository(ownerId: () => null);
          return repo.appendWeek('s', repo.blocksForSplit('s').single.id);
        });
        sessions.loadSessions();
        await tester.pumpAndSettle();
        expect(find.text('Continue to Week 2'), findsOneWidget);
        await tester.tap(find.text('Continue to Week 2'));
        await pumpWithStorage(tester);
        expect(HiveService.getAllTrainingWeeksRaw(), hasLength(2));
        expect(HiveService.progressForPlan('s', 'p')!.activeWeekId, week!.id);
      },
    );
    locationTest('a reordered next block refreshes an open boundary choice', (
      tester,
    ) async {
      final ids = await tester.runAsync(() async {
        await HiveService.putSessionRaw(
          WorkoutSession(
            id: 'done',
            splitId: 's',
            planId: 'p',
            planName: 'Push',
            date: now,
            exercises: [],
          ),
        );
        await TrainingBlockMigration().normalize(ownerId: null);
        final repo = TrainingBlockRepository(ownerId: () => null);
        final first = repo.blocksForSplit('s').single.id;
        final a = await repo.createBlock(
          splitId: 's',
          name: 'Strength',
          weekCount: 1,
        );
        final b = await repo.createBlock(
          splitId: 's',
          name: 'Recovery',
          weekCount: 1,
        );
        return [first, a.id, b.id];
      });
      final sessions = WorkoutSessionProvider();
      await open(tester, sessionProvider: sessions);
      expect(find.text('Move to Strength'), findsOneWidget);
      await tester.runAsync(
        () => TrainingBlockRepository(
          ownerId: () => null,
        ).reorderBlocks('s', [ids![0], ids[2], ids[1]]),
      );
      sessions.loadSessions();
      await tester.pumpAndSettle();
      expect(find.text('Move to Recovery'), findsOneWidget);
      expect(find.text('Move to Strength'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(HiveService.progressForPlan('s', 'p')!.state, 'awaitingBoundary');
    });
    locationTest(
      'new plan shows its default start and allows a different block/week',
      (tester) async {
        await tester.runAsync(() async {
          await TrainingBlockMigration().normalize(ownerId: null);
          await TrainingBlockRepository(
            ownerId: () => null,
          ).createBlock(splitId: 's', name: 'Strength', weekCount: 3);
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => SplitProvider(userIdProvider: () => null),
              ),
              ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
            ],
            child: const MaterialApp(home: PlanEditorScreen.create()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Starting week'), findsOneWidget);
        expect(find.text('Block 1 · Week 1'), findsOneWidget);
        await tester.tap(find.text('Starting week'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Block 1').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Strength').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Week 1').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Week 3').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this week'));
        await tester.pumpAndSettle();
        expect(find.text('Strength · Week 3'), findsOneWidget);
      },
    );

    locationTest('exact duplicate remains selected after provider reload', (
      tester,
    ) async {
      final exact = WorkoutSession(
        id: 'older',
        splitId: 's',
        planId: 'p',
        planName: 'Push',
        date: now,
        exercises: [
          Exercise(name: 'Squat', sets: [gym_set.Set(reps: 7, weight: 40)]),
        ],
      );
      await tester.runAsync(() async {
        await HiveService.putSessionRaw(exact);
        await HiveService.putSessionRaw(
          exact.copyWith(
            id: 'newer',
            date: now.add(const Duration(days: 1)),
            exercises: [
              Exercise(
                name: 'Squat',
                sets: [gym_set.Set(reps: 12, weight: 60)],
              ),
            ],
          ),
        );
      });
      final sessions = WorkoutSessionProvider();
      await open(tester, exact: exact, sessionProvider: sessions);
      expect(
        tester
            .widget<ExerciseCard>(find.byType(ExerciseCard).first)
            .exercise
            .sets
            .single
            .reps,
        7,
      );
      sessions.loadSessions();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ExerciseCard>(find.byType(ExerciseCard).first)
            .exercise
            .sets
            .single
            .reps,
        7,
      );
    });
    locationTest(
      'exact completed-session entry does not prompt at a boundary',
      (tester) async {
        final exact = WorkoutSession(
          id: 'done',
          splitId: 's',
          planId: 'p',
          planName: 'Push',
          date: now,
          exercises: [],
        );
        await tester.runAsync(() => HiveService.putSessionRaw(exact));
        await open(tester, exact: exact);
        expect(find.text('Not now'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
      },
    );
  });
}

class _FailingSessions extends WorkoutSessionProvider {
  int attempts = 0;
  @override
  Future<void> upsertSession(WorkoutSession session) async {
    attempts++;
    throw StateError('disk');
  }
}
