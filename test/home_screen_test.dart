import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/navigation/workout_destination.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/spacing.dart';
import 'package:gymapp/utils/format.dart';
import 'package:gymapp/utils/plan_stats.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:gymapp/widgets/home/home_plan_row.dart';
import 'package:gymapp/widgets/home/plan_marker.dart';
import 'package:gymapp/widgets/home/up_next_card.dart';
import 'package:gymapp/widgets/app_wordmark.dart';
import 'package:gymapp/widgets/raised_card.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';
import 'package:gymapp/widgets/workout/training_block_strip.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

/// The launcher's own plan mark: which workout it offers, and out of how many.
PlanMarker upNextMarker(WidgetTester tester) => tester.widget<PlanMarker>(
  find.descendant(
    of: find.byType(UpNextCard),
    matching: find.byType(PlanMarker),
  ),
);

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
    );
    await loadTestFonts();
    await hiveHarness.open();
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  Widget homeHost({
    Size size = const Size(390, 800),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
    List<WorkoutPlan> plans = const [],
    List<WorkoutSession> sessions = const [],
    List<NavigatorObserver> observers = const [],
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WorkoutPlanProvider>(
          create: (_) => _PlanProvider(plans),
        ),
        ChangeNotifierProvider<WorkoutSessionProvider>(
          create: (_) => _SessionProvider(sessions),
        ),
      ],
      child: MaterialApp(
        key: UniqueKey(),
        theme: buildTheme(const Color(0xFF00A8FF), brightness),
        navigatorObservers: observers,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: const HomeScreen(),
            ),
          ),
        ),
      ),
    );
  }

  WorkoutPlan populatedPlan() => WorkoutPlan(
    id: 'plan-1',
    name: 'Push Day',
    planColor: 0,
    exercises: [
      ExerciseTemplate(name: 'Bench Press', sets: 3),
      ExerciseTemplate(name: 'Overhead Press', sets: 3),
      ExerciseTemplate(name: 'Cable Fly', sets: 3),
      ExerciseTemplate(name: 'Triceps Extension', sets: 3),
    ],
  );

  ({WorkoutPlan plan, WorkoutSession session}) populatedData() {
    final plan = populatedPlan();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final session = WorkoutSession(
      id: 'session-1',
      planId: plan.id,
      planName: plan.name,
      date: yesterday,
      exercises: const [],
    );
    return (plan: plan, session: session);
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 800),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
    List<WorkoutPlan> plans = const [],
    List<WorkoutSession> sessions = const [],
    List<NavigatorObserver> observers = const [],
  }) async {
    if (plans.isNotEmpty || sessions.isNotEmpty) {
      await tester.runAsync(() async {
        for (final session in sessions) {
          session.splitId ??=
              plans.where((p) => p.id == session.planId).firstOrNull?.splitId ??
              'test-split';
          await HiveService.putSessionRaw(session);
        }
        await hiveHarness.prepareTraining(plans);
      });
    }
    await tester.pumpWidget(
      homeHost(
        size: size,
        textScale: textScale,
        brightness: brightness,
        plans: plans,
        sessions: sessions,
        observers: observers,
      ),
    );
  }

  testWidgets('system Back leaves Manage before leaving Home', (tester) async {
    await pumpHome(tester, plans: [populatedPlan()]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('Start workout'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
  });

  testWidgets('plan actions close before Back leaves Manage', (tester) async {
    await pumpHome(tester, plans: [populatedPlan()]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan actions'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Edit plan'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Manage'), findsOneWidget);
  });

  testWidgets('plan card exposes only its overflow action', (tester) async {
    final data = populatedData();
    await pumpHome(tester, plans: [data.plan], sessions: [data.session]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('[START]'), findsNothing);
    final size = tester.getSize(find.byTooltip('Plan actions'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('new plan is an inline action without an overlapping FAB', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      await pumpHome(tester, brightness: brightness, plans: [populatedPlan()]);
      expect(find.byType(FloatingActionButton), findsNothing);
      final action = find.text('New plan');
      await tester.scrollUntilVisible(
        action,
        150,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(PlanEditorScreen), findsOneWidget);
    }
  });

  testWidgets('plan overflow hit region stays inside the card', (tester) async {
    final data = populatedData();
    await pumpHome(tester, plans: [data.plan], sessions: [data.session]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    final overflow = find.byTooltip('Plan actions');
    final card = find.ancestor(
      of: overflow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.clipBehavior == Clip.antiAlias,
      ),
    );
    final buttonRect = tester.getRect(overflow);
    final cardRect = tester.getRect(card);

    expect(card, findsOneWidget);
    expect(buttonRect.left, greaterThanOrEqualTo(cardRect.left));
    expect(buttonRect.top, greaterThanOrEqualTo(cardRect.top));
    expect(buttonRect.right, lessThanOrEqualTo(cardRect.right));
    expect(buttonRect.bottom, lessThanOrEqualTo(cardRect.bottom));
  });

  testWidgets('plan card exposes summary and overflow actions', (tester) async {
    final data = populatedData();
    await pumpHome(tester, plans: [data.plan], sessions: [data.session]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('Push Day'), findsOneWidget);
    expect(find.textContaining('4 exercises'), findsOneWidget);
    expect(find.textContaining('12 sets'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.textContaining('Bench Press'), findsOneWidget);
    expect(find.textContaining('Overhead Press'), findsOneWidget);
    expect(find.textContaining('Cable Fly'), findsOneWidget);
    expect(find.text('[START]'), findsNothing);
    expect(find.byTooltip('Plan actions'), findsOneWidget);
  });

  testWidgets('dragging a plan onto another card changes grid order', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final plans = [
      populatedPlan(),
      populatedPlan().copyWith(id: 'plan-2', name: 'Pull Day'),
      populatedPlan().copyWith(id: 'plan-3', name: 'Leg Day'),
    ];
    await pumpHome(tester, size: const Size(1200, 800), plans: plans);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    final source = find.byTooltip('Drag to reorder Push Day');
    final target = find.byTooltip('Drag to reorder Pull Day');
    expect(source, findsOneWidget);
    expect(target, findsOneWidget);
    expect(tester.getSize(source), const Size(48, 48));

    await tester.dragFrom(
      tester.getCenter(source),
      tester.getCenter(target) - tester.getCenter(source),
    );
    await tester.pumpAndSettle();

    final provider = Provider.of<WorkoutPlanProvider>(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    expect(provider.plans.map((plan) => plan.id), [
      'plan-2',
      'plan-1',
      'plan-3',
    ]);
  });

  testWidgets('plan actions offer a move control', (tester) async {
    final plans = [
      populatedPlan(),
      populatedPlan().copyWith(id: 'plan-2', name: 'Pull Day'),
    ];
    await pumpHome(tester, plans: plans);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Move later'), findsOneWidget);

    await tester.tap(find.text('Move later'));
    await tester.pumpAndSettle();
    final provider = Provider.of<WorkoutPlanProvider>(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    expect(provider.plans.first.id, 'plan-2');
  });

  testWidgets('plan names use title case without changing stored names', (
    tester,
  ) async {
    final plan = populatedPlan().copyWith(name: 'push day');
    await pumpHome(tester, plans: [plan]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    expect(find.text('Push Day'), findsOneWidget);
    expect(find.text('push day'), findsNothing);
    expect(plan.name, 'push day');

    await tester.tap(find.byTooltip('Plan actions'));
    await tester.pumpAndSettle();
    expect(find.text('Push Day'), findsNWidgets(2));
    expect(find.text('PUSH DAY'), findsNothing);
  });

  testWidgets('plan action menu rows have 48px tap targets', (tester) async {
    final data = populatedData();
    await pumpHome(tester, plans: [data.plan], sessions: [data.session]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan actions'));
    await tester.pumpAndSettle();
    // A bottom sheet, not a dialog, with the one destructive row last.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    for (final label in ['Change color', 'Duplicate plan', 'Edit plan']) {
      expect(
        tester.getTopLeft(find.text(label)).dy,
        lessThan(tester.getTopLeft(find.text('Delete plan')).dy),
        reason: label,
      );
    }
    for (final label in [
      'Change color',
      'Duplicate plan',
      'Edit plan',
      'Delete plan',
    ]) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      expect(target, findsOneWidget, reason: label);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('plan actions stay above Android navigation buttons', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    for (final height in [800.0, 420.0]) {
      tester.view.physicalSize = Size(390, height);
      await pumpHome(tester, size: Size(390, height), plans: [populatedPlan()]);
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plan actions'));
      await tester.pumpAndSettle();
      final delete = find.ancestor(
        of: find.text('Delete plan'),
        matching: find.byType(InkWell),
      );
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      expect(tester.getRect(delete).bottom, lessThanOrEqualTo(height - 48));
      expect(delete.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('card tap opens Workout and long press opens plan actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);

    final data = populatedData();
    await pumpHome(tester, plans: [data.plan], sessions: [data.session]);
    await tester.ensureVisible(find.text('Push Day').last);
    await tester.tap(find.text('Push Day').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(WorkoutScreen))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Push Day').last);
    await tester.longPress(find.text('Push Day').last);
    await tester.pumpAndSettle();
    expect(find.text('Change color'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('plan color is limited to identity markers', (tester) async {
    final plan = populatedPlan();
    await pumpHome(tester, plans: [plan]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byType(HomeScreen));
    final expectedHomeColor = planColorOf(plan.planColor, homeContext);
    final homeMarker = find.byType(PlanMarker);
    expect(homeMarker, findsOneWidget);
    final homeMarkerContainer = tester.widget<Container>(
      find.descendant(of: homeMarker, matching: find.byType(Container)),
    );
    expect(
      (homeMarkerContainer.decoration! as BoxDecoration).color,
      expectedHomeColor,
    );

    // Manage arranges plans; the workout opens from the ordinary row.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // The launcher and the row below it draw the same mark.
    for (final host in [UpNextCard, HomePlanRow]) {
      final marker = tester.widget<Container>(
        find.descendant(
          of: find.descendant(
            of: find.byType(host),
            matching: find.byType(PlanMarker),
          ),
          matching: find.byType(Container),
        ),
      );
      expect(
        (marker.decoration! as BoxDecoration).color,
        expectedHomeColor,
        reason: '$host',
      );
    }
    await tester.ensureVisible(find.text('Push Day').last);
    await tester.tap(find.text('Push Day').last);
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Push Day' &&
            widget.style?.fontSize == 18,
      ),
    );
    final context = tester.element(find.byType(WorkoutScreen));
    expect(title.style?.color, textPrimaryColor(context));

    final workoutMarker = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Push Day plan marker',
    );
    expect(workoutMarker, findsOneWidget);
    final workoutMarkerContainer = tester.widget<Container>(
      find.descendant(of: workoutMarker, matching: find.byType(Container)),
    );
    expect(
      (workoutMarkerContainer.decoration! as BoxDecoration).color,
      planColorOf(plan.planColor, context),
    );
  });

  testWidgets('workout add exercise is a quiet action with a 48 pixel target', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);

    for (final brightness in Brightness.values) {
      final plan = populatedPlan();
      await pumpHome(tester, brightness: brightness, plans: [plan]);
      await tester.ensureVisible(find.text('Push Day').last);
      await tester.tap(find.text('Push Day').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('add_exercise_button')),
        300,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      final addTile = find.text('Add exercise');
      expect(
        find.ancestor(
          of: addTile,
          matching: find.byType(ReorderableDelayedDragStartListener),
        ),
        findsNothing,
      );
      final target = find.byKey(const ValueKey('add_exercise_button'));
      final button = tester.widget<TextButton>(target);
      expect(
        button.style!.foregroundColor!.resolve({}),
        accentColor(tester.element(find.byType(WorkoutScreen))),
      );
      expect(button.style!.backgroundColor?.resolve({}), isNull);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('holding an exercise heading reorders the workout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);

    final plan = populatedPlan();
    await pumpHome(tester, plans: [plan]);
    await tester.ensureVisible(find.text('Push Day').last);
    await tester.tap(find.text('Push Day').last);
    await tester.pumpAndSettle();

    // Holding an exercise's name folds the log to one row per exercise.
    final folded = find.byKey(const ValueKey('exercise-reorder'));
    Future<void> hold(String name, Offset by) async {
      await tester.ensureVisible(find.text(name));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(name)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 300));
      expect(folded, findsOneWidget);
      await gesture.moveBy(by);
      // Long enough for the rows to scroll if the list runs off screen.
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await pumpWithStorage(tester);
      await tester.pumpAndSettle();
      expect(folded, findsNothing);
    }

    // One row down.
    await hold('Bench Press', const Offset(0, 60));
    final reordered = tester.widgetList<ExerciseCard>(
      find.byType(ExerciseCard),
    );
    expect(reordered.first.exercise.name, 'Overhead Press');
    // The log is scrolled so the moved exercise sits where it was dropped.
    expect(find.text('Bench Press').hitTestable(), findsOneWidget);

    // Pushed past the end, it takes the last place.
    await hold('Overhead Press', const Offset(0, 800));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    final endOrder = tester.widgetList<ExerciseCard>(find.byType(ExerciseCard));
    expect(endOrder.last.exercise.name, 'Overhead Press');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('plan header swipe follows the active plan after reorder', (
    tester,
  ) async {
    final plans = [
      populatedPlan(),
      populatedPlan().copyWith(id: 'plan-2', name: 'Pull Day'),
      populatedPlan().copyWith(id: 'plan-3', name: 'Leg Day'),
    ];
    final planProvider = _PlanProvider(plans);

    await tester.runAsync(() => hiveHarness.prepareTraining(plans));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>.value(
            value: planProvider,
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>(
            create: (_) => _SessionProvider(),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
          home: WorkoutScreen(plan: plans[1], planIndex: 1),
        ),
      ),
    );
    await tester.pump();

    planProvider.replacePlans([plans[0], plans[2], plans[1]]);
    await tester.pump();
    await tester.fling(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Pull Day' &&
            widget.style?.fontSize == 18,
      ),
      const Offset(100, 0),
      1000,
    );
    await pumpWithStorage(tester);

    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Leg Day' &&
            widget.style?.fontSize == 18,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a single plan ignores swipes and weeks change only through tabs',
    (tester) async {
      final plan = populatedPlan();
      final sessions = [
        for (var week = 1; week <= 3; week++)
          WorkoutSession(
            id: 'session-$week',
            planId: plan.id,
            planName: plan.name,
            date: DateTime(2026, 9, week),
            exercises: const [],
            weekNumber: week,
            isCompleted: week < 3,
          ),
      ];
      await tester.runAsync(() async {
        for (final session in sessions) {
          await Hive.box<WorkoutSession>(
            HiveService.sessionsBox,
          ).put(session.id, session);
        }
      });

      await tester.runAsync(() => hiveHarness.prepareTraining([plan]));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WorkoutPlanProvider>.value(
              value: _PlanProvider([plan]),
            ),
            ChangeNotifierProvider<WorkoutSessionProvider>(
              create: (_) => _SessionProvider(sessions),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
            home: WorkoutScreen(plan: plan, planIndex: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      int selectedWeek() {
        final strip = tester.widget<TrainingBlockStrip>(
          find.byType(TrainingBlockStrip),
        );
        return strip.weeksByBlock.values
                .expand((weeks) => weeks)
                .firstWhere((week) => week.id == strip.selectedWeekId)
                .number -
            1;
      }

      expect(selectedWeek(), 2);
      for (final delta in [100.0, -100.0]) {
        await tester.flingFrom(const Offset(200, 330), Offset(delta, 0), 1000);
        await tester.pumpAndSettle();
        expect(selectedWeek(), 2);
      }
      for (final expected in [1, 0, 1, 2]) {
        await tester.tap(find.text('Week ${expected + 1}').last);
        await tester.pumpAndSettle();
        expect(selectedWeek(), expected);
      }
      expect(
        find.descendant(
          of: find.byType(WorkoutScreen),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('notification navigation opens the requested workout week', (
    tester,
  ) async {
    final plan = populatedPlan();
    final sessions = [
      for (var week = 1; week <= 3; week++)
        WorkoutSession(
          id: 'notification-session-$week',
          planId: plan.id,
          planName: plan.name,
          date: DateTime(2026, 9, week),
          exercises: const [],
          weekNumber: week,
          isCompleted: week != 2,
          startedAt: week == 2 ? DateTime(2026, 9, 2, 10) : null,
          durationSeconds: week == 2 ? 90 : null,
        ),
    ];
    await tester.runAsync(() async {
      for (final session in sessions) {
        await Hive.box<WorkoutSession>(
          HiveService.sessionsBox,
        ).put(session.id, session);
      }
    });

    await tester.runAsync(() => hiveHarness.prepareTraining([plan]));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>.value(
            value: _PlanProvider([plan]),
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>(
            create: (_) => _SessionProvider(sessions),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
          home: WorkoutScreen(
            plan: plan,
            planIndex: 0,
            destination: WorkoutDestination.week(
              plan.id!,
              legacyTrainingWeekId(plan.splitId!, 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = tester.widget<TrainingBlockStrip>(
      find.byType(TrainingBlockStrip),
    );
    expect(
      strip.weeksByBlock.values
          .expand((weeks) => weeks)
          .firstWhere((week) => week.id == strip.selectedWeekId)
          .number,
      1,
    );
  });

  testWidgets('long workout title stays clear of the timer below it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);
    final plan = populatedPlan().copyWith(name: 'UPPER BODY');

    await tester.runAsync(() => hiveHarness.prepareTraining([plan]));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>.value(
            value: _PlanProvider([plan]),
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>(
            create: (_) => _SessionProvider(),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
          home: WorkoutScreen(plan: plan, planIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.text('UPPER BODY').first;
    final timer = find.byKey(const ValueKey('workout_elapsed_time'));
    // An untouched log has nothing to time, so the clock waits for Start.
    expect(timer, findsNothing);
    await tester.tap(find.text('Start'));
    await pumpWithStorage(tester);
    expect(timer, findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));

    expect(appBar.titleSpacing, AppSpacing.sm);
    expect(tester.getRect(title).overlaps(tester.getRect(timer)), isFalse);
    expect(
      tester.getRect(timer).top,
      greaterThanOrEqualTo(tester.getRect(title).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan color choices are selected and at least 48 square', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final data = populatedData();
    await pumpHome(tester, plans: [data.plan], sessions: [data.session]);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change color'));
    await tester.pumpAndSettle();
    final choices = find.bySemanticsLabel(
      RegExp('^(${kPlanColorNames.join('|')})\$'),
    );
    expect(choices, findsWidgets);
    for (final choice in choices.evaluate()) {
      expect(
        tester.getSize(find.byWidget(choice.widget)).width,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byWidget(choice.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('Rose')),
      matchesSemantics(
        label: 'Rose',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('compact and wide plan grids render without overflow', (
    tester,
  ) async {
    final data = populatedData();
    for (final size in [const Size(320, 700), const Size(1200, 800)]) {
      await pumpHome(
        tester,
        size: size,
        plans: [data.plan],
        sessions: [data.session],
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  List<WorkoutPlan> rotationPlans() => [
    populatedPlan(),
    populatedPlan().copyWith(
      id: 'plan-2',
      name: 'Pull Day',
      planColor: kPlanColors[3],
    ),
    populatedPlan().copyWith(
      id: 'plan-3',
      name: 'Leg Day',
      planColor: kPlanColors[6],
    ),
  ];

  WorkoutSession pullSession(DateTime date) => WorkoutSession(
    id: 'session-pull',
    planId: 'plan-2',
    planName: 'Pull Day',
    date: date,
    exercises: const [],
  );

  testWidgets('a single plan has a launcher and separate weekly activity', (
    tester,
  ) async {
    final data = populatedData();
    await pumpHome(
      tester,
      plans: [data.plan],
      sessions: [data.session.copyWith(date: DateTime.now())],
    );
    expect(find.text('Next up'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('1 workout · 0 sets'), findsOneWidget);
    expect(find.text('Last workout'), findsNothing);
    expect(find.text('Your plans'), findsOneWidget);
    expect(find.byTooltip('Plan actions'), findsNothing);
    expect(find.byTooltip('Drag to reorder Push Day'), findsNothing);
    await tester.ensureVisible(find.text('Manage'));
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Plan actions'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Plan actions'), findsNothing);
    expect(find.text('Start workout'), findsOneWidget);
  });

  testWidgets('a draft does not advance rotation or count as trained', (
    tester,
  ) async {
    final plans = rotationPlans();
    final draft = WorkoutSession(
      id: 'draft-pull',
      planId: plans[1].id,
      planName: plans[1].name,
      date: DateTime.now(),
      exercises: const [],
      isCompleted: false,
    );
    await pumpHome(tester, plans: plans, sessions: [draft]);

    expect(upNextMarker(tester).number, 1);
    expect(find.text('0 workouts'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsNothing);
  });

  testWidgets('an empty week leaves room for four of five plans on a phone', (
    tester,
  ) async {
    // A 412x915dp phone less what the emulator measures outside Home: a 24dp
    // status bar and a 92dp tab bar with gesture navigation.
    const size = Size(412, 915 - 24 - 92);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final plans = [
      for (var index = 0; index < 5; index++)
        populatedPlan().copyWith(
          id: 'plan-${index + 1}',
          name: 'Day ${index + 1}',
          planColor: kPlanColors[index],
        ),
    ];
    for (final brightness in Brightness.values) {
      await pumpHome(tester, size: size, brightness: brightness, plans: plans);
      await tester.pump();

      expect(find.text('0 workouts'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('weekly-training-link')),
        findsOneWidget,
      );
      // The week keeps its frame, and today its mark, before anything is
      // logged; the bars' slot stays closed to the baseline until then.
      expect(find.byKey(const ValueKey('training-day-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('training-day-today-dot')),
        findsOneWidget,
      );
      final fourth = find.byWidgetPredicate(
        (widget) => widget is HomePlanRow && widget.plan.id == 'plan-4',
      );
      expect(fourth, findsOneWidget);
      expect(
        tester.getRect(fourth).bottom,
        lessThanOrEqualTo(size.height),
        reason: '$brightness',
      );
    }
  });

  testWidgets('up next card and button open the plan after the last trained', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final plans = rotationPlans();
    await pumpHome(tester, plans: plans, sessions: [pullSession(yesterday)]);

    expect(find.text('Next up'), findsOneWidget);
    expect(upNextMarker(tester).number, 3);
    expect(upNextMarker(tester).count, 3);

    // Under the name the card says what the workout trains; the counts
    // stay on the plan's row.
    Finder inCard(Pattern text) => find.descendant(
      of: find.byType(UpNextCard),
      matching: find.textContaining(text),
    );
    expect(inCard(RegExp(r'^Chest, Shoulders$')), findsOneWidget);
    expect(inCard('exercises'), findsNothing);
    expect(inCard('sets'), findsNothing);

    // The bar draws every plan in its own colour; the one on offer only
    // stands taller.
    final card = tester.element(find.byType(UpNextCard));
    for (var index = 0; index < plans.length; index++) {
      final segment = find.byKey(ValueKey('rotation-segment-$index'));
      expect(
        (tester.widget<Container>(segment).decoration! as BoxDecoration).color,
        planColorOf(plans[index].planColor, card),
        reason: 'segment $index',
      );
      expect(
        tester.getSize(segment).height,
        index == 2 ? 6 : 2,
        reason: 'segment $index',
      );
    }
    // Status, bar and marker lock together: one top edge, one bottom edge.
    final marker = tester.getRect(
      find.descendant(
        of: find.byType(UpNextCard),
        matching: find.byType(PlanMarker),
      ),
    );
    expect(tester.getRect(find.text('Next up')).top, closeTo(marker.top, 0.01));
    expect(
      tester.getRect(find.byKey(const ValueKey('rotation-segment-2'))).bottom,
      closeTo(marker.bottom, 0.01),
    );

    // A screen reader and a keyboard meet the action once, on Start: the
    // card's own tap is for a pointer only.
    final semantics = tester.ensureSemantics();
    for (final label in ['Next up', 'Chest, Shoulders']) {
      final nodes = find.semantics.byLabel(RegExp(label)).evaluate();
      expect(nodes, isNotEmpty, reason: label);
      for (final node in nodes) {
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
          reason: label,
        );
      }
    }
    expect(
      find.semantics.byLabel('Start workout').evaluate().single
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    final focusable = FocusManager.instance.rootScope.descendants.where(
      (node) =>
          node.canRequestFocus &&
          node.context?.findAncestorWidgetOfExactType<UpNextCard>() != null,
    );
    expect(focusable, hasLength(1));

    // A tap anywhere on the card does what Start does; Start itself opens
    // the workout once.
    for (final target in [
      find.descendant(
        of: find.byType(UpNextCard),
        matching: find.text('Next up'),
      ),
      find.descendant(
        of: find.byType(UpNextCard),
        matching: find.text('Leg Day'),
      ),
      find.text('Start workout'),
    ]) {
      await tester.tap(target);
      await tester.pumpAndSettle();
      final opened = find.byType(WorkoutScreen, skipOffstage: false);
      expect(opened, findsOneWidget, reason: '$target');
      final workout = tester.widget<WorkoutScreen>(opened);
      expect(workout.plan.name, 'Leg Day');
      expect(workout.planIndex, 2);
      Navigator.of(tester.element(opened)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WorkoutScreen), findsNothing);
    }
  });

  testWidgets(
    'weekly activity exposes trained days without repeated status labels',
    (tester) async {
      await pumpHome(
        tester,
        plans: rotationPlans(),
        sessions: [pullSession(DateTime.now())],
      );
      expect(find.text('1 workout · 0 sets'), findsOneWidget);
      expect(find.text('Pull Day · Today'), findsNothing);
      expect(find.text('Not trained yet'), findsNothing);
      final day = DateTime.now().weekday - 1;
      expect(find.byKey(ValueKey('training-day-$day')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').contains(
                '1 workout, 0 sets, today',
              ),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Next'),
        150,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(find.text('Next'), findsOneWidget);
    },
  );

  testWidgets(
    'snapshot counts performed sets and excludes drafts and other weeks',
    (tester) async {
      final today = DateTime(2026, 9, 30);
      final plan = populatedPlan();
      final older = WorkoutSession(
        date: today.subtract(const Duration(days: 8)),
        planName: 'Leg Day',
        exercises: const [],
      );
      final completed = WorkoutSession(
        date: today,
        planId: plan.id,
        planName: plan.name,
        exercises: [
          Exercise(
            name: 'Bench Press',
            sets: [Set(reps: 8, weight: 50), Set(reps: 0, weight: 50)],
          ),
        ],
      );
      final draft = WorkoutSession(
        date: today.add(const Duration(hours: 1)),
        planName: 'Draft',
        exercises: [
          Exercise(name: 'Squat', sets: [Set(reps: 5, weight: 80)]),
        ],
        isCompleted: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
          home: Scaffold(
            body: TrainingSnapshot(
              plans: [plan],
              sessions: [draft, older, completed],
              now: today,
            ),
          ),
        ),
      );

      expect(find.text('1 workout · 1 set'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Wednesday: 1 workout, 1 set, today',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Draft'), findsNothing);
    },
  );

  testWidgets('snapshot fits the narrow side of the up next card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
              width: 254,
              child: TrainingSnapshot(
                plans: [populatedPlan()],
                sessions: [populatedData().session],
                onOpenWeeklyTraining: () {},
                onOpenLastWorkout: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('week strip fits all seven days on a 360 dp phone', (
    tester,
  ) async {
    await pumpHome(
      tester,
      size: const Size(360, 800),
      plans: rotationPlans(),
      sessions: [pullSession(DateTime.now())],
    );
    final snapshot = find.byType(TrainingSnapshot);
    expect(snapshot, findsOneWidget);
    expect(
      find.descendant(of: snapshot, matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(
      find.descendant(of: snapshot, matching: find.byType(Scrollbar)),
      findsNothing,
    );
    final bounds = tester.getRect(snapshot);
    // Home pads the list by 16 dp each side: 328 dp shared by seven days.
    expect(bounds.width, closeTo(360 - 2 * AppSpacing.lg, .01));
    for (var day = 0; day < 7; day++) {
      final cell = tester.getRect(find.byKey(ValueKey('training-day-$day')));
      expect(cell.left, greaterThanOrEqualTo(bounds.left - .01));
      expect(cell.right, lessThanOrEqualTo(bounds.right + .01));
      expect(cell.width, closeTo(bounds.width / 7, .01));
      expect(cell.height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getRect(find.byKey(const ValueKey('training-day-6'))).right,
      closeTo(bounds.right, .01),
    );
  });

  testWidgets('up next and plans fit every width, theme, and text size', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    for (final brightness in Brightness.values) {
      for (final size in [const Size(320, 700), const Size(1200, 800)]) {
        for (final scale in [1.0, 2.0]) {
          await pumpHome(
            tester,
            size: size,
            textScale: scale,
            brightness: brightness,
            plans: rotationPlans(),
            sessions: [pullSession(yesterday)],
          );
          await tester.pump();
          expect(find.text('Next up'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '$brightness $size ${scale}x',
          );
        }
      }
    }
  });

  group('PlanStat.nextInRotation', () {
    List<WorkoutSession> trained(Map<String, int> daysAgoByPlan) => [
      for (final entry in daysAgoByPlan.entries)
        WorkoutSession(
          planName: entry.key,
          date: DateTime.now().subtract(Duration(days: entry.value)),
          exercises: const [],
        ),
    ];

    int next(Map<String, int> daysAgoByPlan) {
      final plans = rotationPlans();
      final stats = PlanStat.compute(plans, trained(daysAgoByPlan));
      return PlanStat.nextInRotation(stats, plans.length);
    }

    test('starts at the first plan when nothing is trained', () {
      expect(next({}), 0);
    });

    test('follows whichever plan was trained last', () {
      expect(next({'Push Day': 1, 'Pull Day': 3}), 1);
      expect(next({'Push Day': 3, 'Pull Day': 1}), 2);
    });

    test('wraps from the last plan back to the first', () {
      expect(next({'Leg Day': 0}), 0);
    });

    test('uses plan ids after renames and with duplicate names', () {
      final plans = rotationPlans();
      final renamedSession = WorkoutSession(
        planId: plans[1].id,
        planName: 'Old Pull Day',
        date: DateTime(2026, 9, 29),
        exercises: const [],
      );
      final duplicateName = plans[0].copyWith(name: plans[1].name);
      final stats = PlanStat.compute(
        [duplicateName, plans[1], plans[2]],
        [renamedSession],
      );

      expect(stats.singleWhere((stat) => stat.planIndex == 0).sessionCount, 0);
      expect(stats.singleWhere((stat) => stat.planIndex == 1).sessionCount, 1);
      expect(PlanStat.nextInRotation(stats, 3), 2);
    });

    test('falls back to names for sessions without plan ids', () {
      final stats = PlanStat.compute(rotationPlans(), trained({'Pull Day': 0}));
      expect(PlanStat.nextInRotation(stats, 3), 2);
    });
  });

  group('formatDaysAgo', () {
    final now = DateTime(2026, 9, 26, 9);

    test('reads in sentence case at every range', () {
      expect(formatDaysAgo(DateTime(2026, 9, 26, 7), now: now), 'Today');
      expect(formatDaysAgo(DateTime(2026, 9, 25, 23), now: now), 'Yesterday');
      expect(formatDaysAgo(DateTime(2026, 9, 21), now: now), '5 days ago');
      expect(formatDaysAgo(DateTime(2026, 9, 5), now: now), '3 weeks ago');
      expect(formatDaysAgo(DateTime(2026, 6, 1), now: now), '3 months ago');
    });

    test('a daylight saving change does not lose a day', () {
      // Europe's clocks go forward overnight here, so in those time zones the
      // two local midnights are 23 hours apart.
      final after = DateTime(2026, 3, 30);
      expect(formatDaysAgo(DateTime(2026, 3, 29), now: after), 'Yesterday');
    });
  });

  group('titleCase', () {
    test('raises the first letter of each word and keeps the rest', () {
      expect(titleCase('push day'), 'Push Day');
      expect(titleCase('PPL plan'), 'PPL Plan');
      expect(titleCase('RDL focus'), 'RDL Focus');
      expect(titleCase('upper body (heavy week)'), 'Upper Body (Heavy Week)');
      expect(titleCase('5x5 day'), '5x5 Day');
      expect(titleCase('  spaced   out  '), 'Spaced Out');
    });
  });

  test('countOf is singular only for one', () {
    expect(countOf(1, 'set'), '1 set');
    expect(countOf(0, 'set'), '0 sets');
    expect(countOf(3, 'exercise'), '3 exercises');
  });

  testWidgets('a tap in Manage opens the plan actions, not a workout', (
    tester,
  ) async {
    await pumpHome(tester, plans: rotationPlans());
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull Day').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Edit plan'), findsOneWidget);
  });

  testWidgets('rows are flat and say which plan is next and which are done', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(
      tester,
      size: const Size(390, 1400),
      plans: rotationPlans(),
      sessions: [pullSession(DateTime.now())],
    );
    HomePlanRow row(String name) => tester.widget<HomePlanRow>(
      find.byWidgetPredicate(
        (widget) => widget is HomePlanRow && widget.plan.name == name,
      ),
    );
    expect(row('Push Day').status, HomePlanStatus.none);
    expect(row('Pull Day').status, HomePlanStatus.done);
    expect(row('Leg Day').status, HomePlanStatus.next);
    expect(find.bySemanticsLabel(RegExp('Done this week')), findsOneWidget);
    // The launcher is the one raised card; no row lifts into a second.
    for (final card in tester.widgetList<RaisedCard>(
      find.descendant(
        of: find.byType(HomePlanRow),
        matching: find.byType(RaisedCard),
      ),
    )) {
      expect(card.raised, isFalse);
    }
    semantics.dispose();
  });

  testWidgets('large text wraps between phrases and keeps the brand whole', (
    tester,
  ) async {
    // The test font's glyphs are square and wide, so 150% here stands in
    // for the 200% a real phone reaches before a phrase outgrows a line.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    await pumpHome(
      tester,
      size: const Size(390, 1600),
      textScale: 1.5,
      plans: rotationPlans(),
    );
    final push = find.byWidgetPredicate(
      (widget) => widget is HomePlanRow && widget.plan.name == 'Push Day',
    );
    final sets = find.descendant(
      of: push,
      matching: find.textContaining(' set'),
    );
    final dot = find.descendant(of: push, matching: find.text(' · ')).first;
    // The set count is its own phrase on one line, never split from its unit
    // across a break the way one run of text wrapped.
    expect(sets, findsOneWidget);
    expect(
      tester.getSize(sets).height,
      closeTo(tester.getSize(dot).height, 0.5),
    );
    // The wordmark shrinks to its share of the header rather than clipping.
    final brand = find.ancestor(
      of: find.byType(AppWordmark),
      matching: find.byType(FittedBox),
    );
    expect(brand, findsOneWidget);
    expect(tester.getSize(brand).width, lessThanOrEqualTo(390 * 0.4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the play glyph gives way to the details at large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.reset);
    Finder glyph() => find.descendant(
      of: find.byType(HomePlanRow),
      matching: find.byIcon(LucideIcons.play),
    );
    await pumpHome(tester, size: const Size(390, 1400), plans: rotationPlans());
    expect(glyph(), findsNWidgets(3));
    await pumpHome(
      tester,
      size: const Size(390, 1400),
      textScale: 2,
      plans: rotationPlans(),
    );
    expect(find.byType(HomePlanRow), findsNWidgets(3));
    expect(glyph(), findsNothing);
  });

  testWidgets('a tablet keeps Home to a readable column', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 1180);
    addTearDown(tester.view.reset);
    await pumpHome(tester, size: const Size(820, 1180), plans: rotationPlans());
    final card = tester.getRect(find.byType(UpNextCard));
    expect(card.width, lessThanOrEqualTo(680));
    expect(card.center.dx, closeTo(410, 1));
    // The header is capped the same way, so the wordmark lines up with the
    // launcher instead of sitting a padding's width to its left.
    expect(
      tester.getTopLeft(find.byType(AppWordmark)).dx,
      closeTo(card.left, 1),
    );
  });

  testWidgets('the in-progress row opens the live workout, as Resume does', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.reset);
    final plans = rotationPlans();
    final now = DateTime.now();
    // Paused twenty minutes ago, so it is live without a ticking clock.
    final live = WorkoutSession(
      id: 'live-pull',
      planId: plans[1].id,
      planName: plans[1].name,
      date: now.subtract(const Duration(minutes: 20)),
      startedAt: now.subtract(const Duration(minutes: 20)),
      durationSeconds: 600,
      isCompleted: false,
      exercises: const [],
    );
    await pumpHome(
      tester,
      size: const Size(390, 1400),
      plans: plans,
      sessions: [live],
    );
    await tester.pumpAndSettle();

    Finder openedScreen() {
      final workout = find.byType(WorkoutScreen);
      return workout.evaluate().isNotEmpty
          ? workout
          : find.byType(WorkoutDetailsScreen);
    }

    String opened() {
      final screen = tester.widget(openedScreen());
      return screen is WorkoutScreen
          ? 'workout:${screen.destination?.navigationKey}'
          : 'details:${(screen as WorkoutDetailsScreen).sessionIdentity}';
    }

    Future<void> back() async {
      Navigator.of(tester.element(openedScreen())).pop();
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Resume workout'));
    await tester.pumpAndSettle();
    final viaResume = opened();
    expect(viaResume, contains('live-pull'));
    await back();

    final row = find.byWidgetPredicate(
      (widget) =>
          widget is HomePlanRow && widget.status == HomePlanStatus.inProgress,
    );
    expect(tester.widget<HomePlanRow>(row).plan.id, plans[1].id);
    await tester.tap(find.descendant(of: row, matching: find.text('Pull Day')));
    await tester.pumpAndSettle();
    expect(opened(), viaResume);
    await back();
  });
}

class _PlanProvider extends WorkoutPlanProvider {
  _PlanProvider(this.values);
  List<WorkoutPlan> values;

  void replacePlans(List<WorkoutPlan> plans) {
    values = plans;
    notifyListeners();
  }

  @override
  List<WorkoutPlan> get plans => values;

  @override
  Future<void> reorderPlans(int oldIndex, int newIndex) async {
    final reordered = List<WorkoutPlan>.of(values);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    replacePlans(reordered);
  }
}

class _SessionProvider extends WorkoutSessionProvider {
  _SessionProvider([this.values = const []]);
  final List<WorkoutSession> values;
  @override
  List<WorkoutSession> get sessions => values;

  // These tests exercise navigation and layout; real writes are covered by
  // workout_entry_test and controlled failures by async_mutation_feedback_test.
  @override
  Future<void> upsertSession(WorkoutSession session) async {}
}
