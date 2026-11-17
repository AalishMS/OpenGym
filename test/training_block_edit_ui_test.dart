import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
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
import 'package:gymapp/services/sync_service.dart';
import 'package:gymapp/services/training_block_lifecycle.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:gymapp/widgets/workout/training_block_actions.dart';
import 'package:gymapp/widgets/workout/training_block_dialogs.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

/// Block forms are bottom sheets that scroll on the 800×600 test screen, so a
/// control near the bottom (Delete block) is scrolled into view before the tap.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

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
      (String, int?)? saved;
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

    testWidgets('a save that left the weeks alone sends no length, even '
        'after stepping away and back', (tester) async {
      final saved = <(String, int?)>[];
      await open(
        tester,
        (c) => TrainingBlockDialogs.edit(
          c,
          block(),
          currentWeekCount: 3,
          onSave: (name, count) async {
            saved.add((name, count));
            return block();
          },
        ),
      );
      await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, [('Power', null)]);

      saved.clear();
      await open(
        tester,
        (c) => TrainingBlockDialogs.edit(
          c,
          block(),
          currentWeekCount: 3,
          onSave: (name, count) async {
            saved.add((name, count));
            return block();
          },
        ),
      );
      await tester.tap(find.byTooltip('More weeks'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fewer weeks'));
      await tester.pumpAndSettle();
      expect(weeksText(tester), '3');
      await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, [('Power', null)]);
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

    group('shorten and delete', () {
      IconButton stepper(WidgetTester tester, String tip) =>
          tester.widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(tip),
              matching: find.byType(IconButton),
            ),
          );
      ButtonStyleButton deleteButton(WidgetTester tester) =>
          tester.widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text('Delete block'),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          );

      Future<TrainingBlockEditResult? Function()> openEdit(
        WidgetTester tester, {
        int current = 4,
        int? minimum,
        Future<void> Function()? onDelete,
        String? reason,
        Future<TrainingBlock> Function(String, int?)? onSave,
        List<(String, int?)>? saved,
      }) async {
        TrainingBlockEditResult? result;
        var finished = false;
        await open(tester, (c) async {
          result = await TrainingBlockDialogs.edit(
            c,
            block(planned: current),
            currentWeekCount: current,
            minimumWeekCount: minimum,
            onDelete: onDelete,
            deleteUnavailableReason: reason,
            onSave:
                onSave ??
                (name, count) async {
                  saved?.add((name, count));
                  return block(planned: count);
                },
          );
          finished = true;
        });
        return () {
          expect(finished, isTrue);
          return result;
        };
      }

      testWidgets('a lower minimum lets the block shrink to it and saves', (
        tester,
      ) async {
        final saved = <(String, int?)>[];
        final result = await openEdit(
          tester,
          minimum: 2,
          onDelete: () async {},
          saved: saved,
        );
        expect(
          find.text(
            'Remove planned weeks no workout has reached, or add more. '
            'Logged workouts stay in this block.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('add weeks but not remove'), findsNothing);
        expect(stepper(tester, 'Fewer weeks').onPressed, isNotNull);

        await tester.enterText(find.bySemanticsLabel('Weeks'), '1');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved, isEmpty);
        expect(find.text('Choose 2–52 weeks.'), findsOneWidget);

        // Stepping from the invalid 1 lands on the floor.
        await tester.tap(find.byTooltip('More weeks'));
        await tester.pumpAndSettle();
        expect(weeksText(tester), '2');
        await tester.tap(find.byTooltip('More weeks'));
        await tester.pumpAndSettle();
        expect(weeksText(tester), '3');
        await tester.tap(find.byTooltip('Fewer weeks'));
        await tester.pumpAndSettle();
        expect(weeksText(tester), '2');
        expect(stepper(tester, 'Fewer weeks').onPressed, isNull);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved, [('Strength', 2)]);
        final r = result();
        expect(r, isA<TrainingBlockSaved>());
        expect((r! as TrainingBlockSaved).block.plannedWeekCount, 2);
      });

      testWidgets('every week reached: minus is off and says why', (
        tester,
      ) async {
        await openEdit(tester, minimum: 4, onDelete: () async {});
        expect(stepper(tester, 'Fewer weeks').onPressed, isNull);
        expect(stepper(tester, 'More weeks').onPressed, isNotNull);
        expect(
          find.text(
            'Every week here has been reached, so this block can\'t be '
            'shorter.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('add weeks but not remove'), findsNothing);
      });

      testWidgets('without lifecycle support it is grow-only with no delete', (
        tester,
      ) async {
        await openEdit(tester, minimum: 4);
        expect(find.textContaining('add weeks but not remove'), findsOneWidget);
        expect(find.textContaining('has been reached'), findsNothing);
        expect(find.text('Delete block'), findsNothing);
        expect(stepper(tester, 'Fewer weeks').onPressed, isNull);
      });

      testWidgets('a block past the cap keeps its length and cannot grow', (
        tester,
      ) async {
        await openEdit(tester, current: 60, minimum: 55, onDelete: () async {});
        expect(weeksText(tester), '60');
        expect(stepper(tester, 'More weeks').onPressed, isNull);
        expect(stepper(tester, 'Fewer weeks').onPressed, isNotNull);
        await tester.enterText(find.bySemanticsLabel('Weeks'), '61');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Choose 55–60 weeks.'), findsOneWidget);
      });

      for (final entry
          in {
            BlockDeletionBlocker.lastBlock: 'A split keeps at least one block.',
            BlockDeletionBlocker.hasWorkouts:
                'This block has workouts in it, so it can\'t be deleted.',
            BlockDeletionBlocker.workoutInBlock:
                'A workout is in this block right now. Move it to another block '
                'first.',
          }.entries) {
        testWidgets('Delete block is disabled for ${entry.key.name}', (
          tester,
        ) async {
          var deletes = 0;
          await openEdit(
            tester,
            minimum: 4,
            onDelete: () async => deletes++,
            reason: TrainingBlockDialogs.blockerMessage(entry.key),
          );
          expect(find.text(entry.value), findsOneWidget);
          expect(deleteButton(tester).onPressed, isNull);
          await tester.tap(find.text('Delete block'), warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.textContaining('Delete Strength?'), findsNothing);
          expect(deletes, 0);
        });
      }

      testWidgets('confirming deletes and reports it; cancelling does not', (
        tester,
      ) async {
        var deletes = 0;
        final result = await openEdit(
          tester,
          minimum: 4,
          onDelete: () async => deletes++,
        );
        expect(deleteButton(tester).onPressed, isNotNull);
        await tapVisible(tester, find.text('Delete block'));
        await tester.pumpAndSettle();
        expect(find.text('Delete Strength?'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(deletes, 0);
        expect(find.text('Edit block'), findsOneWidget);

        await tapVisible(tester, find.text('Delete block'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Delete'),
          ),
        );
        await tester.pumpAndSettle();
        expect(deletes, 1);
        expect(find.text('Edit block'), findsNothing);
        final r = result();
        expect(r, isA<TrainingBlockDeleted>());
        expect((r! as TrainingBlockDeleted).name, 'Strength');
      });

      testWidgets('cancelling the form closes with no result', (tester) async {
        final result = await openEdit(
          tester,
          minimum: 4,
          onDelete: () async {},
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(result(), isNull);
      });

      for (final entry in <(String, Object, String)>[
        (
          'inUse',
          const TrainingBlockDeletionException(
            TrainingBlockDeletionReason.inUse,
          ),
          'This block is in use on another device.',
        ),
        (
          'lastBlock',
          const TrainingBlockDeletionException(
            TrainingBlockDeletionReason.lastBlock,
          ),
          'A split keeps at least one block.',
        ),
        (
          'updateRequired',
          const TrainingBlockDeletionException(
            TrainingBlockDeletionReason.updateRequired,
          ),
          'Update OpenGym to delete blocks.',
        ),
        (
          'unavailable',
          const TrainingBlockDeletionException(
            TrainingBlockDeletionReason.unavailable,
          ),
          'This block is no longer available.',
        ),
        (
          'splitDeleted',
          const TrainingBlockDeletionException(
            TrainingBlockDeletionReason.splitDeleted,
          ),
          'This block is no longer available.',
        ),
        (
          'local blocker',
          const TrainingBlockDeletionException(
            TrainingBlockDeletionReason.inUse,
            blocker: BlockDeletionBlocker.hasWorkouts,
          ),
          'This block has workouts in it, so it can\'t be deleted.',
        ),
        (
          'a network failure',
          StateError('socket'),
          'Could not delete. Check your connection and try again.',
        ),
      ]) {
        testWidgets('failure ${entry.$1} shows its message and stays open', (
          tester,
        ) async {
          var attempts = 0;
          await openEdit(
            tester,
            minimum: 4,
            onDelete: () async {
              attempts++;
              throw entry.$2;
            },
          );
          for (var i = 1; i <= 2; i++) {
            await tapVisible(tester, find.text('Delete block'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('Delete'),
              ),
            );
            await tester.pumpAndSettle();
            expect(attempts, i);
            expect(find.text(entry.$3), findsOneWidget);
            expect(find.text('Edit block'), findsOneWidget);
            // Nothing is left disabled by the failed attempt.
            expect(deleteButton(tester).onPressed, isNotNull);
          }
        });
      }

      testWidgets('while deleting, everything is disabled and it runs once', (
        tester,
      ) async {
        final gate = Completer<void>();
        var deletes = 0;
        final result = await openEdit(
          tester,
          minimum: 2,
          onDelete: () {
            deletes++;
            return gate.future;
          },
        );
        await tapVisible(tester, find.text('Delete block'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Delete'),
          ),
        );
        // Let the confirmation close; the delete itself is still pending.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(deleteButton(tester).onPressed, isNull);
        expect(stepper(tester, 'Fewer weeks').onPressed, isNull);
        expect(stepper(tester, 'More weeks').onPressed, isNull);
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.ancestor(
                  of: find.text('Cancel'),
                  matching: find.bySubtype<ButtonStyleButton>(),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Save'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Delete block'), warnIfMissed: false);
        await tester.pump();
        expect(deletes, 1);
        gate.complete();
        await tester.pumpAndSettle();
        expect(result(), isA<TrainingBlockDeleted>());
      });
    });
  });

  group('block sheet', () {
    late List<TrainingBlock> stored;
    var lifecycleOn = true;
    final minimums = <String, int>{};
    final blockers = <String, BlockDeletionBlocker>{};
    final deleted = <String>[];

    TrainingBlock make(String id, String name, int weeks, int position) =>
        TrainingBlock(
          id: id,
          splitId: 's',
          name: name,
          position: position,
          createdAt: now,
          plannedWeekCount: weeks,
        );
    String week(String block, int n) => lazyTrainingWeekId('s', block, n);

    setUp(() {
      stored = [make('a', 'Base', 3, 0), make('b', 'Peak', 4, 1)];
      lifecycleOn = true;
      minimums.clear();
      blockers.clear();
      deleted.clear();
    });

    TrainingBlockSnapshot load() => (
      blocks: List.of(stored),
      weeksByBlock: {for (final b in stored) b.id: <TrainingWeek>[]},
    );

    TrainingBlockLifecycle lifecycle() => TrainingBlockLifecycle(
      available: () => lifecycleOn,
      minimumWeekCount: (b) => minimums[b.id],
      deleteBlocker: (b) => blockers[b.id],
      delete: (b) async {
        deleted.add(b.id);
        stored.removeWhere((x) => x.id == b.id);
      },
    );

    Future<TrainingBlock> edit(TrainingBlock b, String name, int? count) async {
      final updated = b.copyWith(name: name, plannedWeekCount: count);
      stored[stored.indexWhere((x) => x.id == b.id)] = updated;
      return updated;
    }

    Future<void> openSheet(
      WidgetTester tester, {
      String? selected,
      bool picking = true,
      void Function(String?)? onChosen,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      if (picking) {
                        onChosen?.call(
                          await TrainingBlockDialogs.startingWeek(
                            context,
                            blocks: load().blocks,
                            weeksByBlock: load().weeksByBlock,
                            selectedWeekId: selected,
                            load: load,
                            onCreateBlock:
                                (_, _) async => throw StateError('x'),
                            onEditBlock: edit,
                            lifecycle: lifecycle(),
                          ),
                        );
                      } else {
                        await TrainingBlockDialogs.manage(
                          context,
                          load: load,
                          onCreateBlock: (_, _) async => throw StateError('x'),
                          onEditBlock: edit,
                          lifecycle: lifecycle(),
                        );
                      }
                    },
                    child: const Text('Open'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> confirmDelete(WidgetTester tester) async {
      await tapVisible(tester, find.text('Delete block'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('deleting the block holding the selection selects the first '
        'remaining block\'s first week', (tester) async {
      String? chosen;
      await openSheet(
        tester,
        selected: week('b', 4),
        onChosen: (c) => chosen = c,
      );
      await tester.tap(find.byTooltip('Edit Peak'));
      await tester.pumpAndSettle();
      await confirmDelete(tester);
      expect(deleted, ['b']);
      expect(find.text('Peak deleted'), findsOneWidget);
      expect(find.text('Peak'), findsNothing);
      expect(find.text('Edit block'), findsNothing);
      // Base opened with its weeks, and nothing points at the deleted block.
      expect(find.text('Week 3'), findsOneWidget);
      expect(find.text('Week 4'), findsNothing);
      await tester.tap(find.text('Use this week'));
      await tester.pumpAndSettle();
      expect(chosen, week('a', 1));
    });

    testWidgets('deleting another block leaves the selection alone', (
      tester,
    ) async {
      String? chosen;
      await openSheet(
        tester,
        selected: week('b', 3),
        onChosen: (c) => chosen = c,
      );
      await tester.tap(find.byTooltip('Edit Base'));
      await tester.pumpAndSettle();
      await confirmDelete(tester);
      expect(find.text('Base deleted'), findsOneWidget);
      await tester.tap(find.text('Use this week'));
      await tester.pumpAndSettle();
      expect(chosen, week('b', 3));
    });

    testWidgets(
      'shortening past the selected week selects the last week left',
      (tester) async {
        String? chosen;
        minimums['b'] = 2;
        await openSheet(
          tester,
          selected: week('b', 4),
          onChosen: (c) => chosen = c,
        );
        expect(find.text('Week 4'), findsOneWidget);
        await tester.tap(find.byTooltip('Edit Peak'));
        await tester.pumpAndSettle();
        await tester.enterText(find.bySemanticsLabel('Weeks'), '2');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('2 weeks'), findsOneWidget);
        expect(find.text('Week 3'), findsNothing);
        expect(find.text('Week 4'), findsNothing);
        await tester.tap(find.text('Use this week'));
        await tester.pumpAndSettle();
        expect(chosen, week('b', 2));
      },
    );

    testWidgets('a stale starting week opens on a week that exists', (
      tester,
    ) async {
      String? chosen;
      await openSheet(tester, selected: 'gone', onChosen: (c) => chosen = c);
      await tester.tap(find.text('Use this week'));
      await tester.pumpAndSettle();
      expect(chosen, week('a', 1));
    });

    testWidgets('managing: delete shows the confirmation and refreshes', (
      tester,
    ) async {
      await openSheet(tester, picking: false);
      expect(
        find.text('Rename a block, change its length, or delete it.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Edit Base'));
      await tester.pumpAndSettle();
      await confirmDelete(tester);
      expect(deleted, ['a']);
      expect(find.text('Base deleted'), findsOneWidget);
      expect(find.byTooltip('Edit Base'), findsNothing);
      expect(find.byTooltip('Edit Peak'), findsOneWidget);
    });

    testWidgets('a blocked block shows Delete block disabled with its reason', (
      tester,
    ) async {
      blockers['a'] = BlockDeletionBlocker.hasWorkouts;
      await openSheet(tester, picking: false);
      await tester.tap(find.byTooltip('Edit Base'));
      await tester.pumpAndSettle();
      expect(
        find.text('This block has workouts in it, so it can\'t be deleted.'),
        findsOneWidget,
      );
      expect(find.text('Delete block'), findsOneWidget);
    });

    testWidgets('without lifecycle support the sheet is grow-only', (
      tester,
    ) async {
      lifecycleOn = false;
      minimums['a'] = 1;
      await openSheet(tester, picking: false);
      expect(
        find.text(
          'Add weeks or rename a block. Weeks can be added but not removed.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Edit Base'));
      await tester.pumpAndSettle();
      expect(find.textContaining('add weeks but not remove'), findsOneWidget);
      expect(find.text('Delete block'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Fewer weeks'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
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

    for (final other in [4, 8]) {
      editorTest(
        'a rename saved after a sync resized the block to $other keeps the '
        'length the other device set',
        (tester) async {
          final strength = await seed(tester, 'Strength', 6);
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
          await tester.tap(find.text('Training block'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Edit Strength'));
          await tester.pumpAndSettle();
          expect(weeksText(tester), '6');
          // A sync brings another device's length while the dialog is open.
          await tester.runAsync(
            () => TrainingBlockRepository(ownerId: () => null).updateBlock(
              splitId: 's',
              blockId: strength.id,
              name: 'Strength',
              weekCount: other,
            ),
          );
          final resized = HiveService.getTrainingBlockById(strength.id)!;
          expect(resized.plannedWeekCount, other);
          expect(resized.plannedWeekCountUpdatedAt, isNotNull);
          await tester.enterText(find.bySemanticsLabel('Block name'), 'Power');
          await tester.tap(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Save'),
            ),
          );
          await pumpWithStorage(tester);
          final saved = HiveService.getTrainingBlockById(strength.id)!;
          expect(saved.name, 'Power');
          expect(saved.plannedWeekCount, other);
          expect(
            saved.plannedWeekCountUpdatedAt,
            resized.plannedWeekCountUpdatedAt,
          );
        },
      );
    }

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
          find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')),
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

    Future<void> fillPlan(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, 'Pull');
      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      if (find.text('Done').evaluate().isNotEmpty) {
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
    }

    Future<void> confirmDeleteBlock(WidgetTester tester) async {
      await tapVisible(tester, find.text('Delete block'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Delete'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
    }

    editorTest(
      'create mode: deleting the block with the chosen starting week lands the '
      'plan in a live block',
      (tester) async {
        await pumpEditor(tester);
        final power = await seed(tester, 'Power', 4);
        await fillPlan(tester);
        await tester.tap(find.text('Starting week'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Power'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Week 3'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this week'));
        await tester.pumpAndSettle();
        expect(find.text('Power · Week 3'), findsOneWidget);

        await tester.tap(find.text('Power · Week 3'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit Power'));
        await tester.pumpAndSettle();
        await confirmDeleteBlock(tester);
        expect(find.text('Power deleted'), findsOneWidget);
        expect(
          HiveService.getTrainingBlockById(power.id)!.deletedAt,
          isNotNull,
        );
        // Dismiss without confirming: the editor must not keep the dead week.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Block 1 · Week 1'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await pumpWithStorage(tester);
        final saved = HiveService.getPlans().single;
        final progress = HiveService.progressForPlan('s', saved.id!)!;
        final week = HiveService.getTrainingWeekById(progress.activeWeekId)!;
        expect(week.blockId, isNot(power.id));
        expect(
          HiveService.getTrainingBlockById(week.blockId)!.deletedAt,
          isNull,
        );
        expect(
          HiveService.readTrainingGraph(ownerId: null).validate,
          returnsNormally,
        );
      },
    );

    editorTest(
      'create mode: shortening the block of the chosen week moves it to the '
      'last week left',
      (tester) async {
        await pumpEditor(tester);
        await seed(tester, 'Power', 4);
        await tester.tap(find.text('Starting week'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Power'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Week 4'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this week'));
        await tester.pumpAndSettle();
        expect(find.text('Power · Week 4'), findsOneWidget);

        await tester.tap(find.text('Power · Week 4'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit Power'));
        await tester.pumpAndSettle();
        await tester.enterText(find.bySemanticsLabel('Weeks'), '2');
        await tester.runAsync(() async {
          await tester.tap(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Save'),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await pumpWithStorage(tester);
        await tester.pumpAndSettle();
        expect(find.text('2 weeks'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Power · Week 2'), findsOneWidget);
      },
    );

    editorTest(
      'edit mode: shorten to the reached week, delete is disabled for the '
      'plan\'s block, and the manage sheet deletes another block',
      (tester) async {
        final strength = await seed(tester, 'Strength', 4);
        final extra = await seed(tester, 'Extra', 3);
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
        expect(find.text('Strength · Week 2 of 4'), findsOneWidget);

        await tester.tap(find.text('Training block'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit Strength'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'A workout is in this block right now. Move it to another block '
            'first.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.ancestor(
                  of: find.text('Delete block'),
                  matching: find.bySubtype<ButtonStyleButton>(),
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(find.bySemanticsLabel('Weeks'), '1');
        await tester.tap(
          find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Choose 2–52 weeks.'), findsOneWidget);
        await tester.enterText(find.bySemanticsLabel('Weeks'), '2');
        await tester.runAsync(() async {
          await tester.tap(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Save'),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await pumpWithStorage(tester);
        await tester.pumpAndSettle();
        expect(find.text('2 weeks'), findsOneWidget);
        expect(
          HiveService.getTrainingBlockById(strength.id)!.plannedWeekCount,
          2,
        );

        await tester.tap(find.byTooltip('Edit Extra'));
        await tester.pumpAndSettle();
        await confirmDeleteBlock(tester);
        expect(find.text('Extra deleted'), findsOneWidget);
        expect(find.byTooltip('Edit Extra'), findsNothing);
        expect(
          HiveService.getTrainingBlockById(extra.id)!.deletedAt,
          isNotNull,
        );

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Strength · Week 2 of 2'), findsOneWidget);
        expect(
          HiveService.readTrainingGraph(ownerId: null).validate,
          returnsNormally,
        );
      },
    );

    editorTest('actions read the lifecycle rules for both worlds', (
      tester,
    ) async {
      final strength = await seed(tester, 'Strength', 4);
      await pumpEditor(tester);
      final context = tester.element(find.byType(PlanEditorScreen));
      TrainingBlockActions actions(bool on) => TrainingBlockActions(
        context: () => context,
        splitId: 's',
        ownerId: () => null,
        lifecycleAvailable: (_) => on,
      );
      expect(actions(false).lifecycleAvailable, isFalse);
      expect(actions(false).minimumWeekCount(strength.id), 4);
      expect(actions(false).lifecycle.available(), isFalse);
      expect(actions(true).lifecycleAvailable, isTrue);
      expect(actions(true).minimumWeekCount(strength.id), 1);
      expect(actions(true).deleteBlocker(strength.id), isNull);
      expect(actions(true).lifecycle.deleteBlocker(strength), isNull);
      expect(SyncService.instance.blockLifecycleAvailable(null), isTrue);
    });

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
