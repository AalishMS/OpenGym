import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/coach_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/split_repository.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/widgets/splits/split_switcher.dart';

import 'support/hive_test_harness.dart';
import 'package:gymapp/theme/app_theme.dart';

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open();
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  testWidgets('header menu switches the complete visible workspace', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(harness.host(const HomeScreen()));
    expect(find.text('PPL'), findsOneWidget);
    expect(find.text('[PPL]'), findsNothing);
    final switcherText = tester.widget<Text>(find.text('PPL'));
    final wordmarkText = tester.widget<Text>(find.text('> OpenGym'));
    expect(switcherText.style?.fontSize, 14);
    expect(
      switcherText.style!.fontSize,
      lessThan(wordmarkText.style!.fontSize!),
    );
    final switcherContent = tester.widget<Container>(
      find.byKey(const ValueKey('split-switcher-content')),
    );
    expect(switcherContent.color, isNull);
    expect(switcherContent.decoration, isNull);
    // Up next and the plan row both name the active split's plan.
    expect(find.text('Ppl Plan'), findsWidgets);
    expect(find.text('Ul Plan'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('split-switcher-button')))
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('split-menu')), findsOneWidget);
    final selectedSplit = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'PPL split',
      ),
    );
    expect(selectedSplit.properties.button, isTrue);
    expect(selectedSplit.properties.selected, isTrue);

    await tester.tap(find.text('UL'));
    await tester.pumpAndSettle();
    expect(find.text('UL'), findsOneWidget);
    expect(find.text('[UL]'), findsNothing);
    expect(find.text('Ppl Plan'), findsNothing);
    expect(find.text('Ul Plan'), findsWidgets);
    expect(harness.sessions.sessions.single.splitId, 'ul');
    semantics.dispose();
  });

  testWidgets('split menu consumes Back before leaving Manage', (tester) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen()));
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('split-menu')), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Manage'), findsOneWidget);
  });

  for (final managing in [false, true]) {
    testWidgets(
      'edge Back keeps menu ownership after Android cancels the pointer (Manage: $managing)',
      (tester) async {
        final harness = (await tester.runAsync(_createHarness))!;
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.host(const HomeScreen()));
        var exitRequests = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') exitRequests++;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        if (managing) {
          await tester.tap(find.text('Manage'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
        await tester.pumpAndSettle();
        // MenuAnchor closes on outside pointer-down, before Android recognizes an
        // edge gesture and sends its Back. That gesture must still own one layer.
        final gesture = await tester.startGesture(const Offset(2, 450));
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('split-menu')), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text(managing ? 'Done' : 'Manage'), findsOneWidget);
        expect(exitRequests, 0);
      },
    );
  }

  testWidgets('history and stats follow the selected split', (tester) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await harness.splits.setActiveSplit('ul');

    await tester.pumpWidget(harness.host(const HistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('UL Plan'), findsOneWidget);
    expect(find.text('PPL Plan'), findsNothing);
    await tester.tap(find.text('UL Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsOneWidget);
    expect(find.text('UL Only'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pumpWidget(harness.host(const StatsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('UL Only'), findsWidgets);
    expect(find.text('PPL Only'), findsNothing);
  });

  testWidgets('split menu opens the grouped workout preset browser', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.host(const HomeScreen()));
    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();

    expect(find.text('Browse'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New split')).dy,
      lessThan(tester.getTopLeft(find.text('Browse')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Browse')).dy,
      lessThan(tester.getTopLeft(find.text('Manage splits')).dy),
    );

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preset-catalog')), findsOneWidget);
    expect(find.text('Workout presets'), findsOneWidget);
    expect(find.text('Hypertrophy'), findsOneWidget);
    expect(find.text('Full-body hypertrophy'), findsOneWidget);
    expect(find.text('55–75 min · New or busy lifter'), findsOneWidget);
    expect(find.text('HYP-FB-3'), findsNothing);
    expect(find.text('Full-body strength'), findsNothing);

    await tester.tap(find.text('Strength'));
    await tester.pumpAndSettle();
    expect(find.text('Full-body strength'), findsOneWidget);
    expect(find.text('Full-body hypertrophy'), findsNothing);

    await tester.tap(find.text('Hypertrophy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full-body hypertrophy'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('preset-details-HYP-FB-3')),
      findsOneWidget,
    );
    expect(find.text('Workout days'), findsOneWidget);
    expect(find.text('Full body A'), findsOneWidget);
    expect(find.byKey(const ValueKey('install-preset-action')), findsOneWidget);

    await tester.tap(find.text('Full body A'));
    await tester.pumpAndSettle();
    expect(find.text('3 × 6-10'), findsOneWidget);
    expect(find.text('Rest 3 min · 2 reps in reserve'), findsOneWidget);
    expect(find.textContaining('Or swap for Front Squat'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to workout presets'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preset-catalog')), findsOneWidget);
  });

  for (final size in [const Size(390, 400), const Size(1000, 400)]) {
    testWidgets('preset system Back preserves the catalog at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen(), size: size));
      await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strength'));
      await tester.pumpAndSettle();
      final catalog = find.byKey(const ValueKey('preset-catalog'));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: catalog, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(50);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, 50);
      await tester.tap(find.text('Full-body strength'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(catalog, findsOneWidget);
      expect(find.text('Full-body strength'), findsOneWidget);
      expect(scroll.position.pixels, 50);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Workout presets'), findsNothing);
    });
  }

  testWidgets('new split dialog validates names and selects the result', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen()));

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New split'));
    await tester.pumpAndSettle();
    expect(find.text('New split'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('split-name-field')),
      'ppl',
    );
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('A split with that name already exists.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('split-name-field')),
      ' Full Body ',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(harness.splits.activeSplit?.name, 'Full Body');
    expect(find.text('Full Body'), findsOneWidget);
    expect(find.text('[FULL BODY]'), findsNothing);
    expect(harness.plans.plans, isEmpty);
  });

  testWidgets('preset browser adapts to themes, width, and large text', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);

    for (final scenario in [
      (Brightness.light, const Size(390, 800), 1.5),
      (Brightness.dark, const Size(1000, 800), 1.0),
    ]) {
      await tester.pumpWidget(
        harness.host(
          const HomeScreen(),
          brightness: scenario.$1,
          size: scenario.$2,
          textScale: scenario.$3,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      expect(find.text('Workout presets'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Upper/lower hypertrophy'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('preset-details-HYP-UL-4')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('five-split limit disables creation with an explanation', (
    tester,
  ) async {
    final harness =
        (await tester.runAsync(
          () => _createHarness(
            splitNames: const ['PPL', 'UL', 'Full Body', 'Power', 'Travel'],
          ),
        ))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen()));
    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();

    expect(find.text('Limit reached'), findsOneWidget);
    final action = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('new-split-action')),
        matching: find.byType(InkWell),
      ),
    );
    expect(action.onTap, isNull);
  });

  testWidgets('manage supports rename and guarded active deletion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen()));

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage splits'));
    await tester.pumpAndSettle();
    expect(find.text('Manage splits'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename PPL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('split-name-field')),
      'Push Pull Legs',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Push Pull Legs'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Delete Push Pull Legs'));
    await tester.pumpAndSettle();
    expect(find.text('Delete split?'), findsOneWidget);
    expect(find.textContaining('removes 1 plan and 1 session'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Delete'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Select'));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(harness.splits.splits.map((split) => split.name), ['UL']);
    expect(harness.splits.activeSplitId, 'ul');
    expect(harness.plans.plans.single.name, 'UL Plan');
    expect(harness.sessions.sessions.single.planName, 'UL Plan');
    semantics.dispose();
  });

  testWidgets('header orders wordmark slash split and Coach', (tester) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    final coach = CoachProvider(
      splitProvider: harness.splits,
      userIdProvider: () => 'user-1',
      isConfigured: () => true,
    );
    addTearDown(coach.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen(), coach: coach));
    final wordmark = find.text('> OpenGym');
    final slash = find.text('/');
    final split = find.byKey(const ValueKey('split-switcher-content'));
    final button = find.byKey(const ValueKey('coach-button'));
    expect(tester.widget<Text>(wordmark).style?.fontSize, 17);
    expect(tester.widget<Text>(find.text('PPL')).style?.fontSize, 14);
    expect(
      tester.getRect(wordmark).right,
      lessThan(tester.getRect(slash).left),
    );
    expect(tester.getRect(slash).right, lessThan(tester.getRect(split).left));
    expect(
      tester.getRect(split).right,
      lessThanOrEqualTo(tester.getRect(button).left),
    );
    expect(
      tester.getCenter(wordmark).dy,
      closeTo(tester.getCenter(slash).dy, 1),
    );
    expect(tester.getCenter(split).dy, closeTo(tester.getCenter(button).dy, 1));
  });

  testWidgets('header omits separator without an active split or provider', (
    tester,
  ) async {
    final splits = SplitProvider(
      repository: _FakeSplitRepository([], ''),
      userIdProvider: () => 'user-1',
    );
    final harness = _Harness(
      splits,
      WorkoutPlanProvider(splits),
      WorkoutSessionProvider(splits),
    );
    addTearDown(harness.dispose);
    for (final includeSplits in [true, false]) {
      await tester.pumpWidget(
        harness.host(const HomeScreen(), includeSplits: includeSplits),
      );
      expect(find.text('> OpenGym'), findsOneWidget);
      expect(find.text('/'), findsNothing);
      expect(find.byKey(const ValueKey('split-switcher-button')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('hiding Coach returns its width to the split', (tester) async {
    final harness =
        (await tester.runAsync(
          () => _createHarness(
            splitNames: ['A Very Long Training Split Name', 'UL'],
          ),
        ))!;
    addTearDown(harness.dispose);
    final coach = CoachProvider(
      splitProvider: harness.splits,
      userIdProvider: () => 'user-1',
      isConfigured: () => true,
    );
    addTearDown(coach.dispose);
    await tester.pumpWidget(harness.host(const HomeScreen(), coach: coach));
    final trigger = find.byKey(const ValueKey('split-switcher-button'));
    final withCoach = tester.getSize(trigger).width;
    coach.enabled = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coach-button')), findsNothing);
    expect(tester.getSize(trigger).width, greaterThan(withCoach));
  });

  testWidgets('switcher remains readable across themes, widths, and scaling', (
    tester,
  ) async {
    final harness =
        (await tester.runAsync(
          () => _createHarness(
            splitNames: const ['A Very Long Training Split Name', 'UL'],
          ),
        ))!;
    addTearDown(harness.dispose);
    final coach = CoachProvider(
      splitProvider: harness.splits,
      userIdProvider: () => 'user-1',
      isConfigured: () => true,
    );
    addTearDown(coach.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final brightness in Brightness.values) {
      for (final size in [
        const Size(320, 640),
        const Size(390, 800),
        const Size(412, 800),
        const Size(1100, 800),
      ]) {
        tester.view.physicalSize = size;
        for (final textScale in [1.0, 1.6]) {
          for (final withCoach in [false, true]) {
            await tester.pumpWidget(
              harness.host(
                const HomeScreen(),
                brightness: brightness,
                size: size,
                textScale: textScale,
                coach: withCoach ? coach : null,
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull, reason: '$brightness $size');
            if (withCoach) {
              final split = tester.getRect(
                find.byKey(const ValueKey('split-switcher-content')),
              );
              final button = tester.getRect(
                find.byKey(const ValueKey('coach-button')),
              );
              expect(split.right, lessThanOrEqualTo(button.left));
              expect(button.right, lessThanOrEqualTo(size.width));
            }
          }
        }
      }
    }
  });

  test('split names keep a trailing copy counter apart from the base', () {
    expect(splitNameParts('Powerbuilding PPLUL (2)'), (
      'Powerbuilding PPLUL',
      ' (2)',
    ));
    expect(splitNameParts('PPL'), ('PPL', ''));
    expect(splitNameParts('(2)'), ('(2)', ''));
    expect(splitNameParts('Upper (2) Lower'), ('Upper (2) Lower', ''));
  });

  testWidgets('the copy counter stays visible with the Coach on and off', (
    tester,
  ) async {
    const size = Size(412, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    RenderParagraph paragraph(String text) => tester.renderObject(
      find.descendant(
        of: find.byKey(const ValueKey('split-switcher-button')),
        matching: find.text(text),
      ),
    );

    // The test font draws every glyph as a square, so the long name can't fit
    // at phone width and with the Coach on even the short one is cut. The
    // counter has to survive both.
    for (final names in [
      ['PPL (2)', 'PPL'],
      ['Powerbuilding PPLUL (2)', 'Powerbuilding PPLUL'],
    ]) {
      final harness =
          (await tester.runAsync(() => _createHarness(splitNames: names)))!;
      addTearDown(harness.dispose);
      final coach = CoachProvider(
        splitProvider: harness.splits,
        userIdProvider: () => 'user-1',
        isConfigured: () => true,
      );
      addTearDown(coach.dispose);
      final fits = names.first.length < 10;

      for (final withCoach in [false, true]) {
        await tester.pumpWidget(
          harness.host(
            const HomeScreen(),
            size: size,
            coach: withCoach ? coach : null,
          ),
        );
        await tester.pump();
        final reason = '${names.first}, Coach ${withCoach ? 'on' : 'off'}';
        expect(tester.takeException(), isNull, reason: reason);
        expect(
          find.byKey(const ValueKey('coach-button')),
          withCoach ? findsOneWidget : findsNothing,
          reason: reason,
        );

        final suffix = paragraph(' (2)');
        expect(suffix.didExceedMaxLines, isFalse, reason: reason);
        final suffixRect = tester.getRect(find.text(' (2)'));
        expect(suffixRect.right, lessThanOrEqualTo(size.width), reason: reason);
        expect(suffixRect.width, greaterThan(0), reason: reason);
        final base = names.first.substring(0, names.first.length - 4);
        if (!withCoach) {
          expect(
            paragraph(base).didExceedMaxLines,
            !fits,
            reason: '$reason: only an overlong base name is cut off',
          );
        }
        // The menu measures its rows with IntrinsicWidth.
        await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$reason: menu');
        final menuSuffix = find.descendant(
          of: find.byKey(const ValueKey('split-menu')),
          matching: find.text(' (2)'),
        );
        expect(menuSuffix, findsOneWidget, reason: '$reason: menu');
        expect(
          tester.renderObject<RenderParagraph>(menuSuffix).didExceedMaxLines,
          isFalse,
          reason: '$reason: menu',
        );
        await tester.tapAt(const Offset(10, 790));
        await tester.pumpAndSettle();
        if (!fits && !withCoach) {
          expect(
            tester
                .getSize(find.byKey(const ValueKey('split-switcher-content')))
                .width,
            greaterThan(180),
            reason: '$reason: the switcher takes the width the wordmark leaves',
          );
        }
      }
    }
  });

  testWidgets('menu dismisses outside and honors reduced motion', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.host(const HomeScreen(), disableAnimations: true),
    );

    final switcherAnimation = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byKey(const ValueKey('split-switcher-button')),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcherAnimation.duration, Duration.zero);

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pump();
    final menu = find.byKey(const ValueKey('split-menu'));
    expect(menu, findsOneWidget);
    final menuRect = tester.getRect(menu);
    final outsideX = menuRect.left > 20 ? 10.0 : menuRect.right + 10;
    await tester.tapAt(Offset(outsideX, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('split-menu')), findsNothing);
  });

  testWidgets('system Back closes the open menu and keeps the app open', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_createHarness))!;
    addTearDown(harness.dispose);
    var exitRequests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exitRequests++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(harness.host(const HomeScreen()));

    await tester.tap(find.byKey(const ValueKey('split-switcher-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('split-menu')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('split-menu')), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(exitRequests, 0);

    // With the menu closed, Back is the app's again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exitRequests, 1);
  });
}

Future<_Harness> _createHarness({
  List<String> splitNames = const ['PPL', 'UL'],
}) async {
  final now = DateTime(2026);
  final splitValues = [
    for (var index = 0; index < splitNames.length; index++)
      gym.Split(
        id: index == 0 ? 'ppl' : (index == 1 ? 'ul' : 'split-$index'),
        name: splitNames[index],
        userId: 'user-1',
        createdAt: now.add(Duration(minutes: index)),
      ),
  ];
  final repository = _FakeSplitRepository(splitValues, splitValues.first.id);

  if (splitValues.length >= 2) {
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: 'ppl-plan',
        splitId: splitValues[0].id,
        name: 'PPL Plan',
        exercises: [],
      ),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: 'ul-plan',
        splitId: splitValues[1].id,
        name: 'UL Plan',
        exercises: [],
      ),
    );
    await HiveService.putSessionRaw(
      _session('ppl-session', splitValues[0].id, 'PPL Plan', 'PPL Only'),
    );
    await HiveService.putSessionRaw(
      _session('ul-session', splitValues[1].id, 'UL Plan', 'UL Only'),
    );
  }
  final splits = SplitProvider(
    repository: repository,
    userIdProvider: () => 'user-1',
  );
  final plans = WorkoutPlanProvider(splits);
  final sessions = WorkoutSessionProvider(splits);
  return _Harness(splits, plans, sessions);
}

