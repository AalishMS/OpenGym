import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  TestWidgetsFlutterBinding.ensureInitialized();
  final hiveHarness = HiveTestHarness();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    const capture = bool.fromEnvironment('TOUR_PREVIEWS');
    if (capture) {
      await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      )).load();
    }
    // Supply the SDK's deterministic test font as an asset for google_fonts;
    // disabling fetching alone still throws for fonts absent from the bundle.
    final configFile = File('.dart_tool/package_config.json');
    final config = jsonDecode(configFile.readAsStringSync()) as Map;
    final flutterPackage = (config['packages'] as List).cast<Map>().singleWhere(
      (package) => package['name'] == 'flutter',
    );
    final flutterRoot = configFile.absolute.uri.resolve(
      '${flutterPackage['rootUri']}/',
    );
    final font =
        capture
            ? File('build/previews/manrope.ttf')
            : File.fromUri(
              flutterRoot.resolve('../flutter_tools/static/Ahem.ttf'),
            );
    final fontBytes = ByteData.sublistView(font.readAsBytesSync());
    final manifest = const StandardMessageCodec().encodeMessage({
      for (final family in ['Manrope', 'JetBrainsMono'])
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
          '$family-$weight.ttf': [
            {'asset': '$family-$weight.ttf'},
          ],
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final asset = utf8.decode(message!.buffer.asUint8List());
          if (asset == 'AssetManifest.bin') return manifest;
          if (asset.startsWith('Manrope-') ||
              asset.startsWith('JetBrainsMono-')) {
            return fontBytes;
          }
          return null;
        });
    await hiveHarness.open();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
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
    var expected = tester.getRect(target).inflate(4);
    if (tester.widget(target) is NavigationDestination) {
      final slot = tester.getRect(target);
      expected = Rect.fromLTRB(
        slot.left + 8,
        slot.top + 4,
        slot.right - 8,
        slot.bottom - 4,
      );
    } else if (find.byType(AppNavRail).evaluate().isNotEmpty &&
        tester.widget(target) is Text) {
      final anchorFinder = find.ancestor(
        of: target,
        matching: find.byType(GuidedTourTarget),
      );
      final anchor = tester.widget<GuidedTourTarget>(anchorFinder);
      expected = tester
          .getRect(target)
          .expandToInclude(tester.getRect(find.byKey(anchor.additionalTarget!)))
          .inflate(8);
    }
    expected = expected.intersect(
      (Offset.zero & tester.view.physicalSize).deflate(2),
    );
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
    expect(
      bubble.overlaps(actual),
      isFalse,
      reason: 'Bubble $bubble must avoid highlight $actual',
    );
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
      if (const bool.fromEnvironment('TOUR_PREVIEWS')) {
        await expectLater(
          find.byType(AppShell),
          matchesGoldenFile(
            '../.dart_tool/tour_previews/light_${size.width.toInt()}_plan.png',
          ),
        );
      }

      for (final label in ['History', 'Stats', 'Settings']) {
        await next(tester);
        expectSpotlight(tester, navTarget(label));
        expect(find.text('No plans yet'), findsOneWidget);
        expect(find.text('Skip'), findsOneWidget);
        if (const bool.fromEnvironment('TOUR_PREVIEWS') && label == 'History') {
          await expectLater(
            find.byType(AppShell),
            matchesGoldenFile(
              '../.dart_tool/tour_previews/light_${size.width.toInt()}_history.png',
            ),
          );
        }
      }
      expect(find.text('Make OpenGym yours'), findsOneWidget);
      expect(find.textContaining('Settings → Appearance'), findsOneWidget);
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
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 5'), findsOneWidget);
      expectSpotlight(tester, find.widgetWithText(TextButton, 'New plan'));
      await next(tester);
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
      if (const bool.fromEnvironment('TOUR_PREVIEWS')) {
        await expectLater(
          find.byType(AppShell),
          matchesGoldenFile(
            '../.dart_tool/tour_previews/dark_large_text_history.png',
          ),
        );
      }
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

  testWidgets('phone safe areas keep tab outlines and controls on screen', (
    tester,
  ) async {
    setSize(tester, const Size(390, 844));
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    await tester.pumpWidget(host(brightness: Brightness.dark));
    await tester.pumpAndSettle();
    await next(tester);
    expectSpotlight(tester, navTarget('History'));
    final target = tester.getRect(navTarget('History'));
    expect(target.bottom, lessThanOrEqualTo(844 - 34));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4'), findsOneWidget);
    expectSpotlight(tester, find.widgetWithText(AppButton, 'Create plan'));
  });

  testWidgets('compact phone supports enlarged text through every step', (
    tester,
  ) async {
    setSize(tester, const Size(320, 568));
    await tester.pumpWidget(host(brightness: Brightness.dark, textScale: 2));
    await tester.pumpAndSettle();
    expectSpotlight(tester, find.widgetWithText(AppButton, 'Create plan'));
    for (final label in ['History', 'Stats', 'Settings']) {
      await next(tester);
      expectSpotlight(tester, navTarget(label));
      final forward = find.widgetWithText(
        ElevatedButton,
        label == 'Settings' ? 'Done' : 'Next',
      );
      final text = find.descendant(of: forward, matching: find.byType(Text));
      expect(
        tester.getSize(text).height,
        lessThan(40),
        reason: 'The forward label should remain on one line',
      );
    }
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'Next and Back retain the spotlight while measuring and move directly '
      'between targets (reduce motion: $reduceMotion)',
      (tester) async {
        setSize(tester, const Size(390, 844));
        final first = GlobalKey();
        final second = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(const Color(0xFF00CED1), Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: Stack(
                children: [
                  Positioned(
                    left: 24,
                    top: 60,
                    child: SizedBox(key: first, width: 80, height: 48),
                  ),
                  Positioned(
                    left: 280,
                    top: 680,
                    child: SizedBox(key: second, width: 80, height: 48),
                  ),
                  Positioned.fill(
                    child: GuidedTour(
                      steps: [
                        GuidedTourStep(
                          target: first,
                          title: 'First step',
                          body: 'A control to try.',
                        ),
                        GuidedTourStep(
                          target: second,
                          title: 'Other step',
                          body:
                              'This control has a longer explanation. Use it to '
                              'review your workouts and see how your training '
                              'has changed over time. You can check your sets, '
                              'weights, and notes before your next session.',
                        ),
                      ],
                      onClose: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final highlight = find.byKey(const ValueKey('tutorial-highlight'));
        final bubble = find.byKey(const ValueKey('tutorial-bubble'));

        for (final forward in [true, false]) {
          final from = tester.getRect(highlight);
          final bubbleFrom = tester.getTopLeft(bubble);
          final to = tester
              .getRect(find.byKey(forward ? second : first))
              .inflate(4);
          await tester.tap(find.text(forward ? 'Next' : 'Back'));
          await tester.pump();
          expect(highlight, findsOneWidget);
          expect(tester.getRect(highlight), from);
          expect(tester.getTopLeft(bubble), bubbleFrom);
          expect(
            find.text(forward ? 'First step' : 'Other step'),
            findsOneWidget,
          );

          // Complete target measurement without advancing the animation clock.
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump();
            expect(highlight, findsOneWidget);
          }
          if (!reduceMotion) {
            expect(tester.getTopLeft(bubble), bubbleFrom);
          }
          await tester.pump(const Duration(milliseconds: 80));
          final midway = tester.getRect(highlight);
          final bubbleMidway = tester.getTopLeft(bubble);
          if (reduceMotion) {
            expect(midway, to);
          } else {
            expect(midway, isNot(from));
            expect(midway, isNot(to));
            expect(
              midway.center.dx,
              inExclusiveRange(
                math.min(from.center.dx, to.center.dx),
                math.max(from.center.dx, to.center.dx),
              ),
            );
            expect(
              midway.center.dy,
              inExclusiveRange(
                math.min(from.center.dy, to.center.dy),
                math.max(from.center.dy, to.center.dy),
              ),
            );
          }
          final paint = tester.widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(GuidedTour),
                  matching: find.byType(CustomPaint),
                )
                .first,
          );
          expect((paint.painter as dynamic).target, midway);
          await tester.pumpAndSettle();
          expect(tester.getRect(highlight), to);
          if (!reduceMotion) {
            final bubbleTo = tester.getTopLeft(bubble);
            expect(
              bubbleMidway.dy,
              inExclusiveRange(
                math.min(bubbleFrom.dy, bubbleTo.dy),
                math.max(bubbleFrom.dy, bubbleTo.dy),
              ),
            );
          }
        }
      },
    );
  }

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
