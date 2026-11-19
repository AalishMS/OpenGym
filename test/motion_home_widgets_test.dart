import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/home/plan_card.dart';
import 'package:gymapp/widgets/home/plan_grid.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';

import 'support/test_fonts.dart';

// Motion in Home's widgets: the plan grid closing a deleted plan's gap and
// its haptics, and the week's bars changing only where they can be seen.

void main() {
  setUpAll(loadTestFonts);

  group('plan grid', () {
    List<WorkoutPlan> plans() => [
      for (final name in ['Push', 'Pull', 'Legs', 'Upper'])
        WorkoutPlan(
          id: name,
          name: name,
          exercises: [ExerciseTemplate(name: 'Bench Press', sets: 3)],
        ),
    ];

    Finder card(String id) => find.byWidgetPredicate(
      (widget) => widget is PlanCard && widget.plan.id == id,
    );

    Widget host(
      List<WorkoutPlan> values, {
      bool reducedMotion = false,
      void Function(String, String)? onMove,
    }) => MaterialApp(
      theme: buildTheme(const Color(0xFF00A8FF), Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reducedMotion,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: PlanGrid(
              plans: values,
              stats: const {},
              onOpen: (_) {},
              onShowActions: (_) {},
              onMove: onMove ?? (_, _) {},
            ),
          ),
        ),
      ),
    );

    Future<StateSetter> pumpGrid(
      WidgetTester tester,
      List<WorkoutPlan> Function() values, {
      bool reducedMotion = false,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return host(values(), reducedMotion: reducedMotion);
          },
        ),
      );
      return update;
    }

    testWidgets('a deleted plan\'s gap closes as the cards after it slide '
        'into place', (tester) async {
      var values = plans();
      final update = await pumpGrid(tester, () => values);
      // Two columns at this width: Legs moves from the second row up.
      final start = tester.getTopLeft(card('Legs'));
      final destination = tester.getTopLeft(card('Pull'));
      expect(start.dy, greaterThan(destination.dy));

      update(() => values = values.where((p) => p.id != 'Pull').toList());
      await tester.pump();
      expect(card('Pull'), findsNothing);
      expect(tester.getTopLeft(card('Legs')), start);
      await tester.pump(const Duration(milliseconds: 90));
      final midway = tester.getTopLeft(card('Legs'));
      expect(midway.dy, lessThan(start.dy));
      expect(midway.dy, greaterThan(destination.dy));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(card('Legs')), destination);
    });

    testWidgets('a deleted plan\'s gap closes at once under reduced motion', (
      tester,
    ) async {
      var values = plans();
      final update = await pumpGrid(tester, () => values, reducedMotion: true);
      final destination = tester.getTopLeft(card('Pull'));
      update(() => values = values.where((p) => p.id != 'Pull').toList());
      await tester.pump();
      expect(tester.getTopLeft(card('Legs')), destination);
    });

    testWidgets('an arriving plan appears in place and moves nothing', (
      tester,
    ) async {
      var values = plans().take(3).toList();
      final update = await pumpGrid(tester, () => values);
      final before = {
        for (final id in ['Push', 'Pull', 'Legs'])
          id: tester.getTopLeft(card(id)),
      };
      update(() => values = plans());
      await tester.pump();
      for (final entry in before.entries) {
        expect(tester.getTopLeft(card(entry.key)), entry.value);
      }
      await tester.pump(const Duration(milliseconds: 90));
      for (final entry in before.entries) {
        expect(tester.getTopLeft(card(entry.key)), entry.value);
      }
    });

    testWidgets('picking a card up gives a light lift, and dropping it a '
        'selection click', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final moves = <(String, String)>[];
      await tester.pumpWidget(
        host(plans(), onMove: (from, to) => moves.add((from, to))),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Drag to reorder Push')),
      );
      await gesture.moveTo(tester.getCenter(card('Pull')));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moves, [('Push', 'Pull')]);
      expect(haptics, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
      ]);
    });
  });

  group('training snapshot', () {
    // A Wednesday; the week starts on the Monday before it.
    final now = DateTime(2026, 11, 18, 12);

    WorkoutSession session(String id, DateTime date, int sets) =>
        WorkoutSession(
          id: id,
          date: date,
          planName: 'Push',
          isCompleted: true,
          exercises: [
            Exercise(
              name: 'Bench Press',
              sets: [for (var i = 0; i < sets; i++) Set(reps: 8, weight: 50)],
            ),
          ],
        );

    final monday = session('monday', DateTime(2026, 11, 16, 9), 2);
    final tuesday = session('tuesday', DateTime(2026, 11, 17, 9), 4);

    double mondayBar(WidgetTester tester) =>
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('training-day-0')),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .height;

    Future<StateSetter> pumpSnapshot(
      WidgetTester tester,
      List<WorkoutSession> Function() sessions, {
      bool Function()? ticking,
      bool reducedMotion = false,
    }) async {
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF00A8FF), Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 800),
              disableAnimations: reducedMotion,
            ),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return TickerMode(
                    enabled: ticking?.call() ?? true,
                    child: TrainingSnapshot(
                      plans: const [],
                      sessions: sessions(),
                      now: now,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      return update;
    }

    testWidgets('bars first appear at their height', (tester) async {
      await pumpSnapshot(tester, () => [monday, tuesday]);
      expect(mondayBar(tester), 14 + 38 * 0.5);
      await tester.pump(const Duration(milliseconds: 100));
      expect(mondayBar(tester), 14 + 38 * 0.5);
    });

    testWidgets('a day changed in view moves over the long token', (
      tester,
    ) async {
      var sessions = [monday];
      final update = await pumpSnapshot(tester, () => sessions);
      expect(mondayBar(tester), 52);

      update(() => sessions = [monday, tuesday]);
      await tester.pump();
      expect(mondayBar(tester), 52);
      await tester.pump(AppMotion.long ~/ 2);
      expect(mondayBar(tester), lessThan(52));
      expect(mondayBar(tester), greaterThan(33));
      await tester.pump(AppMotion.long ~/ 2);
      expect(mondayBar(tester), 33);
      await tester.pumpAndSettle();
    });

    testWidgets('a day changed while covered lands, and nothing plays on the '
        'way back', (tester) async {
      var sessions = [monday];
      var ticking = true;
      final update = await pumpSnapshot(
        tester,
        () => sessions,
        ticking: () => ticking,
      );

      update(() => ticking = false);
      await tester.pump();
      update(() => sessions = [monday, tuesday]);
      await tester.pump();
      expect(mondayBar(tester), 33);

      update(() => ticking = true);
      await tester.pump();
      expect(mondayBar(tester), 33);
      await tester.pump(const Duration(milliseconds: 100));
      expect(mondayBar(tester), 33);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a day changes at once under reduced motion', (tester) async {
      var sessions = [monday];
      final update = await pumpSnapshot(
        tester,
        () => sessions,
        reducedMotion: true,
      );
      update(() => sessions = [monday, tuesday]);
      await tester.pump();
      expect(mondayBar(tester), 33);
    });
  });
}
