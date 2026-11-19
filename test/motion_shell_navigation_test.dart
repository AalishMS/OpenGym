import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/breakpoints.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';
import 'package:gymapp/widgets/app_nav_rail.dart';
import 'package:gymapp/widgets/motion/collapsible.dart';

import 'support/hive_test_harness.dart';

const _seed = Color(0xFF00A2FF);

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(
            'com.aalishms.opengym/workout_timer_notification',
          ),
          (_) async => null,
        );
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  Widget shellHost({double width = 390, bool reduceMotion = false}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: MaterialApp(
        theme: buildTheme(_seed, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            disableAnimations: reduceMotion,
          ),
          child: const AppShell(),
        ),
      ),
    );
  }

  Future<void> tapTab(WidgetTester tester, String label) => tester.tap(
    find.descendant(of: find.byType(AppBottomNav), matching: find.text(label)),
  );

  group('tab change', () {
    double tabOpacity(WidgetTester tester) =>
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.byType(IndexedStack).first,
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;

    testWidgets('the new tab shows from its first frame and settles', (
      tester,
    ) async {
      await tester.pumpWidget(shellHost());
      await tester.pumpAndSettle();
      expect(tabOpacity(tester), 1);

      await tapTab(tester, 'History');
      await tester.pump();
      // In the tree and visible on the first frame: not a blank page.
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(tabOpacity(tester), closeTo(0.4, 0.001));
      await tester.pump(AppMotion.quick ~/ 2);
      expect(tabOpacity(tester), inExclusiveRange(0.4, 1));
      await tester.pumpAndSettle();
      expect(tabOpacity(tester), 1);
    });

    testWidgets('is immediate under reduced motion', (tester) async {
      await tester.pumpWidget(shellHost(reduceMotion: true));
      await tester.pumpAndSettle();
      await tapTab(tester, 'History');
      await tester.pump();
      expect(tabOpacity(tester), 1);
    });

    testWidgets('a selection haptic still marks the change', (tester) async {
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
      await tester.pumpWidget(shellHost());
      await tester.pumpAndSettle();
      await tapTab(tester, 'Stats');
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });
  });

  group('bottom navigation selection', () {
    Color labelColor(WidgetTester tester, String label) =>
        tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: find.byType(AppBottomNav),
                matching: find.text(label),
              ),
            )
            .text
            .style!
            .color!;

    FontWeight labelWeight(WidgetTester tester, String label) =>
        tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: find.byType(AppBottomNav),
                matching: find.text(label),
              ),
            )
            .text
            .style!
            .fontWeight!;

    Color iconColor(WidgetTester tester, String label) {
      final destination = find.ancestor(
        of: find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
        matching: find.byType(NavigationDestination),
      );
      final icon = find.descendant(
        of: destination,
        matching: find.byType(Icon),
      );
      return IconTheme.of(tester.element(icon.first)).color!;
    }

    testWidgets('icon and label settle with the sliding rule', (tester) async {
      await tester.pumpWidget(shellHost());
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AppBottomNav));
      final accent = accentColor(context);
      final secondary = textSecondaryColor(context);
      // At rest from the first frame: nothing animates on arrival.
      expect(labelColor(tester, 'Home'), accent);
      expect(labelColor(tester, 'Settings'), secondary);
      expect(iconColor(tester, 'Home'), accent);

      await tapTab(tester, 'Settings');
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      // Midway, both destinations are between their two states, as the rule
      // is between its two places.
      for (final label in ['Home', 'Settings']) {
        expect(labelColor(tester, label), isNot(accent));
        expect(labelColor(tester, label), isNot(secondary));
        expect(iconColor(tester, label), isNot(accent));
        expect(iconColor(tester, label), isNot(secondary));
      }
      // The weight changes at once: the fonts are static weights, and one
      // eased through them would step and shift the centred label.
      expect(labelWeight(tester, 'Settings'), FontWeight.w700);
      expect(labelWeight(tester, 'Home'), FontWeight.w500);
      final rule = tester.widget<AnimatedAlign>(
        find.byKey(const ValueKey('bottom-nav-indicator')),
      );
      expect(rule.duration, AppMotion.standard);
      expect(rule.curve, AppMotion.curve);

      await tester.pumpAndSettle();
      expect(labelColor(tester, 'Settings'), accent);
      expect(iconColor(tester, 'Settings'), accent);
      expect(labelColor(tester, 'Home'), secondary);
      expect(iconColor(tester, 'Home'), secondary);
      final style =
          tester
              .renderObject<RenderParagraph>(
                find.descendant(
                  of: find.byType(AppBottomNav),
                  matching: find.text('Settings'),
                ),
              )
              .text
              .style!;
      expect(style.fontWeight, FontWeight.w700);
    });

    testWidgets('selection lands at once under reduced motion', (tester) async {
      await tester.pumpWidget(shellHost(reduceMotion: true));
      await tester.pumpAndSettle();
      final accent = accentColor(tester.element(find.byType(AppBottomNav)));
      await tapTab(tester, 'Settings');
      await tester.pump();
      expect(labelColor(tester, 'Settings'), accent);
      expect(iconColor(tester, 'Settings'), accent);
    });

    testWidgets('the update dot fades in rather than popping', (tester) async {
      Widget nav(int? badged, {bool reduceMotion = false}) => MaterialApp(
        theme: buildTheme(_seed, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            bottomNavigationBar: AppBottomNav(
              currentIndex: 0,
              badgedIndex: badged,
              onTap: (_) {},
            ),
          ),
        ),
      );
      Badge dot() => tester.widgetList<Badge>(find.byType(Badge)).elementAt(3);

      await tester.pumpWidget(nav(null));
      expect(dot().isLabelVisible, isFalse);
      await tester.pumpWidget(nav(3));
      await tester.pump(AppMotion.quick ~/ 2);
      expect(dot().isLabelVisible, isTrue);
      expect(dot().backgroundColor!.a, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      // Read the accent once the theme has settled. Each pumpWidget is a new
      // MaterialApp, so AnimatedTheme lerps between two equal themes, and
      // mid-lerp a solved tone can come back a rounding step off.
      final ground = accentFillColor(tester.element(find.byType(Badge).first));
      expect(ground.a, 1);
      expect(dot().backgroundColor, ground);

      await tester.pumpWidget(nav(null));
      await tester.pumpAndSettle();
      expect(dot().isLabelVisible, isFalse);

      // A badge present on arrival is simply there.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(nav(3));
      expect(dot().backgroundColor, ground);

      await tester.pumpWidget(nav(null, reduceMotion: true));
      await tester.pump();
      expect(dot().isLabelVisible, isFalse);
    });

    testWidgets('the rail settles its labels and icons the same way', (
      tester,
    ) async {
      await tester.pumpWidget(shellHost(width: Breakpoints.medium));
      await tester.pumpAndSettle();
      final rail = find.byType(AppNavRail);
      final context = tester.element(rail);
      final accent = accentColor(context);
      final secondary = textSecondaryColor(context);
      Color label(String text) =>
          tester
              .renderObject<RenderParagraph>(
                find.descendant(of: rail, matching: find.text(text)),
              )
              .text
              .style!
              .color!;

      // The rail opens on the Dashboard.
      expect(label('Dashboard'), accent);
      expect(label('History'), secondary);
      await tester.tap(
        find.descendant(of: rail, matching: find.text('History')),
      );
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      expect(label('History'), isNot(accent));
      expect(label('History'), isNot(secondary));
      // Colour eases; weight changes at once.
      FontWeight? weight(String text) =>
          tester
              .renderObject<RenderParagraph>(
                find.descendant(of: rail, matching: find.text(text)),
              )
              .text
              .style!
              .fontWeight;
      final rest =
          Theme.of(tester.element(rail)).textTheme.labelMedium?.fontWeight;
      expect(weight('History'), FontWeight.bold);
      expect(weight('Dashboard'), rest);
      await tester.pumpAndSettle();
      expect(label('History'), accent);
      expect(label('Dashboard'), secondary);
    });
  });

  group('resume strip', () {
    final strip = find.byKey(const ValueKey('active-workout-bar'));
    Finder region() =>
        find.ancestor(of: strip, matching: find.byType(Collapsible));

    Future<void> seedLive(WidgetTester tester) => tester.runAsync(() async {
      final now = DateTime.now();
      final session = WorkoutSession(
        id: 'live-session',
        planName: 'Leg Day',
        date: now.subtract(const Duration(minutes: 20)),
        startedAt: now.subtract(const Duration(minutes: 20)),
        isCompleted: false,
        timerStartedAt: now.subtract(const Duration(minutes: 5)),
        durationSeconds: 600,
        exercises: [
          Exercise(name: 'Squat', sets: [Set(reps: 5, weight: 100)]),
        ],
      );
      await Hive.box<WorkoutSession>(
        HiveService.sessionsBox,
      ).put(session.id, session);
    });

    Future<void> finishLive(WidgetTester tester) => tester.runAsync(() async {
      final box = Hive.box<WorkoutSession>(HiveService.sessionsBox);
      await box.put(
        'live-session',
        box
            .get('live-session')!
            .copyWith(isCompleted: true, timerStartedAt: null),
      );
    });

    testWidgets('opens and closes as a region while the shell is in view', (
      tester,
    ) async {
      await tester.pumpWidget(shellHost());
      await tester.pumpAndSettle();
      expect(strip, findsNothing);

      await seedLive(tester);
      await tester.pump();
      // In the tree, and tappable, from its first frame.
      expect(strip, findsOneWidget);
      await tester.pump(AppMotion.standard ~/ 2);
      final opening = tester.getSize(region()).height;
      await tester.pumpAndSettle();
      final full = tester.getSize(region()).height;
      expect(full, greaterThanOrEqualTo(56));
      expect(opening, inExclusiveRange(0, full));
      // It sits above the navigation, which keeps its place.
      expect(
        tester.getBottomLeft(strip).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(AppBottomNav)).dy),
      );

      final openSemantics = tester.ensureSemantics();
      expect(find.semantics.byLabel(RegExp('Leg Day')), findsOne);
      openSemantics.dispose();

      await finishLive(tester);
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 2);
      // Folding away: the finished workout stays legible but takes no taps
      // and says nothing to screen readers.
      expect(strip, findsOneWidget);
      expect(find.text('Leg Day'), findsOneWidget);
      expect(tester.getSize(region()).height, inExclusiveRange(0, full));
      expect(
        find.ancestor(
          of: strip,
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsWidgets,
      );
      final semantics = tester.ensureSemantics();
      expect(find.semantics.byLabel(RegExp('Leg Day')), findsNothing);
      semantics.dispose();
      await tester.pumpAndSettle();
      expect(strip, findsNothing);
    });

    testWidgets('a strip already showing is simply there', (tester) async {
      await seedLive(tester);
      await tester.pumpWidget(shellHost());
      await tester.pump();
      final full = tester.getSize(region()).height;
      expect(full, greaterThanOrEqualTo(56));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(region()).height, full);
    });

    testWidgets('a change made under a pushed route does not replay', (
      tester,
    ) async {
      await tester.pumpWidget(shellHost());
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(AppShell)));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Workout')),
        ),
      );
      await tester.pumpAndSettle();

      // The workout starts while it covers the shell.
      await seedLive(tester);
      await tester.pump();
      navigator.pop();
      await tester.pump();
      final full = tester.getSize(region()).height;
      expect(full, greaterThanOrEqualTo(56));
      // Throughout the pop the strip is at rest, not folding open.
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getSize(region()).height, full);
      }
      await tester.pumpAndSettle();

      // And it ends the same way: finished while covered, simply gone.
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Workout')),
        ),
      );
      await tester.pumpAndSettle();
      await finishLive(tester);
      await tester.pump();
      navigator.pop();
      await tester.pump();
      expect(strip, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('opens and closes at once under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(shellHost(reduceMotion: true));
      await tester.pumpAndSettle();
      await seedLive(tester);
      await tester.pump();
      expect(tester.getSize(region()).height, greaterThanOrEqualTo(56));
      await tester.pump();

      await finishLive(tester);
      await tester.pump();
      await tester.pump();
      expect(strip, findsNothing);
    });
  });
}
