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
import 'package:gymapp/widgets/motion/collapsible.dart';
import 'package:gymapp/widgets/plan_title_hero.dart';
import 'package:gymapp/widgets/underline_tab_strip.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:gymapp/widgets/workout/training_block_strip.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

/// Motion on the workout screen itself: the log following a plan swipe and
/// settling, the plan switch trading one log for the next while the header
/// holds still and then leaving like any page, the progress line that waits
/// a beat before it moves the log, and the drag lift.
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

  /// [plan]'s log: the scroll view holding its exercises.
  Finder log(String plan) => find.ancestor(
    of: find.text('$plan exercise 0'),
    matching: find.byType(CustomScrollView),
  );

  /// How far [plan]'s log has moved sideways.
  double offsetOf(WidgetTester tester, String plan) =>
      tester
          .widget<Transform>(
            find
                .ancestor(of: log(plan), matching: find.byType(Transform))
                .first,
          )
          .transform
          .storage[12];

  /// How visible [plan]'s log is through every fade above it.
  double opacityOf(WidgetTester tester, String plan) => tester
      .widgetList(
        find.ancestor(
          of: log(plan),
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity || widget is FadeTransition,
          ),
        ),
      )
      .fold(
        1.0,
        (opacity, widget) =>
            opacity *
            (widget is Opacity
                ? widget.opacity
                : (widget as FadeTransition).opacity.value),
      );

  /// How far the only log on screen has followed a plan swipe.
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

  final planStrip = find.byWidgetPredicate(
    (widget) => widget is UnderlineTabStrip && widget.rule == StripRule.bottom,
  );

  Future<void> switchTo(WidgetTester tester, String plan) async {
    await tester.tap(
      find.descendant(of: planStrip.last, matching: find.text(plan)),
    );
  }

  /// Where the parts that hold still through a switch stand: the title, the
  /// plan tabs, the week bar. The page on top is the last in the tree.
  List<Rect> frame(WidgetTester tester, String plan) => [
    tester.getRect(title(plan).last),
    tester.getRect(planStrip.last),
    tester.getRect(
      find.descendant(of: planStrip.last, matching: find.text('Legs')),
    ),
    tester.getRect(find.byType(TrainingBlockStrip).last),
  ];

  /// Pumps past the frame a switch is pushed in. A page route's first frame
  /// is built offstage while the hero controller measures it, so the chosen
  /// plan's workout is first seen, and first takes taps, on the frame after.
  Future<void> pushed(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// The plan tabs' underline while it slides between two tabs.
  Finder slidingMark() =>
      find.descendant(of: planStrip.last, matching: find.byType(Positioned));

  group('plan swipe', () {
    testWidgets('the log follows the finger one to one and fades as it goes, '
        'while the header holds still', (tester) async {
      await open(tester);
      final rest = frame(tester, 'Pull');
      final gesture = await tester.startGesture(const Offset(300, 450));
      // Recognised as a swipe: the log starts from where it is, rather than
      // jumping by the slop to catch the finger up.
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      expect(offsetOf(tester, 'Pull'), 0);
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(offsetOf(tester, 'Pull'), -80);
      final early = opacityOf(tester, 'Pull');
      expect(early, inExclusiveRange(0.5, 1));
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(offsetOf(tester, 'Pull'), -160);
      expect(opacityOf(tester, 'Pull'), inExclusiveRange(0.5, early));
      // Past 40% of the width it holds at half, still legible.
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(offsetOf(tester, 'Pull'), -280);
      expect(opacityOf(tester, 'Pull'), closeTo(0.5, 1e-9));
      expect(frame(tester, 'Pull'), rest);
      expect(currentPlan(tester), 'Pull');
      await gesture.up();
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Legs');
    });

    testWidgets('past the last plan it rubber-bands without fading, and a '
        'flick springs back without overshoot', (tester) async {
      await open(tester, index: 2);
      final gesture = await tester.startGesture(const Offset(300, 450));
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();
      // A small fraction of the travel: the edge reads as an edge.
      expect(bodyOffset(tester), inInclusiveRange(-AppMotion.shift, -1));
      expect(opacityOf(tester, 'Legs'), 1);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(-160, 0),
        1500,
      );
      final offsets = <double>[];
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        offsets.add(bodyOffset(tester));
        expect(opacityOf(tester, 'Legs'), 1);
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

    testWidgets('a drag let go short of a switch springs back to full '
        'opacity', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(300, 450));
      // 38px in all: short of the 40 a switch takes.
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-18, 0));
      await tester.pump();
      expect(offsetOf(tester, 'Pull'), -18);
      final pulled = opacityOf(tester, 'Pull');
      expect(pulled, lessThan(1));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // On its way back, and its opacity coming back with it.
      expect(offsetOf(tester, 'Pull'), inExclusiveRange(-18, 0));
      expect(opacityOf(tester, 'Pull'), inExclusiveRange(pulled, 1));
      await tester.pump(AppMotion.standard);
      expect(offsetOf(tester, 'Pull').abs(), lessThan(1));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, 'Pull'), 0);
      expect(opacityOf(tester, 'Pull'), 1);
      expect(currentPlan(tester), 'Pull');
      expect(find.byType(WorkoutScreen), findsOneWidget);
    });

    testWidgets('under reduced motion the log does not follow the finger', (
      tester,
    ) async {
      await open(tester, reduceMotion: true);
      final gesture = await tester.startGesture(const Offset(300, 450));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(bodyOffset(tester), 0);
      expect(opacityOf(tester, 'Pull'), 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(bodyOffset(tester), 0);
    });
  });

  group('plan switch', () {
    testWidgets('a swipe carries the log out as the next one comes in over '
        'it from the other side, and only the log moves', (tester) async {
      await open(tester);
      final rest = frame(tester, 'Pull');
      final handle = tester.ensureSemantics();
      final gesture = await tester.startGesture(const Offset(300, 450));
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      final released = offsetOf(tester, 'Pull');
      expect(released, -100);
      await gesture.up();
      await pushed(tester);

      // The switch has been pushed: both logs are here, the new one over
      // the old, and only one header shows, standing where it stood.
      final route = ModalRoute.of(tester.element(title('Legs')))!;
      expect(route.animation!.value, 0);
      expect(find.text('Pull exercise 0'), findsOneWidget);
      // The old log carries on from where the finger left it.
      expect(offsetOf(tester, 'Pull'), lessThanOrEqualTo(released));
      // The new one starts a quarter of the width out on the right, unseen
      // but laid out, announced and tappable already.
      final from = AppMotion.swipeShift(600);
      expect(offsetOf(tester, 'Legs'), closeTo(from, 0.01));
      expect(opacityOf(tester, 'Legs'), 0);
      expect(
        tester.getSemantics(find.text('Legs exercise 0')).label,
        contains('Legs exercise 0'),
      );
      expect(frame(tester, 'Legs'), rest);

      await tester.pump(const Duration(milliseconds: 40));
      final leaving = offsetOf(tester, 'Pull');
      expect(leaving, lessThan(released));
      expect(opacityOf(tester, 'Pull'), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      // The old log has gone on further and cleared out; the new one is
      // fading in and closing on its place.
      expect(offsetOf(tester, 'Pull'), lessThan(leaving));
      expect(opacityOf(tester, 'Pull'), 0);
      final arriving = offsetOf(tester, 'Legs');
      expect(arriving, inExclusiveRange(0, from));
      expect(opacityOf(tester, 'Legs'), inExclusiveRange(0, 1));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      expect(frame(tester, 'Legs'), rest);
      // The underline slides from the tab it left to the chosen one.
      final mark = tester.getRect(slidingMark());
      final pullTab = tester.getRect(
        find.descendant(of: planStrip.last, matching: find.text('Pull')),
      );
      final legsTab = tester.getRect(
        find.descendant(of: planStrip.last, matching: find.text('Legs')),
      );
      expect(mark.left, inExclusiveRange(pullTab.left - 1, legsTab.left));

      await tester.pump(const Duration(milliseconds: 80));
      expect(offsetOf(tester, 'Legs'), inExclusiveRange(0, arriving));

      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1);
      expect(currentPlan(tester), 'Legs');
      expect(find.text('Pull exercise 0'), findsNothing);
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(offsetOf(tester, 'Legs'), 0);
      expect(opacityOf(tester, 'Legs'), 1);
      expect(slidingMark(), findsNothing);
      expect(frame(tester, 'Legs'), rest);
      // Landed, the page is opaque again.
      final scaffold = tester.widget<Scaffold>(
        find.ancestor(of: log('Legs'), matching: find.byType(Scaffold)).first,
      );
      expect(
        scaffold.backgroundColor,
        backgroundColor(tester.element(log('Legs'))),
      );
      handle.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the arriving log takes a tap on its first frame', (
      tester,
    ) async {
      await open(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(-160, 0));
      await pushed(tester);
      expect(opacityOf(tester, 'Legs'), 0);
      final card = find.descendant(
        of: log('Legs'),
        matching: find.byType(ExerciseCard),
      );
      await tester.tap(
        find.descendant(of: card.first, matching: find.text('Add set')),
      );
      await tester.pump();
      expect(
        tester.widget<ExerciseCard>(card.first).exercise.sets,
        hasLength(1),
      );
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Legs');
      expect(
        tester.widget<ExerciseCard>(card.first).exercise.sets,
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tab tap plays the same trade, the old log leaving from '
        'rest', (tester) async {
      await open(tester);
      final rest = frame(tester, 'Pull');
      await switchTo(tester, 'Push');
      await pushed(tester);
      // Toward an earlier plan: the old log leaves to the right, from rest,
      // and the new one comes in from the left.
      expect(offsetOf(tester, 'Pull'), 0);
      expect(opacityOf(tester, 'Pull'), 1);
      expect(
        offsetOf(tester, 'Push'),
        closeTo(-AppMotion.swipeShift(600), 0.01),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(offsetOf(tester, 'Pull'), greaterThan(0));
      expect(opacityOf(tester, 'Pull'), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, 'Pull'), 0);
      expect(
        offsetOf(tester, 'Push'),
        inExclusiveRange(-AppMotion.swipeShift(600), 0),
      );
      expect(opacityOf(tester, 'Push'), inExclusiveRange(0, 1));
      expect(frame(tester, 'Push'), rest);
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Push');
      expect(offsetOf(tester, 'Push'), 0);
      expect(opacityOf(tester, 'Push'), 1);
      expect(frame(tester, 'Push'), rest);
    });

    testWidgets('a slow save keeps the new log waiting, not half arrived', (
      tester,
    ) async {
      final sessions = await open(tester);
      sessions.pending = Completer<void>();
      tester.widget<ExerciseCard>(find.byType(ExerciseCard).first).onAddSet(0);
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(-160, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // The old log has gone at once, without waiting for the save.
      expect(opacityOf(tester, 'Pull'), 0);
      expect(find.text('Legs exercise 0'), findsNothing);
      sessions.pending!.complete();
      await tester.pump();
      await tester.pump();
      // The new one starts its arrival only now it is here.
      expect(
        offsetOf(tester, 'Legs'),
        closeTo(AppMotion.swipeShift(600), 0.01),
      );
      expect(opacityOf(tester, 'Legs'), 0);
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Legs');
      expect(offsetOf(tester, 'Legs'), 0);
      expect(opacityOf(tester, 'Legs'), 1);
    });

    testWidgets('a failed save pushes nothing and the log comes back', (
      tester,
    ) async {
      final sessions = await open(tester);
      sessions.pending = Completer<void>();
      tester.widget<ExerciseCard>(find.byType(ExerciseCard).first).onAddSet(0);
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(-160, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(offsetOf(tester, 'Pull'), lessThan(-160));
      expect(opacityOf(tester, 'Pull'), 0);
      sessions.pending!.completeError(StateError('disk full'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(offsetOf(tester, 'Pull'), lessThan(0));
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Pull');
      expect(find.byType(WorkoutScreen), findsOneWidget);
      expect(offsetOf(tester, 'Pull'), 0);
      expect(opacityOf(tester, 'Pull'), 1);
      expect(find.text('Retry'), findsOneWidget);
      // Back in the semantics tree, and taking taps again.
      expect(
        tester.getSemantics(find.text('Pull exercise 0')).label,
        contains('Pull exercise 0'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('under reduced motion the switch lands at once', (
      tester,
    ) async {
      await open(tester, reduceMotion: true);
      await tester.drag(find.byType(CustomScrollView), const Offset(-160, 0));
      await tester.pump();
      final route = ModalRoute.of(tester.element(title('Legs')))!;
      expect(route.animation!.isCompleted, isTrue);
      expect(find.text('Pull exercise 0'), findsNothing);
      expect(offsetOf(tester, 'Legs'), 0);
      expect(opacityOf(tester, 'Legs'), 1);
      expect(slidingMark(), findsNothing);
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Legs');
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
      // The page leaves as a page; its log's arrival doesn't play backwards.
      final logTransform = tester.widget<Transform>(
        find.ancestor(of: log('Legs'), matching: find.byType(Transform)).first,
      );
      expect(logTransform.transform.storage[12], 0);
      final logFade = tester.widget<Opacity>(
        find.ancestor(of: log('Legs'), matching: find.byType(Opacity)).first,
      );
      expect(logFade.opacity, 1);
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
                matching: find.byType(Collapsible),
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
    final raised = surfaceColor(tester.element(find.text('Pull exercise 0')));
    final folded = find.byKey(const ValueKey('exercise-reorder'));
    Color? ground() =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.descendant(
                              of: folded,
                              matching: find.text('Pull exercise 0'),
                            ),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Pull exercise 0')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    // Picked up, it is still the title on the page.
    expect(ground()!.a, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ground(), raised);
    await gesture.up();
    await tester.pump();
    await tester.pump();
    await tester.pump(AppMotion.quick);
    final sinking = ground()!.a;
    expect(sinking, greaterThan(0));
    expect(sinking, lessThan(raised.a));
    await tester.pumpAndSettle();
    expect(folded, findsNothing);
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
