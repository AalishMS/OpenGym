import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/motion/entrance.dart';
import 'package:gymapp/widgets/statistics/block_statistics.dart';
import 'package:gymapp/widgets/statistics/block_trend.dart';
import 'package:gymapp/widgets/statistics/lift_list.dart';
import 'package:gymapp/widgets/statistics/statistics_controls.dart';
import 'package:gymapp/widgets/statistics/statistics_widgets.dart';
import 'package:gymapp/widgets/statistics/strength_trend.dart';
import 'package:gymapp/widgets/statistics/training_overview.dart';

import 'support/test_fonts.dart';

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> values;
  _Sessions(this.values);
  @override
  void loadSessions() {}
  @override
  List<WorkoutSession> get sessions => values;
}

const _accent = Color(0xFF41B9B9);

/// The app's theme, with reduced motion when [reduced].
Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: buildTheme(_accent, Brightness.light),
  home: Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child,
        ),
  ),
);

/// Keeps one app for a whole test and swaps what it shows, so a change
/// updates the widget in place, as a rebuild in the app would, instead of
/// pumping a new app around it.
class _Host {
  final ValueNotifier<Widget> _child = ValueNotifier(const SizedBox.shrink());
  bool _shown = false;

  /// Shows [child] and pumps one frame.
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool reduced = false,
  }) async {
    _child.value = child;
    if (_shown) return tester.pump();
    _shown = true;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ValueListenableBuilder<Widget>(
            valueListenable: _child,
            builder: (context, child, _) => child,
          ),
        ),
        reduced: reduced,
      ),
    );
  }
}

