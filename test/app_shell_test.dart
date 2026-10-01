import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/providers/progression_provider.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/breakpoints.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';
import 'package:gymapp/widgets/app_nav_rail.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    hiveDirectory = await Directory.systemTemp.createTemp(
      'opengym_shell_test_',
    );
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

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  Future<void> seedHomeTraining() async {
    final plan = WorkoutPlan(
      id: 'shell-plan',
      name: 'Push Day',
      exercises: [ExerciseTemplate(name: 'Bench Press', sets: 1)],
    );
    final session = WorkoutSession(
      id: 'shell-session',
      planId: plan.id,
      planName: plan.name,
      date: DateTime.now(),
      exercises: [
        Exercise(name: 'Bench Press', sets: [Set(reps: 8, weight: 50)]),
      ],
    );
    await Hive.box<WorkoutPlan>(HiveService.plansBox).put(plan.id, plan);
    await Hive.box<WorkoutSession>(
      HiveService.sessionsBox,
    ).put(session.id, session);
  }

  Widget shellHost(double width, {double textScale = 1}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
        ChangeNotifierProvider(create: (_) => ProgressionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF00A2FF), Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const AppShell(),
        ),
      ),
    );
  }

  Widget bottomNavHost({double textScale = 1}) {
    return MaterialApp(
      theme: buildTheme(const Color(0xFF00A2FF), Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: (_) {}),
        ),
      ),
    );
  }

  testWidgets('compact shell exposes four phone destinations', (tester) async {
    await tester.pumpWidget(shellHost(Breakpoints.medium - 1));
    await tester.pumpAndSettle();

    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.byType(AppNavRail), findsNothing);
    for (final label in ['Plans', 'History', 'Stats', 'Settings']) {
      expect(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('both snapshot metrics open weekly training statistics', (
    tester,
  ) async {
    await tester.runAsync(seedHomeTraining);
    await tester.pumpWidget(shellHost(390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final snapshot = find.byType(TrainingSnapshot);
    await tester.tap(
      find.descendant(of: snapshot, matching: find.text('workout')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text('Weekly training'), findsOneWidget);
    expect(find.text('All exercises'), findsOneWidget);
    expect(
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
      2,
    );
    final statsScroll =
        tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('statistics-scroll')),
            )
            .controller!;
    statsScroll.jumpTo(300);
    await tester.pump();
    expect(statsScroll.offset, greaterThan(0));

    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Plans'),
      ),
    );
    await tester.pump();
    await tester.tap(find.descendant(of: snapshot, matching: find.text('set')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Weekly training'), findsOneWidget);
    expect(statsScroll.offset, 0);
    expect(
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
      2,
    );
  });

  testWidgets('last workout opens its History detail and returns to History', (
    tester,
  ) async {
    await tester.runAsync(seedHomeTraining);
    await tester.pumpWidget(shellHost(390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.descendant(
        of: find.byType(TrainingSnapshot),
        matching: find.text('Push Day · Today'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutDetailsScreen), findsOneWidget);
    expect(find.text('Bench Press'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
      1,
    );
  });

  testWidgets('medium shell exposes the desktop rail and dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(shellHost(Breakpoints.medium));
    await tester.pumpAndSettle();

    expect(find.byType(AppNavRail), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppNavRail),
        matching: find.text('Dashboard'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('active destinations expose selected semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(bottomNavHost());
    expect(
      tester.getSemantics(find.text('Plans')),
      matchesSemantics(
        label: 'Plans',
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.pumpWidget(shellHost(Breakpoints.medium));
    await tester.pumpAndSettle();
    final dashboardDestination = find.descendant(
      of: find.byType(AppNavRail),
      matching: find.text('Dashboard'),
    );
    expect(
      tester.getSemantics(dashboardDestination),
      matchesSemantics(
        label: 'Dashboard',
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    semantics.dispose();
  });

  testWidgets('selected destination uses restrained accent emphasis', (
    tester,
  ) async {
    await tester.pumpWidget(bottomNavHost());
    final context = tester.element(find.byType(AppBottomNav));
    final selected = tester.widget<Text>(find.text('Plans')).style!;
    final unselected = tester.widget<Text>(find.text('History')).style!;

    expect(selected.color, accentColor(context));
    expect(selected.fontWeight, FontWeight.w700);
    expect(unselected.color, textSecondaryColor(context));
    expect(unselected.fontWeight, FontWeight.w500);
  });

  testWidgets('every navigation destination is at least 48 pixels high', (
    tester,
  ) async {
    await tester.pumpWidget(bottomNavHost());
    for (final inkWell in find.byType(InkWell).evaluate()) {
      expect(
        tester.getSize(find.byWidget(inkWell.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }

    await tester.pumpWidget(shellHost(Breakpoints.medium));
    await tester.pumpAndSettle();
    final rail = find.byType(AppNavRail);
    for (final inkWell
        in find
            .descendant(of: rail, matching: find.byType(InkWell))
            .evaluate()) {
      expect(
        tester.getSize(find.byWidget(inkWell.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('compact bottom destinations are at least 48 pixels wide', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(bottomNavHost());

    for (final inkWell in find.byType(InkWell).evaluate()) {
      final size = tester.getSize(find.byWidget(inkWell.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('compact navigation does not overflow at 2x text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(bottomNavHost(textScale: 2));
    await tester.pump();

    expect(tester.view.physicalSize.width, 320);
    expect(tester.takeException(), isNull);
  });
}