WorkoutSession _session(
  String id,
  String splitId,
  String planName,
  String exerciseName,
) => WorkoutSession(
  id: id,
  splitId: splitId,
  date: DateTime(2026),
  planName: planName,
  exercises: [
    Exercise(name: exerciseName, sets: [Set(reps: 5, weight: 50)]),
  ],
);

class _Harness {
  final SplitProvider splits;
  final WorkoutPlanProvider plans;
  final WorkoutSessionProvider sessions;

  const _Harness(this.splits, this.plans, this.sessions);

  Widget host(
    Widget child, {
    Brightness brightness = Brightness.dark,
    Size size = const Size(390, 800),
    double textScale = 1,
    bool disableAnimations = false,
    bool includeSplits = true,
    CoachProvider? coach,
  }) => MultiProvider(
    providers: [
      if (coach != null)
        ChangeNotifierProvider<CoachProvider>.value(value: coach),
      if (includeSplits)
        ChangeNotifierProvider<SplitProvider>.value(value: splits),
      ChangeNotifierProvider<WorkoutPlanProvider>.value(value: plans),
      ChangeNotifierProvider<WorkoutSessionProvider>.value(value: sessions),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
    ],
    child: MaterialApp(
      key: UniqueKey(),
      theme: buildTheme(const Color(0xFF00A8FF), brightness),
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );

  void dispose() {
    sessions.dispose();
    plans.dispose();
    splits.dispose();
  }
}

class _FakeSplitRepository extends SplitRepository {
  final List<gym.Split> values;
  SplitPreference preference;

