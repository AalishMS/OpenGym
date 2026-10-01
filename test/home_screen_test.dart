import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';

import 'support/hive_test_harness.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/spacing.dart';
import 'package:gymapp/utils/format.dart';
import 'package:gymapp/utils/plan_stats.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';
import 'package:gymapp/widgets/underline_tab_strip.dart';

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
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

  testWidgets('plan card exposes only its overflow action', (tester) async {
    final data = populatedData();
    await tester.pumpWidget(
      homeHost(plans: [data.plan], sessions: [data.session]),
    );
    expect(find.text('[START]'), findsNothing);
    final size = tester.getSize(find.byTooltip('Plan actions'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('create plan action is a compact bottom-right plus button', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(homeHost(brightness: brightness));

      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      expect(
        tester.widget<FloatingActionButton>(fab).backgroundColor,
        surfaceColor(tester.element(find.byType(HomeScreen))),
      );
      expect(
        find.descendant(of: fab, matching: find.byIcon(Icons.add)),
        findsNothing,
      );
      expect(
        find.descendant(of: fab, matching: find.byIcon(LucideIcons.plus)),
        findsOneWidget,
      );
      expect(find.text('[+ NEW PLAN]'), findsNothing);
    }
  });

  testWidgets('plan overflow hit region stays inside the card', (tester) async {
    final data = populatedData();
    await tester.pumpWidget(
      homeHost(plans: [data.plan], sessions: [data.session]),
    );

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
    await tester.pumpWidget(
      homeHost(plans: [data.plan], sessions: [data.session]),
    );
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
    await tester.pumpWidget(
      homeHost(size: const Size(1200, 800), plans: plans),
    );

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
    await tester.pumpWidget(homeHost(plans: plans));
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
    await tester.pumpWidget(homeHost(plans: [plan]));

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
    await tester.pumpWidget(
      homeHost(plans: [data.plan], sessions: [data.session]),
    );
    await tester.tap(find.byTooltip('Plan actions'));
    await tester.pumpAndSettle();
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

  testWidgets('card tap opens Workout and long press opens plan actions', (
    tester,
  ) async {
    final data = populatedData();
    await tester.pumpWidget(
      homeHost(plans: [data.plan], sessions: [data.session]),
    );
    await tester.tap(find.text('Push Day'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(WorkoutScreen))).pop();
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Push Day'));
    await tester.pumpAndSettle();
    expect(find.text('Change color'), findsOneWidget);
  });

  testWidgets('plan color is limited to identity markers', (tester) async {
    final plan = populatedPlan();
    await tester.pumpWidget(homeHost(plans: [plan]));

    final homeContext = tester.element(find.byType(HomeScreen));
    final expectedHomeColor = planColorOf(plan.planColor, homeContext);
    final homeMarker = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Push Day plan marker',
    );
    expect(homeMarker, findsOneWidget);
    final homeMarkerContainer = tester.widget<Container>(
      find.descendant(of: homeMarker, matching: find.byType(Container)),
    );
    expect(
      (homeMarkerContainer.decoration! as BoxDecoration).color,
      expectedHomeColor,
    );

    await tester.tap(find.text('Push Day'));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'PUSH DAY' &&
            widget.style?.fontSize == 14,
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

  testWidgets(
    'workout add exercise uses the card surface and has a 48 pixel target',
    (tester) async {
      for (final brightness in Brightness.values) {
        final plan = populatedPlan();
        await tester.pumpWidget(
          homeHost(brightness: brightness, plans: [plan]),
        );
        await tester.tap(find.text('Push Day'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -1000),
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
        final target = find.ancestor(
          of: addTile,
          matching: find.byType(InkWell),
        );
        final container = tester.widget<Container>(
          find.descendant(of: target, matching: find.byType(Container)).first,
        );
        expect(
          (container.decoration! as BoxDecoration).color,
          surfaceColor(tester.element(find.byType(WorkoutScreen))),
        );
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      }
    },
  );

  testWidgets('workout drag handles reorder exercises', (tester) async {
    final plan = populatedPlan();
    await tester.pumpWidget(homeHost(plans: [plan]));
    await tester.tap(find.text('Push Day'));
    await tester.pumpAndSettle();

    final handle = find.byTooltip('Drag to reorder Bench Press');
    expect(handle, findsOneWidget);
    final dragItems = find.byWidgetPredicate(
      (widget) => widget is Container && widget.key is ObjectKey,
    );
    expect(dragItems, findsWidgets);

    await tester.drag(handle, const Offset(0, 220));
    await tester.pumpAndSettle();
    final reordered = tester.widgetList<ExerciseCard>(
      find.byType(ExerciseCard),
    );
    expect(reordered.first.exercise.name, 'Overhead Press');

    // The final slot follows the non-draggable Add exercise tile.
    tester
        .widget<SliverReorderableList>(find.byType(SliverReorderableList))
        .onReorderItem!(0, plan.exercises.length);
    await tester.pumpAndSettle();
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
            widget.data == 'PULL DAY' &&
            widget.style?.fontSize == 14,
      ),
      const Offset(100, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'LEG DAY' &&
            widget.style?.fontSize == 14,
      ),
      findsOneWidget,
    );
  });

  testWidgets('week swipe continues across consecutive completed sessions', (
    tester,
  ) async {
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

    int selectedWeek() =>
        tester
            .widget<UnderlineTabStrip>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is UnderlineTabStrip && widget.rule == StripRule.top,
              ),
            )
            .selectedIndex;

    expect(selectedWeek(), 2);
    for (final expected in [1, 0]) {
      await tester.flingFrom(
        const Offset(200, 330),
        const Offset(100, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(selectedWeek(), expected);
    }
    for (final expected in [1, 2]) {
      await tester.flingFrom(
        const Offset(200, 330),
        const Offset(-100, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(selectedWeek(), expected);
    }
  });

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
          home: WorkoutScreen(plan: plan, planIndex: 0, initialWeekNumber: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabs = tester.widget<UnderlineTabStrip>(
      find.byWidgetPredicate(
        (widget) => widget is UnderlineTabStrip && widget.rule == StripRule.top,
      ),
    );
    expect(tabs.selectedIndex, 0);
  });

  testWidgets('long workout title stays clear of the centered timer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);
    final plan = populatedPlan().copyWith(name: 'UPPER BODY');

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
    final appBar = tester.widget<AppBar>(find.byType(AppBar));

    expect(appBar.titleSpacing, AppSpacing.sm);
    expect(
      tester.getRect(title).right + AppSpacing.sm,
      lessThanOrEqualTo(tester.getRect(timer).left),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan color choices are selected and at least 48 square', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final data = populatedData();
    await tester.pumpWidget(
      homeHost(plans: [data.plan], sessions: [data.session]),
    );
    await tester.tap(find.byTooltip('Plan actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change color'));
    await tester.pumpAndSettle();
    final choices = find.bySemanticsLabel(RegExp(r'^Plan color \d+$'));
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
      tester.getSemantics(find.bySemanticsLabel('Plan color 1')),
      matchesSemantics(
        label: 'Plan color 1',
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
      await tester.pumpWidget(
        homeHost(size: size, plans: [data.plan], sessions: [data.session]),
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

  testWidgets('a single plan shows training without an up next card', (
    tester,
  ) async {
    final data = populatedData();
    await tester.pumpWidget(
      homeHost(
        plans: [data.plan],
        sessions: [data.session.copyWith(date: DateTime.now())],
      ),
    );
    expect(find.text('Up next'), findsNothing);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('workout'), findsOneWidget);
    expect(find.text('Last workout'), findsOneWidget);
    expect(find.text('Your plans'), findsOneWidget);
    expect(tester.getSize(find.byType(TrainingSnapshot)).height, lessThan(130));
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
    await tester.pumpWidget(homeHost(plans: plans, sessions: [draft]));

    expect(find.text('Day 1 of 3'), findsOneWidget);
    expect(find.text('No workouts logged yet'), findsOneWidget);
    expect(find.text('workouts'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsNothing);
  });

  testWidgets('up next starts the plan after the last one trained', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await tester.pumpWidget(
      homeHost(plans: rotationPlans(), sessions: [pullSession(yesterday)]),
    );

    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Day 3 of 3'), findsOneWidget);

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    final workout = tester.widget<WorkoutScreen>(find.byType(WorkoutScreen));
    expect(workout.plan.name, 'Leg Day');
    expect(workout.planIndex, 2);
  });

  testWidgets('snapshot and cards mark what was trained this week', (
    tester,
  ) async {
    await tester.pumpWidget(
      homeHost(plans: rotationPlans(), sessions: [pullSession(DateTime.now())]),
    );

    expect(find.text('workout'), findsOneWidget);
    expect(find.text('Pull Day · Today'), findsOneWidget);
    // Only the Pull Day card is done this week, and says when.
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets(
    'snapshot counts performed sets and uses the latest completed session',
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

      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('workout'), findsOneWidget);
      expect(find.text('set'), findsOneWidget);
      expect(find.text('Push Day · Today'), findsOneWidget);
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

  testWidgets('up next and plans fit every width, theme, and text size', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    for (final brightness in Brightness.values) {
      for (final size in [const Size(320, 700), const Size(1200, 800)]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            homeHost(
              size: size,
              textScale: scale,
              brightness: brightness,
              plans: rotationPlans(),
              sessions: [pullSession(yesterday)],
            ),
          );
          await tester.pump();
          expect(find.text('Up next'), findsOneWidget);
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
}
