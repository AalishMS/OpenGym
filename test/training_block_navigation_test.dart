import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym_set;
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/navigation/workout_destination.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/services/workout_progression_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:gymapp/widgets/workout/training_block_dialogs.dart';
import 'package:gymapp/widgets/workout/training_block_strip.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    double scale = 1,
    ValueChanged<String>? onAction,
    bool enabled = true,
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
                body: Text('Selected $selected'),
                bottomNavigationBar: TrainingBlockStrip(
                  blocks: structure,
                  weeksByBlock: slots,
                  selectedWeekId: selected,
                  onSelectWeek: (id) => setState(() => selected = id),
                  onSelectBlock:
                      (id) => setState(() => selected = slots[id]!.first.id),
                  onRenameBlock: (id) => onAction?.call('rename:$id'),
                  onReorderBlocks: () => onAction?.call('reorder'),
                  onCreateBlock: () => onAction?.call('create'),
                  onAddWeek: (id) => onAction?.call('add:$id'),
                  enabled: enabled,
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
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(attempts, 0);
      await tester.enterText(find.bySemanticsLabel('Block name'), ' Strength ');
      await tester.enterText(find.bySemanticsLabel('Weeks'), '53');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(attempts, 0);
      await tester.enterText(find.bySemanticsLabel('Weeks'), '4');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(values, [('Strength', 4), ('Strength', 4)]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('block name opens a menu with switches and management actions', (
    tester,
  ) async {
    await tester.pumpWidget(host(structure: blocks(2), slots: weeks(2, 3)));
    await tester.pumpAndSettle();
    expect(find.text('Block 2'), findsNothing);
    await tester.tap(find.text('Block 1'));
    await tester.pumpAndSettle();
    expect(find.text('Block 2'), findsOneWidget);
    expect(find.text('Create block'), findsOneWidget);
    expect(find.text('Rename block'), findsOneWidget);
    expect(find.text('Reorder blocks'), findsOneWidget);
    await tester.tap(find.text('Block 2'));
    await tester.pumpAndSettle();
    expect(find.text('Selected b1-w1'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-week-b0-w2')), findsNothing);
    expect(find.byKey(const ValueKey('training-week-b1-w2')), findsOneWidget);
  });

  testWidgets('short bar fills the width with Add week fixed to the right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(structure: blocks(1), slots: weeks(1, 1)));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TrainingBlockStrip)).width, 390);
    expect(
      tester.getRect(find.byTooltip('Add week')).right,
      greaterThanOrEqualTo(380),
    );
  });
  testWidgets('only weeks scroll and the menu opens above its block button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(structure: blocks(2), slots: weeks(2, 52)));
    await tester.pumpAndSettle();
    final blockRect = tester.getRect(find.text('Block 1'));
    final plusRect = tester.getRect(find.byTooltip('Add week'));
    final scroll = find.descendant(
      of: find.byType(TrainingBlockStrip),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(scroll, const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Block 1')), blockRect);
    expect(tester.getRect(find.byTooltip('Add week')), plusRect);
    await tester.tap(find.text('Block 1'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Reorder blocks')).bottom,
      lessThan(blockRect.top),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Rename block'), findsNothing);
    expect(find.text('Selected b0-w1'), findsOneWidget);
    await tester.tap(find.text('Block 1'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(380, 100));
    await tester.pumpAndSettle();
    expect(find.text('Rename block'), findsNothing);
  });

  testWidgets(
    'management and Add week use explicit callbacks; busy bar is disabled',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        host(structure: blocks(2), slots: weeks(2, 1), onAction: actions.add),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add week'));
      for (final label in ['Create block', 'Rename block', 'Reorder blocks']) {
        await tester.tap(find.text('Block 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(actions, ['add:b0', 'create', 'rename:b0', 'reorder']);
      await tester.pumpWidget(
        host(
          structure: blocks(1),
          slots: weeks(1, 1),
          onAction: actions.add,
          enabled: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add week'));
      await tester.tap(find.text('Block 1'));
      await tester.pumpAndSettle();
      expect(actions, hasLength(4));
      expect(find.text('Create block'), findsNothing);
    },
  );
  testWidgets('a single block cannot be reordered from the menu', (
    tester,
  ) async {
    final actions = <String>[];
    await tester.pumpWidget(
      host(structure: blocks(1), slots: weeks(1, 1), onAction: actions.add),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block 1'));
    await tester.pumpAndSettle();
    expect(find.text('Needs 2 blocks'), findsOneWidget);
    await tester.tap(find.text('Reorder blocks'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    expect(find.text('Reorder blocks'), findsOneWidget);
  });
  testWidgets(
    'entry reveals selected slot and constructs only its block weeks',
    (tester) async {
      await tester.pumpWidget(
        host(
          structure: blocks(100),
          slots: weeks(100, 52),
          selected: 'b99-w52',
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
  testWidgets(
    'many blocks keep the popup bounded and scrollable at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(structure: blocks(100), slots: weeks(100, 1), scale: 2.4),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block 1'));
      await tester.pumpAndSettle();
      final menu = find.byType(SingleChildScrollView).last;
      final rect = tester.getRect(menu);
      expect(rect.top, greaterThanOrEqualTo(8));
      expect(
        rect.bottom,
        lessThan(tester.getRect(find.text('Block 1').first).top),
      );
      await tester.drag(menu, const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(find.text('Reorder blocks').hitTestable(), findsOneWidget);
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
              destination:
                  exact == null ? null : WorkoutDestination.session(exact.id!),
            ),
          ),
        ),
      );
      await pumpWithStorage(tester);
    }

    locationTest(
      'Push reveals Week 2 while Pull shows only Week 1 after reopening',
      (tester) async {
        final weekId = await tester.runAsync(() async {
          final repo = TrainingBlockRepository(ownerId: () => null);
          final block = await repo.createBlock(
            splitId: 's',
            name: 'Build',
            weekCount: 4,
          );
          await HiveService.putPlanRaw(plan.copyWith(id: 'pull', name: 'Pull'));
          await TrainingBlockMigration().normalize(ownerId: null);
          final first = repo.weeksForBlock('s', block.id).single;
          await HiveService.putSessionRaw(
            WorkoutSession(
              id: 'push-done',
              splitId: 's',
              planId: 'p',
              planName: 'Push',
              trainingWeekId: first.id,
              date: now,
              isCompleted: false,
              startedAt: now,
              durationSeconds: 60,
              exercises: [],
            ),
          );
          await WorkoutProgressionService(
            ownerId: () => null,
          ).complete('push-done');
          return repo.weeksForBlock('s', block.id).last.id;
        });
        await open(tester);
        expect(find.byKey(ValueKey('training-week-$weekId')), findsOneWidget);
        expect(find.text('Build · Week 2'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        plan = HiveService.getPlanById('pull')!;
        await open(tester);
        expect(find.text('Build · Week 1'), findsOneWidget);
        expect(find.byKey(ValueKey('training-week-$weekId')), findsNothing);
        expect(HiveService.getAllSessionsRaw(), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    locationTest('holding a week tab deletes that week for this workout only', (
      tester,
    ) async {
      final ids = await tester.runAsync(() async {
        final repo = TrainingBlockRepository(ownerId: () => null);
        final block = await repo.createBlock(
          splitId: 's',
          name: 'Build',
          weekCount: 4,
        );
        await TrainingBlockMigration().normalize(ownerId: null);
        final first = repo.weeksForBlock('s', block.id).single;
        await HiveService.putSessionRaw(
          WorkoutSession(
            id: 'push-done',
            splitId: 's',
            planId: 'p',
            planName: 'Push',
            trainingWeekId: first.id,
            date: now,
            isCompleted: false,
            startedAt: now,
            durationSeconds: 60,
            exercises: [],
          ),
        );
        await WorkoutProgressionService(
          ownerId: () => null,
        ).complete('push-done');
        return [first.id, repo.weeksForBlock('s', block.id).last.id];
      });
      await open(tester);
      expect(find.text('Build · Week 2'), findsOneWidget);

      await tester.longPress(find.byKey(ValueKey('training-week-${ids![0]}')));
      await tester.pumpAndSettle();
      expect(find.text('Build'), findsWidgets);
      await tester.tap(find.text('Delete week'));
      await tester.pumpAndSettle();
      expect(find.text('Delete week?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await pumpWithStorage(tester);

      expect(HiveService.getSessionById('push-done')!.deletedAt, isNotNull);
      expect(find.byKey(ValueKey('training-week-${ids[0]}')), findsNothing);
      expect(find.text('Build · Week 2'), findsOneWidget);
      final progress = HiveService.progressForPlan('s', 'p')!;
      expect(progress.activeWeekId, ids[1]);
      expect(progress.availableWeekIds, [ids[1]]);
      // The shared week row stays for the split's other workouts.
      expect(HiveService.getTrainingWeekById(ids[0])!.deletedAt, isNull);

      await tester.longPress(find.byKey(ValueKey('training-week-${ids[1]}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete week'));
      await pumpWithStorage(tester);
      expect(find.text("You can't delete the only week."), findsOneWidget);
      expect(find.byKey(ValueKey('training-week-${ids[1]}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    locationTest(
      'block switching remembers reached weeks and cannot append while browsing',
      (tester) async {
        final ids = await tester.runAsync(() async {
          await TrainingBlockMigration().normalize(ownerId: null);
          final repo = TrainingBlockRepository(ownerId: () => null);
          final first = repo.blocksForSplit('s').single;
          final secondWeek = await repo.appendWeek('s', first.id);
          final other = await repo.createBlock(
            splitId: 's',
            name: 'Strength',
            weekCount: 3,
          );
          await repo.appendWeek('s', other.id);
          await repo.appendWeek('s', other.id);
          final p = HiveService.progressForPlan('s', 'p')!;
          await HiveService.putWorkoutProgressRaw(
            p.copyWith(
              availableWeekIds:
                  HiveService.getAllTrainingWeeksRaw()
                      .map((w) => w.id)
                      .toList(),
            ),
          );
          return [first.id, secondWeek.id, other.id];
        });
        await open(tester);
        final progress = HiveService.getAllWorkoutProgressRaw().single;
        await tester.tap(find.byKey(ValueKey('training-week-${ids![1]}')));
        await pumpWithStorage(tester);
        await tester.tap(find.text('Block 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Strength'));
        await pumpWithStorage(tester);
        expect(find.text('Strength · Week 1'), findsOneWidget);
        await tester.tap(find.text('Week 3'));
        await pumpWithStorage(tester);
        await tester.tap(find.text('Strength'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Block 1'));
        await pumpWithStorage(tester);
        expect(find.text('Block 1 · Week 2'), findsOneWidget);
        await tester.tap(find.text('Block 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Strength'));
        await pumpWithStorage(tester);
        expect(find.text('Strength · Week 3'), findsOneWidget);
        final add = find.byTooltip('Complete this block to add a week');
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(of: add, matching: find.byType(IconButton)),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Strength · Week 3'), findsOneWidget);
        final repo = TrainingBlockRepository(ownerId: () => null);
        expect(repo.weeksForBlock('s', ids[0]), hasLength(2));
        expect(repo.weeksForBlock('s', ids[2]), hasLength(3));
        expect(
          HiveService.getAllWorkoutProgressRaw().single.activeWeekId,
          progress.activeWeekId,
        );
        expect(HiveService.getAllSessionsRaw(), isEmpty);
      },
    );

    locationTest(
      'popup creates and selects a block, renames it, and reorders without losing its week',
      (tester) async {
        await open(tester);
        Future<void> choose(String blockName, String action) async {
          await tester.tap(find.text(blockName));
          await tester.pumpAndSettle();
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
        }

        await choose('Block 1', 'Create block');
        await tester.enterText(find.bySemanticsLabel('Block name'), 'Strength');
        await tester.enterText(find.bySemanticsLabel('Weeks'), '3');
        await tester.tap(find.text('Create'));
        await pumpWithStorage(tester);
        expect(find.text('Strength · Week 1'), findsOneWidget);
        await choose('Strength', 'Rename block');
        await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
        await tester.tap(find.text('Save'));
        await pumpWithStorage(tester);
        expect(find.text('Power · Week 1'), findsOneWidget);
        expect(find.text('Week 2'), findsNothing);
        await choose('Power', 'Reorder blocks');
        await tester.tap(find.byTooltip('Move Power up'));
        await tester.pump();
        await tester.tap(find.text('Save'));
        await pumpWithStorage(tester);
        expect(HiveService.blocksForSplit('s').first.name, 'Power');
        expect(find.text('Power · Week 1'), findsOneWidget);
        for (final action in [
          'Create block',
          'Rename block',
          'Reorder blocks',
        ]) {
          await choose('Power', action);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Power · Week 1'), findsOneWidget);
        }
        expect(HiveService.getAllTrainingBlocksRaw(), hasLength(2));
        expect(HiveService.getAllSessionsRaw(), isEmpty);
      },
    );

    locationTest(
      'failed save prevents switching blocks and future weeks stay disabled',
      (tester) async {
        await tester.runAsync(() async {
          await TrainingBlockMigration().normalize(ownerId: null);
          await TrainingBlockRepository(
            ownerId: () => null,
          ).createBlock(splitId: 's', name: 'Strength', weekCount: 1);
        });
        final failing = _FailingSessions();
        await open(tester, sessionProvider: failing);
        await tester.tap(find.text('Add set'));
        await pumpWithStorage(tester);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Block 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Strength'));
        await pumpWithStorage(tester);
        expect(find.text('Block 1 · Week 1'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        final attempts = failing.attempts;
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(
                  of: find.byTooltip('Complete this block to add a week'),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
        );
        await pumpWithStorage(tester);
        expect(find.text('Block 1 · Week 1'), findsOneWidget);
        expect(failing.attempts, attempts);
        expect(HiveService.getAllTrainingWeeksRaw(), hasLength(2));
      },
    );

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
        final week = await repo.appendWeek(
          's',
          repo.blocksForSplit('s').single.id,
        );
        final p = HiveService.progressForPlan('s', 'p')!;
        await HiveService.putWorkoutProgressRaw(
          p.copyWith(availableWeekIds: [p.activeWeekId, week.id]),
        );
        return week;
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
      'four-week block prompts only after Week 4; dismissal retains saved result',
      (tester) async {
        final service = WorkoutProgressionService(ownerId: () => null);
        Future<void> logWeek(int number) async {
          final progress = HiveService.progressForPlan('s', 'p')!;
          await HiveService.putSessionRaw(
            WorkoutSession(
              id: 'done-$number',
              splitId: 's',
              planId: 'p',
              planName: 'Push',
              trainingWeekId: progress.activeWeekId,
              weekNumber: number,
              date: now,
              isCompleted: false,
              startedAt: now,
              durationSeconds: 60,
              exercises: [],
            ),
          );
          await service.complete('done-$number');
        }

        await tester.runAsync(() async {
          await TrainingBlockRepository(
            ownerId: () => null,
          ).createBlock(splitId: 's', name: 'Block 1', weekCount: 4);
          await TrainingBlockMigration().normalize(ownerId: null);
          for (var number = 1; number <= 3; number++) {
            await logWeek(number);
          }
        });
        await open(tester);
        expect(find.text('Block 1 · Week 4'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => logWeek(4));
        await open(tester);
        expect(find.text('Choose next week'), findsWidgets);
        expect(find.text('Add week'), findsOneWidget);
        expect(find.text('Create block'), findsOneWidget);
        expect(
          find.text(
            'You finished Week 4 of Block 1. Choose where Push goes next.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(find.text('Choose next week'), findsOneWidget);
        expect(HiveService.getAllTrainingWeeksRaw(), hasLength(4));
        expect(HiveService.getAllSessionsRaw(), hasLength(4));
      },
    );
    locationTest('browsing an untouched supplied week never saves a preview', (
      tester,
    ) async {
      final week = await tester.runAsync(() async {
        await TrainingBlockMigration().normalize(ownerId: null);
        final repo = TrainingBlockRepository(ownerId: () => null);
        final week = await repo.appendWeek(
          's',
          repo.blocksForSplit('s').single.id,
        );
        final p = HiveService.progressForPlan('s', 'p')!;
        await HiveService.putWorkoutProgressRaw(
          p.copyWith(availableWeekIds: [p.activeWeekId, week.id]),
        );
        return week;
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

    locationTest(
      'exact timer permission does not follow browsing to another started draft',
      (tester) async {
        final rows = await tester.runAsync(() async {
          await TrainingBlockMigration().normalize(ownerId: null);
          final repo = TrainingBlockRepository(ownerId: () => null);
          final first =
              repo
                  .weeksForBlock('s', repo.blocksForSplit('s').single.id)
                  .single;
          final second = await repo.appendWeek('s', first.blockId);
          final exact = WorkoutSession(
            id: 'exact',
            splitId: 's',
            planId: 'p',
            planName: 'Push',
            date: now,
            trainingWeekId: first.id,
            exercises: [],
            isCompleted: false,
            startedAt: now,
          );
          await HiveService.putSessionRaw(exact);
          await HiveService.putSessionRaw(
            exact.copyWith(
              id: 'other-started',
              trainingWeekId: second.id,
              weekNumber: 2,
            ),
          );
          return (exact, second.id);
        });
        await open(tester, exact: rows!.$1);
        await tester.tap(find.byKey(ValueKey('training-week-${rows.$2}')));
        await pumpWithStorage(tester);
        final button = find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(TextButton),
        );
        expect(tester.widget<TextButton>(button).onPressed, isNull);
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
