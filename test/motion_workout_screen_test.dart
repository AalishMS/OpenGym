import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/action_progress.dart';
import 'package:gymapp/widgets/plan_title_hero.dart';
import 'package:gymapp/widgets/underline_tab_strip.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

/// Motion on the workout screen itself: the plan swipe settling, the plan
/// switch arriving and then leaving like any page, the progress line that
/// waits a beat before it moves the log, and the drag lift.
void main() {
  final harness = HiveTestHarness();
  final plans = [
    for (final name in ['Push', 'Pull', 'Legs'])
      WorkoutPlan(
        id: name,
        name: name,
        exercises: [
          for (var index = 0; index < 3; index++)
            ExerciseTemplate(name: '$name exercise $index', sets: 1),
        ],
      ),
  ];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadTestFonts();
    await harness.open();
  });
  tearDownAll(harness.close);
  setUp(() async {
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    for (final plan in plans) {
      for (final week in [1, 2]) {
        final session = WorkoutSession(
          id: '${plan.id}-$week',
          planId: plan.id,
          planName: plan.name,
          weekNumber: week,
          date: DateTime(2026, 9, week),
          isCompleted: week == 1,
          exercises: [
            for (final template in plan.exercises)
              Exercise(name: template.name, sets: []),
          ],
        );
        await Hive.box<WorkoutSession>(
          HiveService.sessionsBox,
        ).put(session.id, session);
      }
    }
  });

  Future<_Sessions> open(
    WidgetTester tester, {
    int index = 1,
    bool reduceMotion = false,
    bool fromHome = false,
    TargetPlatform? platform,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 844);
    addTearDown(tester.view.reset);
    final sessions = _Sessions();
    await tester.runAsync(() => harness.prepareTraining(plans));
    Widget workout() => WorkoutScreen(plan: plans[index], planIndex: index);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>.value(
            value: _Plans(plans),
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>.value(value: sessions),
        ],
        child: MaterialApp(
          theme: buildTheme(
            const Color(0xFF008D8D),
            Brightness.light,
          ).copyWith(platform: platform),
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduceMotion),
                child: child!,
              ),
          home:
              fromHome
                  ? Builder(
                    builder:
                        (context) => Scaffold(
                          body: TextButton(
                            onPressed:
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => workout(),
                                  ),
                                ),
                            child: const Text('Open workout'),
                          ),
                        ),
                  )
                  : workout(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (fromHome) {
      await tester.tap(find.text('Open workout'));
      await tester.pumpAndSettle();
    }
    return sessions;
  }

  String currentPlan(WidgetTester tester) =>
      tester.widget<WorkoutScreen>(find.byType(WorkoutScreen).last).plan.name;

  /// How far the log has followed a plan swipe.
  double bodyOffset(WidgetTester tester) =>
      tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage[12];

  Finder title(String plan) => find.descendant(
    of: find.byType(PlanTitleHero),
    matching: find.text(plan),
  );

  Future<void> switchTo(WidgetTester tester, String plan) async {
    final strip = find.byWidgetPredicate(
      (widget) =>
          widget is UnderlineTabStrip && widget.rule == StripRule.bottom,
    );
    await tester.tap(find.descendant(of: strip, matching: find.text(plan)));
  }

  group('plan swipe', () {
    testWidgets('a flick past the last plan springs back without overshoot', (
      tester,
    ) async {
      await open(tester, index: 2);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(-160, 0),
        1500,
      );
      final offsets = <double>[];
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        offsets.add(bodyOffset(tester));
      }
      expect(currentPlan(tester), 'Legs');
      // It moved with the flick, and only ever on the side it was pulled.
      expect(offsets.reduce((a, b) => a < b ? a : b), lessThan(-1));
      for (final offset in offsets) {
        expect(offset, lessThanOrEqualTo(1e-6));
        expect(offset, greaterThanOrEqualTo(-AppMotion.shift));
      }
      await tester.pumpAndSettle();
      expect(bodyOffset(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short drag settles back within the standard time', (
      tester,
    ) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(300, 450));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      final pulled = bodyOffset(tester);
      expect(pulled, inInclusiveRange(-AppMotion.shift, -1));
      await gesture.up();
      await tester.pump();
      await tester.pump(AppMotion.standard);
      expect(bodyOffset(tester).abs(), lessThan(1));
      await tester.pumpAndSettle();
      expect(bodyOffset(tester), 0);
      expect(currentPlan(tester), 'Pull');
    });

    testWidgets('under reduced motion the log does not follow the finger', (
      tester,
    ) async {
      await open(tester, reduceMotion: true);
      final gesture = await tester.startGesture(const Offset(300, 450));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(bodyOffset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(bodyOffset(tester), 0);
    });
  });

  group('plan switch', () {
    testWidgets('the chosen plan comes in from its side as the old page '
        'gives way by the nudge', (tester) async {
      await open(tester);
      final rest = tester.getTopLeft(title('Pull')).dx;
      await switchTo(tester, 'Legs');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final route = ModalRoute.of(tester.element(title('Legs')))!;
      expect(route.animation!.value, inExclusiveRange(0, 1));
      // The page being replaced only gives way by the nudge; the platform's
      // own transition doesn't carry it off.
      final outgoing = tester.getTopLeft(title('Pull')).dx;
      expect(outgoing, lessThanOrEqualTo(rest));
      expect(outgoing, greaterThanOrEqualTo(rest - AppMotion.shift - 0.5));
      // The arriving page is still short of its place, to the right.
      expect(tester.getTopLeft(title('Legs')).dx, greaterThan(rest));
      // It lands within the standard time.
      await tester.pump(AppMotion.standard - const Duration(milliseconds: 60));
      expect(route.animation!.value, 1);
      expect(tester.getTopLeft(title('Legs')).dx, closeTo(rest, 0.5));
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Legs');
      expect(tester.getTopLeft(title('Legs')).dx, closeTo(rest, 0.5));
    });

    testWidgets('once it has landed, it lets go of the workout it replaced', (
      tester,
    ) async {
      await open(tester, fromHome: true);
      final replaced =
          ModalRoute.of(tester.element(title('Pull')))!
              as TransitionRoute<dynamic>;
      await switchTo(tester, 'Legs');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final route =
          ModalRoute.of(tester.element(title('Legs')))!
              as TransitionRoute<dynamic>;
      // While it arrives, the workout it replaces is singled out to hold
      // still under it.
      expect(route.canTransitionFrom(replaced), isFalse);
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(replaced.isActive, isFalse);
      // Landed, it no longer refers to the disposed route; held, every
      // switch would keep the whole chain of workouts before it alive.
      expect(route.canTransitionFrom(replaced), isTrue);
    });

    testWidgets('once it has landed, Back plays the page transition', (
      tester,
    ) async {
      await open(tester, fromHome: true);
      await switchTo(tester, 'Legs');
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final route = ModalRoute.of(tester.element(title('Legs')))!;
      expect(route.animation!.value, inExclusiveRange(0, 1));
      // The sideways entry stays put; it doesn't play backwards.
      final slide = tester.widget<SlideTransition>(
        find
            .ancestor(of: title('Legs'), matching: find.byType(SlideTransition))
            .first,
      );
      expect(slide.position.value, Offset.zero);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(of: title('Legs'), matching: find.byType(FadeTransition))
            .first,
      );
      expect(fade.opacity.value, 1);
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutScreen), findsNothing);
      expect(find.text('Open workout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('once it has landed, an iOS edge swipe goes back', (
      tester,
    ) async {
      await open(tester, fromHome: true, platform: TargetPlatform.iOS);
      await switchTo(tester, 'Legs');
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Legs');
      // A logged week, so nothing holds the page.
      await tester.tap(find.text('Week 1').last);
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      final back = tester.getCenter(find.byTooltip('Back'));
      await tester.dragFrom(Offset(5, back.dy), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutScreen), findsNothing);
      expect(find.text('Open workout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('progress line', () {
    Finder band() =>
        find
            .ancestor(
              of: find.byType(ActionProgress),
              matching: find.byType(SizeTransition),
            )
            .first;
    double logTop(WidgetTester tester) =>
        tester.getTopLeft(find.text('Pull exercise 0')).dy;

    testWidgets('a save that ends within a beat never moves the log', (
      tester,
    ) async {
      final sessions = await open(tester);
      final rest = logTop(tester);
      sessions.pending = Completer<void>();
      tester.widget<ExerciseCard>(find.byType(ExerciseCard).first).onAddSet(0);
      await tester.pump();
      // Named at once, for anything that looks, without taking any room.
      expect(find.text('Saving workout'), findsOneWidget);
      expect(tester.getSize(band()).height, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(logTop(tester), rest);
      sessions.pending!.complete();
      await tester.pump();
      expect(find.byType(ActionProgress), findsNothing);
      expect(logTop(tester), rest);
      await tester.pumpAndSettle();
      expect(logTop(tester), rest);
    });

    testWidgets('work still going after a beat folds the line open and away', (
      tester,
    ) async {
      final sessions = await open(tester);
      final rest = logTop(tester);
      sessions.pending = Completer<void>();
      tester.widget<ExerciseCard>(find.byType(ExerciseCard).first).onAddSet(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(AppMotion.standard ~/ 2);
      final opening = tester.getSize(band()).height;
      expect(opening, greaterThan(0));
      await tester.pump(AppMotion.standard);
      final opened = tester.getSize(band()).height;
      expect(opened, greaterThan(opening));
      expect(logTop(tester), closeTo(rest + opened, 0.5));
      sessions.pending!.complete();
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      // Folding away, keeping its label as it goes.
      expect(find.text('Saving workout'), findsOneWidget);
      expect(tester.getSize(band()).height, inExclusiveRange(0, opened));
      await tester.pumpAndSettle();
      expect(find.byType(ActionProgress), findsNothing);
      expect(logTop(tester), rest);
    });

    testWidgets('under reduced motion it opens and closes at once', (
      tester,
    ) async {
      final sessions = await open(tester, reduceMotion: true);
      final rest = logTop(tester);
      sessions.pending = Completer<void>();
      tester.widget<ExerciseCard>(find.byType(ExerciseCard).first).onAddSet(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final opened = tester.getSize(band()).height;
      expect(opened, greaterThan(0));
      expect(logTop(tester), closeTo(rest + opened, 0.5));
      sessions.pending!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(ActionProgress), findsNothing);
      expect(logTop(tester), rest);
    });

    testWidgets('a failed save folds its message open, and away after retry', (
      tester,
    ) async {
      final sessions = await open(tester);
      sessions.pending = Completer<void>();
      tester.widget<ExerciseCard>(find.byType(ExerciseCard).first).onAddSet(0);
      await tester.pump();
      sessions.pending!.completeError(StateError('disk full'));
      await tester.pump();
      await tester.pump();
      Finder message() =>
          find
              .ancestor(
                of: find.text('Retry'),
                matching: find.byType(SizeTransition),
              )
              .first;
      // There to find and tap from the first frame, opening rather than
      // appearing at full height.
      expect(find.text('Retry'), findsOneWidget);
      await tester.pump(AppMotion.standard ~/ 4);
      final opening = tester.getSize(message()).height;
      await tester.pumpAndSettle();
      final full = tester.getSize(message()).height;
      expect(opening, inExclusiveRange(0, full));
      sessions.pending = null;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('block menu', () {
    double menuScale(WidgetTester tester) =>
        tester
            .widget<ScaleTransition>(
              find
                  .ancestor(
                    of: find.text('Training blocks'),
                    matching: find.byType(ScaleTransition),
                  )
                  .first,
            )
            .scale
            .value;

    /// How visible the menu is through every fade above its title.
    double menuOpacity(WidgetTester tester) => tester
        .widgetList<FadeTransition>(
          find.ancestor(
            of: find.text('Training blocks'),
            matching: find.byType(FadeTransition),
          ),
        )
        .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);

    testWidgets('grows out of the block button, and leaves with a plain fade', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Block 1'));
      await tester.pump();
      expect(menuScale(tester), AppMotion.scale);
      await tester.pump(AppMotion.standard ~/ 2);
      expect(menuScale(tester), inExclusiveRange(AppMotion.scale, 1));
      await tester.pump(AppMotion.standard ~/ 2);
      expect(menuScale(tester), 1);
      expect(menuOpacity(tester), 1);
      await tester.pumpAndSettle();

      // Leaving, it holds its size as a dialog does, and is mostly gone
      // halfway through.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(find.text('Training blocks'), findsOneWidget);
      expect(menuScale(tester), 1);
      expect(menuOpacity(tester), lessThan(0.2));
      await tester.pumpAndSettle();
      expect(find.text('Training blocks'), findsNothing);
    });

    testWidgets('opens at once under reduced motion', (tester) async {
      await open(tester, reduceMotion: true);
      await tester.tap(find.text('Block 1'));
      await tester.pump();
      final route =
          ModalRoute.of(tester.element(find.text('Training blocks')))!;
      expect(route.animation!.isCompleted, isTrue);
      expect(menuScale(tester), 1);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('a held exercise rises onto a raised ground and sinks back', (
    tester,
  ) async {
    await open(tester);
    final context = tester.element(find.text('Pull exercise 0'));
    final page = backgroundColor(context);
    final raised = surfaceColor(context);
    Color? ground() =>
        tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text('Pull exercise 0'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Pull exercise 0')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(ground(), page);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ground(), raised);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _Plans extends WorkoutPlanProvider {
  final List<WorkoutPlan> values;
  _Plans(this.values);

  @override
  List<WorkoutPlan> get plans => values;
}

class _Sessions extends WorkoutSessionProvider {
  Completer<void>? pending;

  @override
  Future<void> upsertSession(WorkoutSession session) async {
    await pending?.future;
  }
}
