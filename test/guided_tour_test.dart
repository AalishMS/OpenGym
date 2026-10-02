import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/intro_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/tutorial_preferences.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';
import 'package:gymapp/widgets/app_button.dart';
import 'package:gymapp/widgets/app_nav_rail.dart';
import 'package:gymapp/widgets/guided_tour.dart';

import 'support/hive_test_harness.dart';

void main() {
  final hiveHarness = HiveTestHarness();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await hiveHarness.open();
  });
  tearDownAll(hiveHarness.close);
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      TutorialPreferences.tourPendingKey: true,
    });
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  Widget host({
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF00CED1), brightness),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: const AppShell(),
      ),
    );
  }

  void setSize(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Finder navTarget(String label) {
    if (find.byType(AppBottomNav).evaluate().isNotEmpty) {
      return find.byWidgetPredicate(
        (widget) => widget is NavigationDestination && widget.label == label,
      );
    }
    return find.descendant(
      of: find.byType(AppNavRail),
      matching: find.text(label),
    );
  }

  void expectSpotlight(WidgetTester tester, Finder target) {
    final expected = tester.getRect(target).inflate(6);
    final actual = tester.getRect(
      find.byKey(const ValueKey('tutorial-highlight')),
    );
    expect(actual.left, closeTo(expected.left, .01));
    expect(actual.top, closeTo(expected.top, .01));
    expect(actual.width, closeTo(expected.width, .01));
    expect(actual.height, closeTo(expected.height, .01));
    final bubble = tester.getRect(
      find.byKey(const ValueKey('tutorial-bubble')),
    );
    final size = tester.view.physicalSize;
    expect(bubble.left, greaterThanOrEqualTo(0));
    expect(bubble.top, greaterThanOrEqualTo(0));
    expect(bubble.right, lessThanOrEqualTo(size.width));
    expect(bubble.bottom, lessThanOrEqualTo(size.height));
    expect(bubble.overlaps(actual), isFalse);
    expect(tester.takeException(), isNull);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('empty tour stays on Home with aligned targets at $size', (
      tester,
    ) async {
      setSize(tester, size);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.text('Plan your first workout'), findsOneWidget);
      expectSpotlight(tester, find.widgetWithText(AppButton, 'Create plan'));

      for (final label in ['History', 'Stats', 'Settings']) {
        await next(tester);
        expectSpotlight(tester, navTarget(label));
        expect(find.text('No plans yet'), findsOneWidget);
        expect(find.text('Skip'), findsOneWidget);
      }
      expect(find.textContaining('Settings → Data'), findsOneWidget);
      expect(find.text('4 of 4'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidedTour), findsNothing);
      expect(HiveService.getPlans(), isEmpty);
      expect(HiveService.getSessions(), isEmpty);
    });
  }

  testWidgets('Back and Skip close the tour and it does not auto-replay', (
    tester,
  ) async {
    setSize(tester, const Size(390, 844));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GuidedTour), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    expect(await TutorialPreferences.isTourPending(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(GuidedTour), findsNothing);

    await TutorialPreferences.markTourSeen();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(TutorialPreferences.tourPendingKey, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(GuidedTour), findsNothing);
    expect(await TutorialPreferences.isTourPending(), isFalse);
  });

  testWidgets(
    'replay with existing plans shows five steps and scrolls to New plan',
    (tester) async {
      setSize(tester, const Size(390, 844));
      await tester.runAsync(() async {
        for (var index = 0; index < 12; index++) {
          final plan = WorkoutPlan(
            id: 'plan-$index',
            name: 'Plan $index',
            exercises: [ExerciseTemplate(name: 'Squat', sets: 3)],
          );
          await Hive.box<WorkoutPlan>(HiveService.plansBox).put(plan.id, plan);
        }
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(TutorialPreferences.tourPendingKey, false);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(navTarget('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Replay tutorial'), 250);
      await tester.tap(find.text('Replay tutorial'));
      await tester.pumpAndSettle();
      expect(find.byType(IntroScreen), findsOneWidget);
      await next(tester);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 5'), findsOneWidget);
      expectSpotlight(tester, find.widgetWithText(TextButton, 'New plan'));
      await next(tester);
      expect(find.text('2 of 5'), findsOneWidget);
      expectSpotlight(tester, find.widgetWithText(AppButton, 'Start workout'));
      for (final label in ['History', 'Stats', 'Settings']) {
        await next(tester);
        expectSpotlight(tester, navTarget(label));
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(HiveService.getPlans(), hasLength(12));
      expect(HiveService.getSessions(), isEmpty);
      expect(await TutorialPreferences.isTourPending(), isFalse);
    },
  );

  testWidgets(
    'resizing an active tour reanchors from bottom tabs to the rail',
    (tester) async {
      setSize(tester, const Size(390, 844));
      await tester.pumpWidget(host(brightness: Brightness.dark, textScale: 2));
      await tester.pumpAndSettle();
      await next(tester);
      expectSpotlight(tester, navTarget('History'));
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(find.byType(AppNavRail), findsOneWidget);
      expect(find.text('2 of 4'), findsOneWidget);
      expectSpotlight(tester, navTarget('History'));
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expectSpotlight(tester, navTarget('History'));
      expect(find.text('Skip'), findsOneWidget);
    },
  );

  testWidgets('missing targets are skipped without blocking the tour', (
    tester,
  ) async {
    setSize(tester, const Size(390, 844));
    final target = GlobalKey();
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const Color(0xFF00CED1), Brightness.light),
        home: Stack(
          children: [
            Center(child: SizedBox(key: target, width: 80, height: 48)),
            Positioned.fill(
              child: GuidedTour(
                steps: [
                  GuidedTourStep(
                    target: GlobalKey(),
                    title: 'Missing',
                    body: 'Missing',
                  ),
                  GuidedTourStep(
                    target: target,
                    title: 'Available',
                    body: 'Available target',
                  ),
                ],
                onClose: () => closed = true,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Available target'), findsOneWidget);
    expectSpotlight(tester, find.byKey(target));
    await tester.tap(find.text('Done'));
    expect(closed, isTrue);
  });

  testWidgets('keyboard traversal stays within the tutorial controls', (
    tester,
  ) async {
    setSize(tester, const Size(390, 844));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    for (var index = 0; index < 8; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      expect(focusedContext, isNotNull);
      expect(
        focusedContext!.findAncestorWidgetOfExactType<GuidedTour>(),
        isNotNull,
      );
    }
    expect(HiveService.getPlans(), isEmpty);
    expect(HiveService.getSessions(), isEmpty);
  });
}