  _FakeSplitRepository(this.values, String activeSplitId)
    : preference = SplitPreference(
        userId: 'user-1',
        activeSplitId: activeSplitId,
      );

  @override
  List<gym.Split> getSplits() => List.of(values);

  @override
  SplitPreference? getPreference(String userId) => preference;

  @override
  Future<void> upsertSplit(gym.Split split) async {
    final index = values.indexWhere((value) => value.id == split.id);
    if (index < 0) {
      values.add(split);
    } else {
      values[index] = split;
    }
  }

  @override
  Future<void> setActive(String userId, String splitId) async {
    preference = SplitPreference(userId: userId, activeSplitId: splitId);
  }

  @override
  Future<void> deleteSplit({
    required String userId,
    required String splitId,
    required String replacementSplitId,
  }) async {
    values.removeWhere((split) => split.id == splitId);
    if (preference.activeSplitId == splitId) {
      preference = SplitPreference(
        userId: userId,
        activeSplitId: replacementSplitId,
      );
    }
    final deletedAt = DateTime(2026, 1, 2);
    for (final plan in HiveService.getAllPlansRaw()) {
      if (plan.splitId == splitId) plan.deletedAt = deletedAt;
    }
    for (final session in HiveService.getAllSessionsRaw()) {
      if (session.splitId == splitId) session.deletedAt = deletedAt;
    }
  }
}
