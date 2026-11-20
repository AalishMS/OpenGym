import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/repositories/split_repository.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/home/home_plan_row.dart';
import 'package:gymapp/widgets/home/plan_card.dart';
import 'package:gymapp/widgets/motion/surface_fade.dart';

import 'support/hive_test_harness.dart';
import 'support/test_fonts.dart';

// Motion on Home: the workspace changing with the split, Manage folding the
// week away, and the split switcher's name, chevron and menu.

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open(includeSplits: true);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  const switcher = ValueKey('split-switcher-button');

  /// How visible [finder] is through the fades Home itself draws, leaving
  /// out the route's own transition.
  double homeOpacity(WidgetTester tester, Finder finder) {
    final inHome =
        find
            .descendant(
              of: find.byType(HomeScreen),
              matching: find.byType(FadeTransition),
            )
            .evaluate()
            .toSet();
    var opacity = 1.0;
    for (final element
        in find
            .ancestor(of: finder, matching: find.byType(FadeTransition))
            .evaluate()) {
      if (!inHome.contains(element)) continue;
      opacity *= (element.widget as FadeTransition).opacity.value;
    }
    return opacity;
  }

  Future<void> chooseSplit(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(switcher));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
  }

  group('changing split', () {
    testWidgets('fades the new workspace in once, in the tree from its first '
        'frame, without the old one crossing', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));
      expect(homeOpacity(tester, find.text('PPL Plan').first), 1);

      await chooseSplit(tester, 'UL');
      await tester.pump();
      // The old split's plans are gone at once, not leaving alongside.
      expect(find.text('PPL Plan', skipOffstage: false), findsNothing);
      expect(find.text('UL Plan'), findsWidgets);
      expect(find.text('UL Plan').first.hitTestable(), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      final midway = homeOpacity(tester, find.text('UL Plan').first);
      expect(midway, greaterThan(0));
      expect(midway, lessThan(1));

      await tester.pump(AppMotion.standard);
      expect(homeOpacity(tester, find.text('UL Plan').first), 1);
      await tester.pumpAndSettle();

      // A rebuild with the same split replays nothing.
      harness.splits.loadSplits();
      harness.plans.loadPlans();
      await tester.pump();
      expect(homeOpacity(tester, find.text('UL Plan').first), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('its first frame paints the new workspace at the floor, not '
        'at nothing', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));

      await chooseSplit(tester, 'UL');
      await tester.pump();
      // A fade from zero would spend this frame on the bare page.
      expect(
        homeOpacity(tester, find.text('UL Plan').first),
        closeTo(SurfaceFade.floor, 1e-6),
      );
      await tester.pump(AppMotion.quick);
      expect(homeOpacity(tester, find.text('UL Plan').first), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('lands at once under reduced motion', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.host(const HomeScreen(), disableAnimations: true),
      );

      await chooseSplit(tester, 'UL');
      await tester.pump();
      expect(homeOpacity(tester, find.text('UL Plan').first), 1);
    });

    testWidgets('a split changed while another tab shows simply lands', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen(active: false)));

      await tester.runAsync(() => harness.splits.setActiveSplit('ul'));
      await tester.pump();
      expect(homeOpacity(tester, find.text('UL Plan').first), 1);
    });

    testWidgets('a split changed under a page plays nothing on the way back', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));

      final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();

      await tester.runAsync(() => harness.splits.setActiveSplit('ul'));
      await tester.pump();
      navigator.pop();
      await tester.pump();
      expect(
        homeOpacity(tester, find.text('UL Plan', skipOffstage: false).first),
        1,
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(homeOpacity(tester, find.text('UL Plan').first), 1);
      await tester.pumpAndSettle();
    });
  });

  group('Manage', () {
    testWidgets('folds the week away so the plans rise, then unfolds it', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));
      final heading = find.text('Your plans');
      final atRest = tester.getTopLeft(heading).dy;

      await tester.tap(find.text('Manage'));
      await tester.pump();
      // Nothing has jumped: the summary is still there, on its way out, and
      // takes no taps; the cards arriving can be tapped already.
      expect(tester.getTopLeft(heading).dy, atRest);
      expect(find.text('Next up'), findsOneWidget);
      expect(find.text('Next up').hitTestable(), findsNothing);
      expect(find.byType(PlanCard).hitTestable(), findsOneWidget);
      expect(find.byType(HomePlanRow).hitTestable(), findsNothing);

      await tester.pump(const Duration(milliseconds: 90));
      final midway = tester.getTopLeft(heading).dy;
      expect(midway, lessThan(atRest));

      await tester.pumpAndSettle();
      final managing = tester.getTopLeft(heading).dy;
      expect(managing, lessThan(midway));
      expect(find.text('Next up'), findsNothing);
      expect(find.byType(HomePlanRow), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Manage'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(tester.getTopLeft(heading).dy, managing);
      // The summary is back in the tree from the first frame, growing open
      // from no height (so a finder counts it offstage until it has some).
      expect(find.text('Next up', skipOffstage: false), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(heading).dy, greaterThan(managing));
      expect(tester.getTopLeft(heading).dy, lessThan(atRest));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(heading).dy, atRest);
      expect(find.byType(PlanCard), findsNothing);
      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('changes at once under reduced motion', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.host(const HomeScreen(), disableAnimations: true),
      );

      await tester.tap(find.text('Manage'));
      await tester.pump();
      expect(find.text('Next up'), findsNothing);
      expect(find.byType(HomePlanRow), findsNothing);
      expect(find.text('Manage'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('cleared by the app, it settles at once rather than unfolding '
        'out of sight', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      var active = true;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return harness.host(HomeScreen(active: active));
          },
        ),
      );
      final heading = find.text('Your plans');
      final atRest = tester.getTopLeft(heading).dy;
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();

      update(() => active = false);
      await tester.pump();
      expect(tester.getTopLeft(heading).dy, atRest);
      expect(find.text('Next up').hitTestable(), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(find.byType(PlanCard), findsNothing);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(heading).dy, atRest);
    });
  });

  group('split switcher', () {
    testWidgets('the name crosses while its width eases', (tester) async {
      final harness =
          (await tester.runAsync(
            () => _createHarness(splitNames: const ['PPL', 'Upper lower']),
          ))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));
      final before = tester.getSize(find.byKey(switcher)).width;

      await chooseSplit(tester, 'Upper lower');
      await tester.pumpAndSettle();
      final after = tester.getSize(find.byKey(switcher)).width;
      expect(after, greaterThan(before));

      await chooseSplit(tester, 'PPL');
      await tester.pump();
      // The longer name holds its room while it fades, then the room eases
      // in to the shorter one.
      final widths = <double>[];
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        widths.add(tester.getSize(find.byKey(switcher)).width);
      }
      expect(
        widths.where((width) => width > before && width < after),
        isNotEmpty,
        reason: 'the switcher passes through widths between the two names',
      );
      for (var index = 1; index < widths.length; index++) {
        expect(widths[index], lessThanOrEqualTo(widths[index - 1]));
      }
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(switcher)).width, before);
      expect(
        find.descendant(
          of: find.byKey(switcher),
          matching: find.text('Upper lower'),
        ),
        findsNothing,
      );
    });

    testWidgets('the chevron turns as the menu opens and closes', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));
      double turns() =>
          tester
              .widget<RotationTransition>(
                find.descendant(
                  of: find.byKey(switcher),
                  matching: find.byType(RotationTransition),
                ),
              )
              .turns
              .value;
      final closed = turns();

      await tester.tap(find.byKey(switcher));
      await tester.pump();
      await tester.pump(AppMotion.quick ~/ 2);
      final midway = turns();
      expect(midway, isNot(closed));
      await tester.pump(AppMotion.quick ~/ 2);
      final open = turns();
      expect((open - closed).abs(), greaterThan((midway - closed).abs()));
      await tester.pumpAndSettle();
      expect(turns(), open);

      await tester.tap(find.byKey(switcher));
      await tester.pump();
      await tester.pump(AppMotion.quick ~/ 2);
      expect(turns(), isNot(open));
      expect(turns(), isNot(closed));
      await tester.pumpAndSettle();
      expect(turns(), closed);
    });

    testWidgets('the menu settles out of the name once per opening', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));
      final menu = find.byKey(const ValueKey('split-menu'));

      double scaleOf() {
        var scale = 1.0;
        for (final element
            in find
                .ancestor(of: menu, matching: find.byType(ScaleTransition))
                .evaluate()) {
          scale *= (element.widget as ScaleTransition).scale.value;
        }
        return scale;
      }

      double opacityOf() {
        var opacity = 1.0;
        for (final element
            in find
                .ancestor(of: menu, matching: find.byType(FadeTransition))
                .evaluate()) {
          opacity *= (element.widget as FadeTransition).opacity.value;
        }
        return opacity;
      }

      await tester.tap(find.byKey(switcher));
      await tester.pump();
      // In the tree and tappable from the first frame.
      expect(find.text('UL').hitTestable(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacityOf(), inExclusiveRange(0, 1));
      expect(scaleOf(), inExclusiveRange(AppMotion.scale, 1));
      await tester.pumpAndSettle();
      expect(opacityOf(), 1);
      expect(scaleOf(), 1);

      // Rebuilding while open replays nothing.
      harness.splits.loadSplits();
      await tester.pump();
      expect(opacityOf(), 1);
      expect(scaleOf(), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Closing is immediate.
      await tester.tap(find.byKey(switcher));
      await tester.pump();
      expect(menu, findsNothing);
      await tester.pumpAndSettle();

      // A new opening plays again.
      await tester.tap(find.byKey(switcher));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacityOf(), lessThan(1));
      await tester.pumpAndSettle();
    });

    testWidgets('the menu simply appears under reduced motion', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.host(const HomeScreen(), disableAnimations: true),
      );
      await tester.tap(find.byKey(switcher));
      await tester.pump();
      final menu = find.byKey(const ValueKey('split-menu'));
      for (final element
          in find
              .ancestor(of: menu, matching: find.byType(FadeTransition))
              .evaluate()) {
        expect((element.widget as FadeTransition).opacity.value, 1);
      }
      for (final element
          in find
              .ancestor(of: menu, matching: find.byType(ScaleTransition))
              .evaluate()) {
        expect((element.widget as ScaleTransition).scale.value, 1);
      }
      expect(
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: find.byKey(switcher),
                matching: find.byType(AnimatedRotation),
              ),
            )
            .duration,
        Duration.zero,
      );
    });
  });

  group('preset browser', () {
    const details = ValueKey('preset-details-HYP-FB-3');
    const catalog = ValueKey('preset-catalog');
    const install = ValueKey('install-preset-action');
    final heading = find.descendant(
      of: find.byKey(details),
      matching: find.text('Full-body hypertrophy'),
    );

    Future<void> openBrowser(WidgetTester tester) async {
      await tester.tap(find.byKey(switcher));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
    }

    testWidgets('a preset\'s details arrive from the end side, with its '
        'install bar, and going back reverses it', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));
      await openBrowser(tester);
      final catalogCard = find.descendant(
        of: find.byKey(catalog),
        matching: find.text('Full-body hypertrophy'),
      );
      final cardAtRest = tester.getTopLeft(catalogCard).dx;

      await tester.tap(catalogCard);
      await tester.pump();
      // Both pages are in the tree; only the arriving one takes taps.
      expect(find.byKey(details).hitTestable(), findsOneWidget);
      expect(find.byKey(catalog), findsOneWidget);
      expect(find.byKey(catalog).hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(catalogCard).dx, lessThan(cardAtRest));
      final headingMidway = tester.getTopLeft(heading).dx;
      final installMidway = tester.getTopLeft(find.byKey(install)).dx;
      await tester.pumpAndSettle();
      expect(headingMidway, greaterThan(tester.getTopLeft(heading).dx));
      expect(
        installMidway,
        greaterThan(tester.getTopLeft(find.byKey(install)).dx),
      );
      // At rest the catalog is offstage but alive.
      expect(find.byKey(catalog), findsNothing);
      expect(find.byKey(catalog, skipOffstage: false), findsOneWidget);

      await tester.tap(find.byTooltip('Back to workout presets'));
      await tester.pump();
      expect(find.byKey(catalog).hitTestable(), findsOneWidget);
      expect(find.byKey(details).hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(catalogCard).dx, lessThan(cardAtRest));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(catalogCard).dx, cardAtRest);
      expect(find.byKey(details, skipOffstage: false), findsNothing);
      expect(find.byKey(install, skipOffstage: false), findsNothing);
    });

    testWidgets('the page simply changes under reduced motion', (tester) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.host(const HomeScreen(), disableAnimations: true),
      );
      await openBrowser(tester);
      await tester.tap(find.text('Full-body hypertrophy'));
      await tester.pump();
      expect(find.byKey(catalog), findsNothing);
      final atOnce = tester.getTopLeft(heading).dx;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(heading).dx, atOnce);

      await tester.tap(find.byTooltip('Back to workout presets'));
      await tester.pump();
      expect(find.byKey(catalog), findsOneWidget);
      expect(find.byKey(details, skipOffstage: false), findsNothing);
    });

    testWidgets('a workout day folds open and away on the tokens', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_createHarness))!;
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.host(const HomeScreen()));
      await openBrowser(tester);
      await tester.tap(find.text('Full-body hypertrophy'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Full body A'),
        200,
        scrollable:
            find
                .descendant(
                  of: find.byKey(details),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      final day = find.ancestor(
        of: find.text('Full body A'),
        matching: find.byType(InkWell),
      );
      double turns() =>
          tester
              .widget<RotationTransition>(
                find.descendant(
                  of: day.first,
                  matching: find.byType(RotationTransition),
                ),
              )
              .turns
              .value;
      expect(turns(), 0);

      await tester.tap(find.text('Full body A'));
      await tester.pump();
      expect(find.text('3 × 6–10', skipOffstage: false), findsOneWidget);
      // The chevron turns with the fold, within the quick time.
      await tester.pump(AppMotion.quick ~/ 2);
      expect(turns(), inExclusiveRange(0, 0.5));
      await tester.pump(AppMotion.quick ~/ 2);
      expect(turns(), 0.5);
      await tester.pumpAndSettle();
      expect(find.text('3 × 6–10'), findsOneWidget);

      await tester.tap(find.text('Full body A'));
      await tester.pump();
      // Folding away, it is still there until it has gone.
      expect(find.text('3 × 6–10', skipOffstage: false), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('3 × 6–10', skipOffstage: false), findsNothing);
    });
  });
}

