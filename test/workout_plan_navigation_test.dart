import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/underline_tab_strip.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

void main() {
  final harness = HiveTestHarness();
  final plans = [
    for (final name in ['Push', 'Pull', 'Legs'])
      WorkoutPlan(
        id: name,
        name: name,
        exercises: [
          for (var index = 0; index < 8; index++)
            ExerciseTemplate(name: '$name exercise $index', sets: 1),
        ],
      ),
  ];

  setUpAll(() async {
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

  Future<void> open(
    WidgetTester tester, {
    int index = 1,
    _Plans? planProvider,
    _Sessions? sessions,
    WorkoutPlan? plan,
    bool reduceMotion = false,
    bool fromHome = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>.value(
            value: planProvider ?? _Plans(plans),
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>.value(
            value: sessions ?? _Sessions(),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
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
                                    builder:
                                        (_) => WorkoutScreen(
                                          plan: plan ?? plans[index],
                                          planIndex: index,
                                        ),
                                  ),
                                ),
                            child: const Text('Open workout'),
                          ),
                        ),
                  )
                  : WorkoutScreen(plan: plan ?? plans[index], planIndex: index),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (fromHome) {
      await tester.tap(find.text('Open workout'));
      await tester.pumpAndSettle();
    }
  }

  String currentPlan(WidgetTester tester) =>
      tester.widget<WorkoutScreen>(find.byType(WorkoutScreen)).plan.name;

  int selectedWeek(WidgetTester tester) =>
      tester
          .widget<UnderlineTabStrip>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is UnderlineTabStrip && widget.rule == StripRule.top,
            ),
          )
          .selectedIndex;

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.drag(find.byType(CustomScrollView), Offset(dx, 0));
    await pumpWithStorage(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('body swipes follow plan order and stop at both boundaries', (
    tester,
  ) async {
    await open(tester);
    for (final step in [
      (dx: -160.0, name: 'Legs'),
      (dx: -160.0, name: 'Legs'),
      (dx: 160.0, name: 'Pull'),
      (dx: 160.0, name: 'Push'),
      (dx: 160.0, name: 'Push'),
    ]) {
      await swipe(tester, step.dx);
      expect(currentPlan(tester), step.name);
      expect(selectedWeek(tester), 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('body swipes use the current plan identity after reordering', (
    tester,
  ) async {
    final provider = _Plans(plans);
    await open(tester, planProvider: provider);
    provider.replace([plans[1], plans[2], plans[0]]);
    await tester.pump();
    await swipe(tester, -160);
    expect(currentPlan(tester), 'Legs');
    await swipe(tester, 160);
    expect(currentPlan(tester), 'Pull');
  });

  testWidgets('header and body swipes distinguish plans without IDs', (
    tester,
  ) async {
    final legacyPlans = [
      for (final plan in plans)
        WorkoutPlan(name: plan.name, exercises: plan.exercises),
    ];
    await open(tester, plan: legacyPlans[1], planProvider: _Plans(legacyPlans));
    final header =
        find
            .descendant(of: find.byType(AppBar), matching: find.text('Pull'))
            .first;
    await tester.drag(header, const Offset(130, 0));
    await tester.pumpAndSettle();
    expect(currentPlan(tester), 'Push');
    await swipe(tester, -160);
    expect(currentPlan(tester), 'Pull');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching by swipes and tabs leaves one workout route to close',
    (tester) async {
      await open(tester, fromHome: true);
      await swipe(tester, -160);
      await swipe(tester, 160);
      final planStrip = find.byWidgetPredicate(
        (widget) =>
            widget is UnderlineTabStrip && widget.rule == StripRule.bottom,
      );
      await tester.tap(
        find.descendant(of: planStrip, matching: find.text('Push')),
      );
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Push');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutScreen), findsNothing);
      expect(find.text('Open workout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('vertical and diagonal scrolling and short drags keep the plan', (
    tester,
  ) async {
    await open(tester);
    final scrollable =
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(currentPlan(tester), 'Pull');
    await tester.drag(find.byType(CustomScrollView), const Offset(-120, -160));
    await tester.pumpAndSettle();
    expect(currentPlan(tester), 'Pull');
    await tester.drag(find.byType(CustomScrollView), const Offset(-25, 0));
    await tester.pumpAndSettle();
    expect(currentPlan(tester), 'Pull');
    expect(selectedWeek(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing active plan does not impersonate another plan', (
    tester,
  ) async {
    await open(tester, planProvider: _Plans([plans[0], plans[2]]));
    await swipe(tester, -160);
    expect(currentPlan(tester), 'Pull');
    expect(find.text('Pull').first, findsOneWidget);
    expect(selectedWeek(tester), 1);
  });

  testWidgets('plan transitions slide in the swipe direction', (tester) async {
    await open(tester);
    for (final dx in [-160.0, 160.0]) {
      await tester.drag(find.byType(CustomScrollView), Offset(dx, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final title =
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.text(dx < 0 ? 'Legs' : 'Pull'),
              )
              .last;
      final route = ModalRoute.of(tester.element(title))!;
      expect(route.transitionDuration, const Duration(milliseconds: 190));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      final slide = tester.widget<SlideTransition>(
        find.ancestor(of: title, matching: find.byType(SlideTransition)).first,
      );
      expect(slide.position.value.dx.sign, dx < 0 ? 1 : -1);
      expect(slide.position.value.dx.abs(), lessThan(0.08));
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: title, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, inExclusiveRange(0.78, 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('workout content follows a swipe before the plan changes', (
    tester,
  ) async {
    await open(tester);
    final gesture = await tester.startGesture(const Offset(300, 450));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    final bodyTransform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byType(CustomScrollView),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(bodyTransform.transform.storage[12], inInclusiveRange(-28, -1));
    expect(currentPlan(tester), 'Pull');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(currentPlan(tester), 'Legs');
  });

  testWidgets('reduced motion switches plans immediately', (tester) async {
    await open(tester, reduceMotion: true);
    await swipe(tester, -160);
    final route = ModalRoute.of(tester.element(find.byType(WorkoutScreen)))!;
    expect(currentPlan(tester), 'Legs');
    expect(route.transitionDuration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'swipes wait for saving and a failed save keeps edits available',
    (tester) async {
      final sessions = _Sessions()..pending = Completer<void>();
      await open(tester, sessions: sessions);
      tester.widget<ExerciseCard>(find.byType(ExerciseCard).first).onAddSet(0);
      await tester.pump();
      expect(sessions.writes, hasLength(1));
      await tester.drag(find.byType(CustomScrollView), const Offset(-160, 0));
      await tester.pump();
      expect(currentPlan(tester), 'Pull');
      await tester.dragFrom(const Offset(300, 450), const Offset(-160, 0));
      await tester.pump();
      expect(sessions.writes, hasLength(1));
      sessions.pending!.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Pull');
      expect(find.text('Retry'), findsOneWidget);
      expect(
        tester
            .widget<ExerciseCard>(find.byType(ExerciseCard).first)
            .exercise
            .sets,
        hasLength(1),
      );

      sessions.pending = Completer<void>();
      await tester.drag(find.byType(CustomScrollView), const Offset(-160, 0));
      await tester.pump();
      expect(currentPlan(tester), 'Pull');
      expect(sessions.writes, hasLength(2));
      sessions.pending!.complete();
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(currentPlan(tester), 'Legs');
      final saved = sessions.writes.last;
      expect(saved.planId, 'Pull');
      expect(saved.weekNumber, 2);
      expect(saved.exercises.first.sets, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

class _Plans extends WorkoutPlanProvider {
  List<WorkoutPlan> values;
  _Plans(this.values);

  @override
  List<WorkoutPlan> get plans => values;

  void replace(List<WorkoutPlan> plans) {
    values = plans;
    notifyListeners();
  }
}

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> writes = [];
  Completer<void>? pending;

  @override
  Future<void> upsertSession(WorkoutSession session) async {
    writes.add(session);
    await pending?.future;
  }
}
