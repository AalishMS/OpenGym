import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/screens/workout_summary_screen.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:gymapp/widgets/motion/state_switcher.dart';
import 'package:gymapp/widgets/workout/training_block_dialogs.dart';

import 'support/test_fonts.dart';

/// Motion in the workout's sheets and the summary: the block sheet trading
/// its list for a form, a chosen block's weeks folding open, and Share
/// crossing to its progress outside the captured summary.
void main() {
  setUpAll(loadTestFonts);

  Widget app(Widget home, {bool reduceMotion = false}) => MaterialApp(
    theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
    home: home,
  );

  group('block sheet', () {
    final now = DateTime(2026);
    TrainingBlock make(String id, String name, int weeks, int position) =>
        TrainingBlock(
          id: id,
          splitId: 's',
          name: name,
          position: position,
          createdAt: now,
          plannedWeekCount: weeks,
        );
    final blocks = [make('a', 'Base', 3, 0), make('b', 'Peak', 4, 1)];
    TrainingBlockSnapshot load() => (
      blocks: blocks,
      weeksByBlock: {for (final b in blocks) b.id: <TrainingWeek>[]},
    );

    Future<List<String?>> openSheet(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      final chosen = <String?>[];
      await tester.pumpWidget(
        app(
          reduceMotion: reduceMotion,
          Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () async => chosen.add(
                          await TrainingBlockDialogs.startingWeek(
                            context,
                            blocks: load().blocks,
                            weeksByBlock: load().weeksByBlock,
                            selectedWeekId: lazyTrainingWeekId('s', 'a', 1),
                            load: load,
                            onCreateBlock:
                                (_, _) async => throw StateError('x'),
                            onEditBlock: (block, _, _) async => block,
                          ),
                        ),
                    child: const Text('Open'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('the list gives way to a form and takes no taps as it goes', (
      tester,
    ) async {
      final chosen = await openSheet(tester);
      final listHeight = tester.getSize(find.byType(StateSwitcher)).height;
      await tester.tap(find.text('Create block').last);
      await tester.pump();
      // The form is there at once; the list is still fading out of the way,
      // and the sheet starts from the height it had rather than jumping.
      expect(find.text('Block name'), findsOneWidget);
      expect(
        tester.getSize(find.byType(StateSwitcher)).height,
        closeTo(listHeight, 0.5),
      );
      expect(find.text('Use this week'), findsOneWidget);
      await tester.tap(find.text('Use this week'), warnIfMissed: false);
      await tester.pump();
      expect(chosen, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Use this week'), findsNothing);
      expect(chosen, isEmpty);
      // ...and has since eased to the form's.
      expect(
        (tester.getSize(find.byType(StateSwitcher)).height - listHeight).abs(),
        greaterThan(1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('under reduced motion the form simply replaces the list', (
      tester,
    ) async {
      await openSheet(tester, reduceMotion: true);
      await tester.tap(find.text('Create block').last);
      await tester.pump();
      expect(find.text('Block name'), findsOneWidget);
      expect(find.text('Use this week'), findsNothing);
    });

    testWidgets('a chosen block folds its weeks open as the last folds away', (
      tester,
    ) async {
      final chosen = await openSheet(tester);
      expect(find.text('Week 4'), findsNothing);
      await tester.tap(find.text('Peak'));
      await tester.pump();
      // Peak's weeks are there to tap from the first frame, while Base's
      // are still folding away.
      expect(find.text('Week 4'), findsOneWidget);
      expect(find.text('Week 1'), findsNWidgets(2));
      Finder fold(String week) =>
          find
              .ancestor(
                of: find.text(week),
                matching: find.byType(SizeTransition),
              )
              .first;
      expect(
        tester.widget<SizeTransition>(fold('Week 4')).sizeFactor.value,
        lessThan(1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Week 1'), findsOneWidget);
      await tester.tap(find.text('Week 4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this week'));
      await tester.pumpAndSettle();
      expect(chosen, [lazyTrainingWeekId('s', 'b', 4)]);
    });
  });

  group('workout summary', () {
    final session = WorkoutSession(
      id: 'now',
      planId: 'push',
      planName: 'Push',
      date: DateTime(2026, 11, 5, 18),
      weekNumber: 3,
      durationSeconds: 3125,
      isCompleted: true,
      exercises: [
        Exercise(name: 'Bench press', sets: [gym.Set(weight: 100, reps: 5)]),
      ],
    );

    testWidgets('Share crosses to its progress outside the captured summary', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          WorkoutSummaryScreen(
            session: session,
            history: const [],
            records: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = find.byKey(const ValueKey('workout-summary-content'));
      final captured =
          find
              .ancestor(
                of: content,
                matching: find.byWidgetPredicate(
                  (widget) => widget is RepaintBoundary && widget.key != null,
                ),
              )
              .first;
      // Nothing that crosses or fades lives inside the image Share sends.
      expect(
        find.descendant(of: captured, matching: find.byType(StateSwitcher)),
        findsNothing,
      );
      expect(
        find.descendant(of: captured, matching: find.byTooltip('Share workout')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('summary-sharing')), findsNothing);
      await tester.tap(find.byTooltip('Share workout'));
      await tester.pump();
      // The progress is there at once, while the icon gives way in place.
      expect(find.byKey(const ValueKey('summary-sharing')), findsOneWidget);
      expect(find.byKey(const ValueKey('summary-share')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 75));
      final leaving =
          tester
              .widget<FadeTransition>(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('summary-share')),
                      matching: find.byType(FadeTransition),
                    )
                    .first,
              )
              .opacity
              .value;
      expect(leaving, inExclusiveRange(0, 1));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