void main() {
  setUpAll(loadTestFonts);

  final thisWeek = StatisticsAnalyticsService.startOfWeek(DateTime.now());

  WorkoutSession workout(
    String id,
    int daysAgo,
    double weight, {
    String exercise = 'Bench press',
  }) => WorkoutSession(
    id: id,
    planName: 'Push',
    date: thisWeek.subtract(Duration(days: daysAgo)),
    isCompleted: true,
    exercises: [
      Exercise(name: exercise, sets: [gym.Set(weight: weight, reps: 8)]),
    ],
  );

  void phone(WidgetTester tester, {double height = 900}) {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Stats views', () {
    final provider = _Sessions([
      for (var week = 0; week < 8; week++)
        workout('w$week', week * 7, 40.0 + week),
    ]);

    Widget stats({
      Key? key,
      int visit = 0,
      int weekly = 0,
      bool reduced = false,
    }) => ChangeNotifierProvider<WorkoutSessionProvider>.value(
      value: provider,
      child: _app(
        Scaffold(
          body: StatsScreen(
            key: key,
            visitRequest: visit,
            weeklyTrainingRequest: weekly,
          ),
        ),
        reduced: reduced,
      ),
    );

    final pages = find.byKey(const ValueKey('statistics-scroll'));

    testWidgets('trade places in the direction of travel and settle', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(stats());
      await tester.pumpAndSettle();
      expect(pages, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('statistics-tab-Strength')));
      await tester.pump();
      // Both pages share the place while they cross; the arriving one is
      // there, tappable, from its first frame.
      expect(pages, findsNWidgets(2));
      expect(find.text('Latest workout'), findsOneWidget);
      expect(find.text('Latest workout').hitTestable(), findsOneWidget);
      // The leaving page takes no taps.
      expect(find.text('Weekly training').hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 80));
      // Going forward, the new page arrives from the end side.
      expect(tester.getTopLeft(pages.last).dx, greaterThan(0));
      await tester.pumpAndSettle();
      expect(pages, findsOneWidget);
      expect(tester.getTopLeft(pages).dx, 0);

      await tester.tap(find.byKey(const ValueKey('statistics-tab-Overview')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // Going back, it arrives from the start side.
      expect(tester.getTopLeft(pages.last).dx, lessThan(0));
      await tester.pumpAndSettle();
      expect(pages, findsOneWidget);
      expect(find.text('Weekly training'), findsOneWidget);
    });

    testWidgets('the leaving page says nothing to screen readers', (
      tester,
    ) async {
      phone(tester);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(stats());
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('Weekly training'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('statistics-tab-Records')));
      await tester.pump();
      expect(find.semantics.byLabel('Weekly training'), findsNothing);
      // The arriving page is announced before it can be seen.
      expect(find.semantics.byLabel('Personal bests'), findsOneWidget);
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets(
      'the leaving page keeps its place; the next starts at the top',
      (tester) async {
        phone(tester, height: 600);
        await tester.pumpWidget(stats());
        await tester.pumpAndSettle();
        tester.widget<SingleChildScrollView>(pages).controller!.jumpTo(200);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('statistics-tab-Strength')));
        await tester.pump();
        // Each page scrolls on a controller of its own, so neither moves the
        // other while they cross.
        final controllers = [
          for (final page in tester.widgetList<SingleChildScrollView>(pages))
            page.controller!,
        ];
        expect(controllers.map((controller) => controller.positions.length), [
          1,
          1,
        ]);
        expect(controllers.map((controller) => controller.offset), [200, 0]);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SingleChildScrollView>(pages).controller!.offset,
          0,
        );
      },
    );

    testWidgets('on desktop, a view change while the scrollbar fades is safe', (
      tester,
    ) async {
      // Each page owns its scroll position: the leaving and arriving pages
      // never share one controller, which the desktop scrollbar reads.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        phone(tester, height: 600);
        await tester.pumpWidget(stats());
        await tester.pumpAndSettle();
        await tester.drag(pages, const Offset(0, -200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        await tester.tap(find.byKey(const ValueKey('statistics-tab-Strength')));
        await tester.pump();
        // The scrollbar's fade-out timer fires while the pages cross.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pages, findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a swipe within the tab trades places; entering does not', (
      tester,
    ) async {
      phone(tester);
      final key = GlobalKey<StatsScreenState>();
      await tester.pumpWidget(stats(key: key));
      await tester.pumpAndSettle();

      expect(key.currentState!.handleSectionSwipe(forward: true), isTrue);
      await tester.pump();
      expect(pages, findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(find.text('Latest workout'), findsOneWidget);

      // Entering the tab from History: the tab's own fade carries it.
      expect(
        key.currentState!.handleSectionSwipe(forward: true, entering: true),
        isTrue,
      );
      await tester.pump();
      expect(pages, findsOneWidget);
      expect(find.text('Weekly training'), findsOneWidget);
      expect(tester.getTopLeft(pages).dx, 0);
    });

    testWidgets('returning to the tab and the Home shortcut replay nothing', (
      tester,
    ) async {
      phone(tester);
      final key = GlobalKey<StatsScreenState>();
      await tester.pumpWidget(stats(key: key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-tab-Strength')));
      await tester.pumpAndSettle();

      // A tab return keeps the view, with no arrival.
      await tester.pumpWidget(stats(key: key, visit: 1));
      await tester.pump();
      expect(pages, findsOneWidget);
      expect(tester.getTopLeft(pages).dx, 0);
      expect(find.text('Latest workout'), findsOneWidget);

      // The Home shortcut opens Overview at once.
      await tester.pumpWidget(stats(key: key, visit: 1, weekly: 1));
      await tester.pump();
      expect(pages, findsOneWidget);
      expect(find.text('Week in progress'), findsOneWidget);
      expect(tester.getTopLeft(pages).dx, 0);
    });

    testWidgets('reduced motion changes view at once', (tester) async {
      phone(tester);
      await tester.pumpWidget(stats(reduced: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-tab-Records')));
      await tester.pump();
      expect(pages, findsOneWidget);
      expect(find.text('Personal bests'), findsOneWidget);
      expect(find.text('Weekly training'), findsNothing);
    });
  });

  group('Overview bars', () {
    List<WeeklyTrainingValue> weeks(List<double> volumes) => [
      for (var i = 0; i < volumes.length; i++)
        WeeklyTrainingValue(
          weekStart: thisWeek.subtract(
            Duration(days: 7 * (volumes.length - 1 - i)),
          ),
          volumeLoad: volumes[i],
        ),
    ];

    Widget overview(List<WeeklyTrainingValue> weeks, {String? exercise}) =>
        SingleChildScrollView(
          child: TrainingOverview(
            sessions: const [],
            weeks: weeks,
            exercise: exercise,
            weightUnit: 'kg',
            onChooseExercise: () {},
          ),
        );

    final bars = find.descendant(
      of: find.byKey(const ValueKey('training-timeline')),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 26,
      ),
    );
    List<double> heights(WidgetTester tester) => [
      for (final element in bars.evaluate())
        (element.renderObject! as RenderBox).size.height,
    ];

    testWidgets('appear at their heights on the first frame', (tester) async {
      final host = _Host();
      phone(tester);
      await host.show(tester, overview(weeks([100, 200, 300])));
      final first = heights(tester);
      expect(first, everyElement(greaterThan(3)));
      await tester.pumpAndSettle();
      expect(heights(tester), first);
    });

    testWidgets('ease to a new exercise and grow new weeks from the baseline', (
      tester,
    ) async {
      final host = _Host();
      phone(tester);
      await host.show(tester, overview(weeks([100, 200, 300])));
      await tester.pumpAndSettle();
      final before = heights(tester);

      await host.show(
        tester,
        overview(weeks([300, 100, 200]), exercise: 'Bench press'),
      );
      await tester.pump();
      // The readout lands at once: the new week's exact value is there.
      expect(find.text('100 kg'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      final midway = heights(tester);
      await tester.pumpAndSettle();
      final after = heights(tester);
      expect(after[0], greaterThan(before[0]));
      expect(midway[0], greaterThan(before[0]));
      expect(midway[0], lessThan(after[0]));
      expect(midway[1], lessThan(before[1]));
      expect(midway[1], greaterThan(after[1]));

      // A week that joins the plot grows from the baseline; the rest keep
      // their bars and so do not grow again.
      await host.show(
        tester,
        overview(weeks([150, 300, 100, 200]), exercise: 'Bench press'),
      );
      await tester.pump();
      final joined = heights(tester);
      expect(joined[0], 0);
      expect(joined[1], closeTo(after[0], 0.01));
      await tester.pumpAndSettle();
      expect(heights(tester)[0], greaterThan(0));
    });

    testWidgets('the selected week eases its emphasis; another exercise '
        'starts again from the default week', (tester) async {
      final host = _Host();
      phone(tester);
      await host.show(tester, overview(weeks([100, 200, 300, 250])));
      await tester.pumpAndSettle();
      final context = tester.element(bars.first);
      Color? colorOf(int index) {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: bars.at(index),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      expect(colorOf(0), accentDimColor(context));
      await tester.tap(find.byKey(const ValueKey('training-week-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(colorOf(0), isNot(accentDimColor(context)));
      expect(colorOf(0), isNot(accentFillColor(context)));
      await tester.pumpAndSettle();
      expect(colorOf(0), accentFillColor(context));
      expect(find.textContaining('Selected week'), findsOneWidget);

      await host.show(
        tester,
        overview(weeks([100, 200, 300, 250]), exercise: 'Bench press'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Last week'), findsOneWidget);
    });

    testWidgets('under reduced motion bars change at once', (tester) async {
      final host = _Host();
      phone(tester);
      await host.show(tester, overview(weeks([100, 200, 300])), reduced: true);
      await tester.pumpAndSettle();
      await host.show(
        tester,
        overview(weeks([300, 100, 200]), exercise: 'Row'),
        reduced: true,
      );
      await tester.pump();
      final now = heights(tester);
      await tester.pumpAndSettle();
      expect(heights(tester), now);
    });
  });

  group('Strength plot', () {
    const analytics = StatisticsAnalyticsService();
    final data = [
      workout('a', 14, 40),
      workout('b', 7, 50),
      workout('c', 0, 60),
    ];

    Widget trend(Object dataset, ExerciseMetric metric) =>
        SingleChildScrollView(
          child: StrengthTrend(
            dataset: dataset,
            progress: analytics.exerciseProgress(data, 'Bench press', metric),
            metric: metric,
            weightUnit: 'kg',
          ),
        );

    final timelines = find.byKey(const ValueKey('strength-timeline'));

    testWidgets('crosses to a new dataset while its figures land at once', (
      tester,
    ) async {
      final host = _Host();
      phone(tester);
      await host.show(tester, trend('e1rm', ExerciseMetric.estimatedOneRepMax));
      await tester.pumpAndSettle();
      // The readout and Best in period.
      expect(find.text('76 kg'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('strength-point-0')));
      await tester.pumpAndSettle();
      expect(find.text('Selected workout'), findsOneWidget);
      await host.show(tester, trend('best', ExerciseMetric.bestWeight));
      await tester.pump();
      // The plot crosses, and only the arriving one takes taps.
      expect(timelines, findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('strength-point-2')).hitTestable(),
        findsOneWidget,
      );
      // A new dataset starts at its latest workout, and its figure is
      // simply there: no roll from a value it can't be compared with.
      expect(find.text('Latest workout'), findsOneWidget);
      expect(find.text('60 kg'), findsWidgets);
      expect(find.text('76 kg'), findsNothing);
      await tester.pumpAndSettle();
      expect(timelines, findsOneWidget);
    });

    testWidgets('the same dataset updates in place', (tester) async {
      final host = _Host();
      phone(tester);
      await host.show(tester, trend('e1rm', ExerciseMetric.estimatedOneRepMax));
      await tester.pumpAndSettle();
      await host.show(tester, trend('e1rm', ExerciseMetric.estimatedOneRepMax));
      await tester.pump();
      expect(timelines, findsOneWidget);
    });

    testWidgets('under reduced motion the plot changes at once', (
      tester,
    ) async {
      final host = _Host();
      phone(tester);
      await host.show(
        tester,
        trend('e1rm', ExerciseMetric.estimatedOneRepMax),
        reduced: true,
      );
      await tester.pumpAndSettle();
      await host.show(
        tester,
        trend('best', ExerciseMetric.bestWeight),
        reduced: true,
      );
      await tester.pump();
      expect(timelines, findsOneWidget);
    });
  });

  group('Blocks', () {
    BlockStatistics block(int i, {int gains = 1}) => BlockStatistics(
      block: TrainingBlock(
        id: '$i',
        splitId: 'test',
        name: 'Block ${i + 1}',
        position: i,
        createdAt: DateTime(2026),
        plannedWeekCount: 2,
      ),
      weeks: [
        for (var n = 1; n <= 2; n++)
          BlockWeekStatistics(
            weekId: '$i-$n',
            number: n,
            workouts: 2,
            sets: (i + n) * 10,
            volumeLoad: (i + 1) * 500.0,
          ),
      ],
      workouts: 4,
      sets: (i + 1) * 20,
      volumeLoad: (i + 1) * 1000,
      records: (i + 1) * 2,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2026, 1, 14),
      latestWeekId: '$i-2',
      gains: [
        for (var g = 0; g < gains; g++)
          LiftGain(exerciseName: 'Lift $g', start: 80, end: 90.0 + g),
      ],
    );

    final blocks = [block(0), block(1), block(2, gains: 5)];
    final plots = find.byKey(const ValueKey('block-trend-scroll'));

    Widget chart(BlockTrendMeasure measure, String selected) => BlockTrendChart(
      blocks: blocks,
      selectedId: selected,
      measure: measure,
      perWeek: true,
      weightUnit: 'kg',
      onSelect: (_) {},
    );

    testWidgets('a new measure crosses the plot; a new block does not', (
      tester,
    ) async {
      final host = _Host();
      phone(tester);
      await host.show(tester, chart(BlockTrendMeasure.volume, '2'));
      await tester.pumpAndSettle();
      await host.show(tester, chart(BlockTrendMeasure.volume, '0'));
      await tester.pump();
      expect(plots, findsOneWidget);
      await host.show(tester, chart(BlockTrendMeasure.sets, '0'));
      await tester.pump();
      expect(plots, findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(plots, findsOneWidget);
    });

    testWidgets('gains fold open, their chevrons turn, and the rest follow', (
      tester,
    ) async {
      phone(tester, height: 2000);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: BlockOverview(
                blocks: blocks,
                selected: blocks.last,
                currentBlockId: '2',
                onSelect: (_) {},
                weightUnit: 'kg',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gain = find.byKey(const ValueKey('block-gain-Lift 0'));
      final endpoints = find.text('80 kg to 90 kg');
      final showAll = find.text('Show all 5 lifts');
      expect(endpoints, findsNothing);
      final before = tester.getTopLeft(showAll).dy;

      await tester.tap(gain);
      await tester.pump();
      // In the tree from the first frame, folding open from the top.
      expect(endpoints, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      final midway = tester.getTopLeft(showAll).dy;
      final turn =
          tester
              .widget<AnimatedRotation>(
                find.descendant(
                  of: gain,
                  matching: find.byType(AnimatedRotation),
                ),
              )
              .turns;
      expect(turn, 0.5);
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(showAll).dy;
      expect(midway, greaterThan(before));
      expect(midway, lessThan(after));

      await tester.tap(showAll);
      await tester.pump();
      expect(find.byKey(const ValueKey('block-gain-Lift 4')), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show fewer lifts'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('block-gain-Lift 4')), findsNothing);
    });
  });

  testWidgets('the lift list folds its rest open around a pinned selection', (
    tester,
  ) async {
    phone(tester, height: 1600);
    const analytics = StatisticsAnalyticsService();
    final sessions = [
      for (var i = 0; i < 8; i++)
        workout('lift-$i', i, 50.0 + i, exercise: 'Lift $i'),
    ];
    final lifts = analytics.liftSummaries(
      sessions,
      ExerciseMetric.estimatedOneRepMax,
    );
    expect(lifts, hasLength(8));
    final pinned = lifts[6];
    String id(LiftSummary lift) => lift.exerciseId ?? lift.exerciseName;
    Finder row(int index) => find.byKey(ValueKey('lift-${id(lifts[index])}'));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: LiftList(
              lifts: lifts,
              selected: id(pinned),
              metric: ExerciseMetric.estimatedOneRepMax,
              weightUnit: 'kg',
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(row(5), findsNothing);
    expect(row(6), findsOneWidget);
    expect(row(7), findsNothing);

    await tester.tap(find.text('Show all 8 lifts'));
    await tester.pump();
    expect(row(5), findsOneWidget);
    expect(row(7), findsOneWidget);
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0.5,
    );
    await tester.pumpAndSettle();
    final order = [for (var i = 4; i < 8; i++) tester.getTopLeft(row(i)).dy];
    expect(order, orderedEquals([...order]..sort()));

    await tester.tap(find.text('Show fewer'));
    await tester.pump();
    // Folding away, the rows are still there until they have gone.
    expect(row(5), findsOneWidget);
    await tester.pumpAndSettle();
    expect(row(5), findsNothing);
    expect(row(6), findsOneWidget);
  });

  testWidgets('record tags fold open, moving the rows below', (tester) async {
    phone(tester);
    const achievement = RecordAchievement(
      type: RecordType.heaviestWeight,
      value: 100,
      setWeight: 100,
      setReps: 3,
    );
    final event = RecordEvent(
      session: workout('r', 0, 100),
      exerciseName: 'Bench press',
      achievements: [
        achievement,
        const RecordAchievement(
          type: RecordType.estimatedOneRepMax,
          value: 110,
          setWeight: 100,
          setReps: 3,
        ),
        const RecordAchievement(
          type: RecordType.setVolume,
          value: 300,
          setWeight: 100,
          setReps: 3,
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: [
              RecordEventRow(event: event, weightUnit: 'kg'),
              const Text('Below'),
            ],
          ),
        ),
      ),
    );
    final before = tester.getTopLeft(find.text('Below')).dy;
    await tester.tap(find.text('+2 more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.getTopLeft(find.text('Below')).dy;
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('Below')).dy;
    expect(midway, greaterThan(before));
    expect(midway, lessThan(after));
  });

  testWidgets(
    'earlier records arrive once; returning to Records replays none',
    (tester) async {
      phone(tester);
      // Each workout lifts more than the last, so each sets a record.
      final provider = _Sessions([
        for (var i = 0; i <= 20; i++) workout('rec-$i', i, 100.0 - i),
      ]);
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkoutSessionProvider>.value(
          value: provider,
          child: _app(const Scaffold(body: StatsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-tab-Records')));
      await tester.pumpAndSettle();

      final entrances = find.byType(Entrance);
      double opacity(int index) =>
          tester
              .widget<FadeTransition>(
                find
                    .descendant(
                      of: entrances.at(index),
                      matching: find.byType(FadeTransition),
                    )
                    .first,
              )
              .opacity
              .value;

      expect(entrances, findsNWidgets(12));
      final button = find.text('Show earlier records');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      expect(entrances, findsNWidgets(20));
      // The rows that were there stay; the revealed ones arrive.
      expect(opacity(0), 1);
      expect(opacity(11), 1);
      expect(opacity(12), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacity(19), 1);

      await tester.tap(find.byKey(const ValueKey('statistics-tab-Overview')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-tab-Records')));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        expect(opacity(i), 1, reason: 'row $i replayed its arrival');
      }
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a pill\'s ground and label settle together', (tester) async {
    phone(tester);
    var selected = StatisticsPeriod.fourWeeks;
    late StateSetter update;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SegmentedPills<StatisticsPeriod>(
                keyPrefix: 'period',
                values: StatisticsPeriod.values,
                selected: selected,
                labelFor: (period) => period.shortLabel,
                onSelected: (_) {},
              );
            },
          ),
        ),
      ),
    );
    final context = tester.element(
      find.byType(SegmentedPills<StatisticsPeriod>),
    );
    final pill = find.byKey(const ValueKey('period-StatisticsPeriod.oneYear'));
    Color? ground() =>
        (tester
                    .widget<Container>(
                      find.descendant(
                        of: pill,
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration
                as BoxDecoration?)
            ?.color;
    Color? label() =>
        tester
            .widget<DefaultTextStyle>(
              find
                  .descendant(of: pill, matching: find.byType(DefaultTextStyle))
                  .last,
            )
            .style
            .color;

    update(() => selected = StatisticsPeriod.oneYear);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(ground(), isNot(accentFillColor(context)));
    expect(label(), isNot(onAccentColor(context)));
    expect(label(), isNot(textSecondaryColor(context)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ground(), accentFillColor(context));
    expect(label(), onAccentColor(context));
  });
}
