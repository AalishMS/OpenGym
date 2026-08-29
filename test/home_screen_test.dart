import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    hiveDirectory = await Directory.systemTemp.createTemp('opengym_home_test_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  Widget homeHost({
    Size size = const Size(390, 800),
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
        theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
        navigatorObservers: observers,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: MediaQueryData(size: size),
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
    await tester.pumpWidget(homeHost());

    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    expect(
      find.descendant(of: fab, matching: find.byIcon(Icons.add)),
      findsNothing,
    );
    expect(
      find.descendant(of: fab, matching: find.byIcon(LucideIcons.plus)),
      findsOneWidget,
    );
    expect(find.text('[+ NEW PLAN]'), findsNothing);
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
    expect(find.textContaining('Last trained yesterday'), findsOneWidget);
    expect(find.textContaining('Bench Press'), findsOneWidget);
    expect(find.textContaining('Overhead Press'), findsOneWidget);
    expect(find.textContaining('Cable Fly'), findsOneWidget);
    expect(find.text('[START]'), findsNothing);
    expect(find.byTooltip('Plan actions'), findsOneWidget);
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
      'CHANGE COLOR',
      'DUPLICATE PLAN',
      'EDIT PLAN',
      'DELETE PLAN',
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
    expect(find.text('CHANGE COLOR'), findsOneWidget);
  });

  testWidgets('workout app bar title uses the active plan color', (
    tester,
  ) async {
    final plan = populatedPlan();
    await tester.pumpWidget(homeHost(plans: [plan]));

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
    expect(title.style?.color, planColorOf(plan.planColor, context));
  });

  testWidgets(
    'workout add exercise is not draggable and has a 48 pixel target',
    (tester) async {
      final plan = populatedPlan();
      await tester.pumpWidget(homeHost(plans: [plan]));
      await tester.tap(find.text('Push Day'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
      await tester.pumpAndSettle();

      final addTile = find.text('[+ ADD EXERCISE]');
      expect(
        find.ancestor(
          of: addTile,
          matching: find.byType(ReorderableDelayedDragStartListener),
        ),
        findsNothing,
      );
      final target = find.ancestor(of: addTile, matching: find.byType(InkWell));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    },
  );

  testWidgets('workout reorder items use stable object identity keys', (
    tester,
  ) async {
    final plan = populatedPlan();
    await tester.pumpWidget(homeHost(plans: [plan]));
    await tester.tap(find.text('Push Day'));
    await tester.pumpAndSettle();

    final dragItems =
        tester
            .widgetList<ReorderableDelayedDragStartListener>(
              find.byType(ReorderableDelayedDragStartListener),
            )
            .toList();
    expect(dragItems, isNotEmpty);
    expect(dragItems.every((item) => item.key is ObjectKey), isTrue);
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
    await tester.tap(find.text('CHANGE COLOR'));
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
}

class _SessionProvider extends WorkoutSessionProvider {
  _SessionProvider([this.values = const []]);
  final List<WorkoutSession> values;
  @override
  List<WorkoutSession> get sessions => values;
}
