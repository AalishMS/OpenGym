import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/settings_screen.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/hive_service.dart';

import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';

import 'support/hive_test_harness.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/breakpoints.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';
import 'package:gymapp/widgets/app_nav_rail.dart';
import 'package:gymapp/widgets/home/training_snapshot.dart';

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  Future<void> seedHomeTraining({bool withLastWeek = false}) async {
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
    if (!withLastWeek) return;
    final earlier = WorkoutSession(
      id: 'shell-session-last-week',
      planId: plan.id,
      planName: plan.name,
      date: DateTime.now().subtract(const Duration(days: 7)),
      exercises: [
        Exercise(name: 'Bench Press', sets: [Set(reps: 8, weight: 40)]),
      ],
    );
    await Hive.box<WorkoutSession>(
      HiveService.sessionsBox,
    ).put(earlier.id, earlier);
  }

  Widget shellHost(double width, {double textScale = 1}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
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

  testWidgets('leaving or reselecting Home clears Manage', (tester) async {
    await tester.runAsync(seedHomeTraining);
    await tester.pumpWidget(shellHost(390));
    await tester.pumpAndSettle();
    Future<void> tab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tab('Home');
    expect(find.text('Manage'), findsOneWidget);
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tab('History');
    await tab('Home');
    expect(find.text('Manage'), findsOneWidget);
  });

  for (final label in ['History', 'Stats', 'Settings']) {
    testWidgets('system Back from $label returns to normal Home', (
      tester,
    ) async {
      await tester.runAsync(seedHomeTraining);
      await tester.pumpWidget(shellHost(390));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
        0,
      );
      expect(find.text('Manage'), findsOneWidget);
      expect(find.text('Start workout'), findsOneWidget);
    });
  }

  testWidgets('compact shell exposes four phone destinations', (tester) async {
    await tester.pumpWidget(shellHost(Breakpoints.medium - 1));
    await tester.pumpAndSettle();

    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.byType(AppNavRail), findsNothing);
    for (final label in ['Home', 'History', 'Stats', 'Settings']) {
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

  testWidgets('horizontal swipes navigate all phone tabs without wrapping', (
    tester,
  ) async {
    await tester.pumpWidget(shellHost(390));
    await tester.pumpAndSettle();

    int selectedTab() =>
        tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex;

    Future<void> swipe(double dx) async {
      await tester.dragFrom(
        tester.getCenter(find.byType(AppShell)),
        Offset(dx, 0),
      );
      await tester.pumpAndSettle();
    }

    await swipe(250);
    expect(selectedTab(), 0);
    for (var index = 1; index <= 3; index++) {
      await swipe(-250);
      expect(selectedTab(), index);
    }
    await swipe(-250);
    expect(selectedTab(), 3);
    for (var index = 2; index >= 0; index--) {
      await swipe(250);
      expect(selectedTab(), index);
    }

    // A tab tap and Back must still work after gesture navigation.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Stats'),
      ),
    );
    await tester.pumpAndSettle();
    expect(selectedTab(), 2);
    await swipe(250);
    expect(selectedTab(), 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(selectedTab(), 0);
  });

  testWidgets('vertical and short drags keep Home; swiping clears Manage', (
    tester,
  ) async {
    await tester.runAsync(seedHomeTraining);
    await tester.pumpWidget(shellHost(390));
    await tester.pumpAndSettle();
    final start = tester.getCenter(find.byType(AppShell));

    await tester.dragFrom(start, const Offset(-25, -200));
    await tester.pumpAndSettle();
    // Diagonal scrolls that lean sideways must not switch tabs, whichever
    // axis the finger moves along first.
    for (final diagonal in const [
      Offset(-150, -120),
      Offset(-150, 100),
      Offset(150, -90),
    ]) {
      await tester.dragFrom(start, diagonal);
      await tester.pumpAndSettle();
    }
    final sideways = TestPointer(7);
    await tester.sendEventToBinding(sideways.down(start));
    await tester.sendEventToBinding(
      sideways.move(start + const Offset(-30, 0)),
    );
    await tester.sendEventToBinding(
      sideways.move(start + const Offset(-160, -140)),
    );
    await tester.sendEventToBinding(sideways.up());
    await tester.pumpAndSettle();
    await tester.timedDragFrom(
      start,
      const Offset(-45, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
      0,
    );

    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.dragFrom(start, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
      1,
    );
    await tester.dragFrom(start, const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Manage'), findsOneWidget);
  });

  testWidgets(
    'weekly summary opens statistics and resets its scroll on each visit',
    (tester) async {
      await tester.runAsync(() => seedHomeTraining(withLastWeek: true));
      await tester.pumpWidget(shellHost(390));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final snapshot = find.byType(TrainingSnapshot);
      await tester.tap(
        find.descendant(
          of: snapshot,
          matching: find.byKey(const ValueKey('weekly-training-link')),
        ),
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
          matching: find.text('Home'),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: snapshot,
          matching: find.byKey(const ValueKey('weekly-training-link')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Weekly training'), findsOneWidget);
      expect(statsScroll.offset, 0);
      expect(
        tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
        2,
      );
      // The shortcut opens the week in progress…
      expect(find.textContaining('This week  /'), findsOneWidget);

      // …but an ordinary visit to Stats returns to the last complete week.
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text('Home'),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text('Stats'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Last week  /'), findsOneWidget);
      expect(find.textContaining('This week  /'), findsNothing);
    },
  );

  testWidgets('the Stats tab reopens at the top after another tab', (
    tester,
  ) async {
    await tester.runAsync(seedHomeTraining);
    await tester.pumpWidget(shellHost(390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> openTab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openTab('Stats');
    final statsScroll =
        tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('statistics-scroll')),
            )
            .controller!;
    statsScroll.jumpTo(300);
    await tester.pump();
    expect(statsScroll.offset, greaterThan(0));

    await openTab('History');
    await openTab('Stats');
    expect(statsScroll.offset, 0);
  });

  testWidgets('tapping the tab that is showing scrolls it to the top', (
    tester,
  ) async {
    await tester.runAsync(seedHomeTraining);
    await tester.pumpWidget(shellHost(390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> openTab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await openTab('Stats');
    final statsScroll =
        tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('statistics-scroll')),
            )
            .controller!;
    statsScroll.jumpTo(300);
    await tester.pump();
    await openTab('Stats');
    expect(statsScroll.offset, 0);

    await openTab('Settings');
    final settingsScroll =
        tester
            .widget<SingleChildScrollView>(
              find
                  .descendant(
                    of: find.byType(SettingsScreen),
                    matching: find.byType(SingleChildScrollView),
                  )
                  .first,
            )
            .controller!;
    settingsScroll.jumpTo(200);
    await tester.pump();
    expect(settingsScroll.offset, greaterThan(0));
    await openTab('Settings');
    expect(settingsScroll.offset, 0);
  });

  testWidgets('changing tabs gives a selection click, reselecting does not', (
    tester,
  ) async {
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
    await tester.pumpWidget(shellHost(390));
    await tester.pump();

    Future<void> openTab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openTab('History');
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    await openTab('History');
    expect(haptics, hasLength(1));
  });

  testWidgets('the selected tab is marked by a rule, not colour alone', (
    tester,
  ) async {
    Alignment indicatorAt() => (tester
                .widget<AnimatedAlign>(
                  find.byKey(const ValueKey('bottom-nav-indicator')),
                )
                .alignment
            as AlignmentDirectional)
        .resolve(TextDirection.ltr);

    await tester.pumpWidget(shellHost(390));
    await tester.pump();
    expect(indicatorAt().x, -1);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text('Settings'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(indicatorAt().x, 1);
  });

  group('workout in progress strip', () {
    Future<void> seedLive({
      required bool running,
      Duration startedAgo = const Duration(minutes: 20),
    }) async {
      final now = DateTime.now();
      final session = WorkoutSession(
        id: 'live-session',
        planName: 'Leg Day',
        date: now.subtract(startedAgo),
        startedAt: now.subtract(startedAgo),
        isCompleted: false,
        timerStartedAt:
            running ? now.subtract(const Duration(minutes: 5)) : null,
        durationSeconds: 600,
        exercises: [
          Exercise(name: 'Squat', sets: [Set(reps: 5, weight: 100)]),
        ],
      );
      await Hive.box<WorkoutSession>(
        HiveService.sessionsBox,
      ).put(session.id, session);
    }

    final strip = find.byKey(const ValueKey('active-workout-bar'));

    testWidgets('shows a running workout above the bar and ticks', (
      tester,
    ) async {
      // Real time passes below, so the shell's native timer restore runs.
      const timerChannel = MethodChannel(
        'com.aalishms.opengym/workout_timer_notification',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        timerChannel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          timerChannel,
          null,
        ),
      );
      await tester.runAsync(() => seedLive(running: true));
      await tester.pumpWidget(shellHost(390));
      await tester.pump();

      expect(strip, findsOneWidget);
      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('Workout in progress'), findsOneWidget);
      expect(
        tester.getBottomLeft(strip).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(AppBottomNav)).dy),
      );
      String clock() =>
          tester.widget<Text>(find.textContaining(RegExp(r'^15:0\d$'))).data!;
      final before = clock();
      // The clock reads wall time, so let real time pass, then the ticker.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(clock(), isNot(before));
    });

    testWidgets('a recent paused workout shows as paused', (tester) async {
      await tester.runAsync(() => seedLive(running: false));
      await tester.pumpWidget(shellHost(390));
      await tester.pump();

      expect(find.text('Workout paused'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('a paused workout left for days is not shown', (tester) async {
      await tester.runAsync(
        () => seedLive(running: false, startedAgo: const Duration(days: 3)),
      );
      await tester.pumpWidget(shellHost(390));
      await tester.pump();

      expect(strip, findsNothing);
    });

    testWidgets('disappears once the workout is finished', (tester) async {
      await tester.runAsync(() => seedLive(running: true));
      await tester.pumpWidget(shellHost(390));
      await tester.pump();
      expect(strip, findsOneWidget);

      await tester.runAsync(() async {
        final box = Hive.box<WorkoutSession>(HiveService.sessionsBox);
        await box.put(
          'live-session',
          box
              .get('live-session')!
              .copyWith(isCompleted: true, timerStartedAt: null),
        );
      });
      await tester.pump();
      expect(strip, findsNothing);
    });

    testWidgets('sits under the content on the desktop rail', (tester) async {
      await tester.runAsync(() => seedLive(running: true));
      await tester.pumpWidget(shellHost(Breakpoints.medium));
      await tester.pump();
      expect(strip, findsOneWidget);
    });
  });

  testWidgets('a trained weekday opens its latest detail and returns to Home', (
    tester,
  ) async {
    await tester.runAsync(seedHomeTraining);
    await tester.pumpWidget(shellHost(390));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.descendant(
        of: find.byType(TrainingSnapshot),
        matching: find.byKey(
          ValueKey('training-day-${DateTime.now().weekday - 1}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutDetailsScreen), findsOneWidget);
    expect(find.text('Bench Press'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsNothing);
    expect(find.byType(TrainingSnapshot), findsOneWidget);
    expect(
      tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
      0,
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
    final plansSemantics = tester.getSemantics(find.text('Home'));
    expect(plansSemantics.label, contains('Home'));
    expect(
      plansSemantics.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      plansSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.pumpWidget(shellHost(Breakpoints.medium));
    await tester.pumpAndSettle();
    final dashboardDestination = find.descendant(
      of: find.byType(AppNavRail),
      matching: find.text('Dashboard'),
    );
    final dashboardSemantics = tester.getSemantics(dashboardDestination);
    expect(dashboardSemantics.label, contains('Dashboard'));
    expect(
      dashboardSemantics.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      dashboardSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    semantics.dispose();
  });

  testWidgets('selected destination uses restrained accent emphasis', (
    tester,
  ) async {
    await tester.pumpWidget(bottomNavHost());
    final context = tester.element(find.byType(AppBottomNav));
    final selected = tester.widget<Text>(find.text('Home')).style!;
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