Future<_Harness> _createHarness({
  List<String> splitNames = const ['PPL', 'UL'],
}) async {
  final now = DateTime(2026);
  final splits = [
    for (var index = 0; index < splitNames.length; index++)
      gym.Split(
        id: index == 0 ? 'ppl' : 'ul',
        name: splitNames[index],
        userId: 'user-1',
        createdAt: now.add(Duration(minutes: index)),
      ),
  ];
  for (final split in splits) {
    final name = '${split.id.toUpperCase()} Plan';
    await HiveService.putPlanRaw(
      WorkoutPlan(
        id: '${split.id}-plan',
        splitId: split.id,
        name: name,
        exercises: [],
      ),
    );
    await HiveService.putSessionRaw(
      WorkoutSession(
        id: '${split.id}-session',
        splitId: split.id,
        date: DateTime.now().subtract(const Duration(days: 1)),
        planName: name,
        exercises: [
          Exercise(name: 'Squat', sets: [Set(reps: 5, weight: 80)]),
        ],
        isCompleted: true,
      ),
    );
  }
  final provider = SplitProvider(
    repository: _FakeSplitRepository(splits, splits.first.id),
    userIdProvider: () => 'user-1',
  );
  return _Harness(
    provider,
    WorkoutPlanProvider(provider),
    WorkoutSessionProvider(provider),
  );
}

class _Harness {
  final SplitProvider splits;
  final WorkoutPlanProvider plans;
  final WorkoutSessionProvider sessions;

  const _Harness(this.splits, this.plans, this.sessions);

  Widget host(Widget child, {bool disableAnimations = false}) {
    const size = Size(390, 800);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SplitProvider>.value(value: splits),
        ChangeNotifierProvider<WorkoutPlanProvider>.value(value: plans),
        ChangeNotifierProvider<WorkoutSessionProvider>.value(value: sessions),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
        // Dialogs sit above `home`, so they take reduced motion from here.
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disableAnimations),
              child: child!,
            ),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                disableAnimations: disableAnimations,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

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
  Future<void> setActive(String userId, String splitId) async {
    preference = SplitPreference(userId: userId, activeSplitId: splitId);
  }
}
