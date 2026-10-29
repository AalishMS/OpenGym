import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/statistics/statistics_widgets.dart';
import 'package:gymapp/widgets/statistics/training_charts.dart';
import 'package:gymapp/utils/statistics_format.dart';

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> data;
  _Sessions(this.data);
  @override
  void loadSessions() {}
  @override
  List<WorkoutSession> get sessions => data;
}

void main() {
  const analytics = StatisticsAnalyticsService();
  final now = DateTime(2026, 9, 5);
  WorkoutSession session(
    String id,
    DateTime date, {
    String split = 'a',
    bool completed = true,
    DateTime? deleted,
    String name = 'Bench press',
  }) => WorkoutSession(
    id: id,
    date: date,
    splitId: split,
    isCompleted: completed,
    deletedAt: deleted,
    planName: 'Push day',
    exercises: [
      Exercise(
        name: name,
        sets: [gym.Set(weight: 80, reps: 5), gym.Set(weight: 90, reps: 0)],
      ),
      Exercise(name: 'Overhead press', sets: [gym.Set(weight: 40, reps: 10)]),
    ],
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test(
    'weekly volume filters individual sets, fills gaps, and excludes ineligible data',
    () {
      final data = [
        session('first', DateTime(2026, 8, 17), name: ' BENCH PRESS '),
        session('last', now),
        session('other-split', now, split: 'b'),
        session('draft', now, completed: false),
        session('deleted', now, deleted: now),
      ];
      final weeks = analytics.weeklyVolume(
        data,
        exerciseName: 'Bench press',
        splitId: 'a',
        now: now,
      );
      expect(weeks.map((week) => week.volumeLoad), [400, 0, 400]);
      expect(
        analytics
            .weeklyVolume(data, splitId: 'a', now: now)
            .map((week) => week.volumeLoad),
        [800, 0, 800],
      );
      expect(analytics.exerciseNames(data), ['Bench press', 'Overhead press']);
      expect(analytics.latestExercise(data), 'Bench press');
      expect(analytics.weeklyVolume([], now: now).single.volumeLoad, 0);
    },
  );

  test('ISO week-year boundaries and exact unit values', () {
    expect(isoWeek(DateTime(2021, 1, 1)), (year: 2020, week: 53));
    expect(isoWeek(DateTime(2018, 12, 31)), (year: 2019, week: 1));
    expect(formatIsoWeek(DateTime(2021, 1, 4)), 'W1');
    expect(formatExactVolume(12450, 'kg'), '12,450 kg');
    expect(formatExactVolume(400.25, 'kg'), '400.25 kg');
    expect(formatExactVolume(100, 'lbs'), '220.46 lbs');
    expect(formatExactVolume(0, 'kg'), '0 kg');
    expect(
      formatChartExerciseValue(80.25, ExerciseMetric.bestWeight, 'kg'),
      '80.25 kg',
    );
  });

  test(
    'exercise history starts at its first performed week, including zero load',
    () {
      final first = session('unrelated', DateTime(2025, 1, 1), name: 'Squat');
      final zero = WorkoutSession(
        id: 'bodyweight',
        date: now,
        planName: 'Upper',
        exercises: [
          Exercise(name: 'Pull up', sets: [gym.Set(weight: 0, reps: 10)]),
        ],
      );
      final result = analytics.weeklyVolume(
        [first, zero],
        exerciseName: 'pull up',
        now: now,
      );
      expect(result.length, 1);
      expect(result.single.volumeLoad, 0);
      expect(analytics.latestExercise([first, zero]), 'Pull up');
      expect(
        analytics
            .weeklyVolume(
              [session('a', now), session('b', now)],
              exerciseName: 'bench press',
              now: now,
            )
            .single
            .volumeLoad,
        800,
      );
    },
  );

  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) => MaterialApp(
    theme: buildTheme(const Color(0xFF00A2FF), brightness),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  List<WeeklyTrainingValue> weeks(int count) => [
    for (var i = 0; i < count; i++)
      WeeklyTrainingValue(
        weekStart: DateTime(2026, 1, 5 + i * 7),
        volumeLoad: (i + 1) * 120,
      ),
  ];

  testWidgets(
    'weekly axis keeps suffixes on one line and anchors the volume unit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final unit in ['kg', 'lbs']) {
          await tester.pumpWidget(
            host(
              WeeklyVolumeChart(weeks: weeks(160), weightUnit: unit),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Volume ($unit)'), findsOneWidget);
          expect(find.text(unit), findsNothing);
          for (var i = 0; i <= 4; i++) {
            final tick = find.byKey(ValueKey('weekly-volume-scroll-axis-$i'));
            final text = tester.widget<Text>(tick);
            final paragraph = tester.renderObject<RenderParagraph>(tick);
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.data!.length),
            );
            expect(boxes, hasLength(1));
            expect(
              boxes.single.right,
              lessThanOrEqualTo(paragraph.size.width + 0.1),
            );
            expect(boxes.single.left, greaterThanOrEqualTo(-0.1));
          }
          final title = tester.getTopLeft(find.text('Volume ($unit)'));
          final plot = tester.getTopLeft(
            find.byKey(const ValueKey('weekly-volume-scroll')),
          );
          expect(title.dx, closeTo(plot.dx, 0.1));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'fixed bars open at newest end, scroll, select, and retain browsing position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = weeks(160);
      await tester.pumpWidget(
        host(WeeklyVolumeChart(weeks: data, weightUnit: 'kg')),
      );
      await tester.pumpAndSettle();
      final plot = find.byKey(const ValueKey('weekly-volume-scroll'));
      final controller = tester.widget<SingleChildScrollView>(plot).controller!;
      expect(controller.offset, 0);
      // Leads with the last complete week, not the one in progress.
      expect(find.text('Last week'), findsOneWidget);
      expect(find.text('19,080 kg'), findsOneWidget);
      expect(find.text('1% more than the week before'), findsOneWidget);
      expect(find.text('This week · In progress'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('volume-bar-0'))).width,
        24,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('volume-bar-159'))).width,
        24,
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('volume-bar-159'))).dx,
        inInclusiveRange(0, 390),
      );
      await tester.drag(plot, const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      final offset = controller.offset;
      await tester.pumpWidget(
        host(WeeklyVolumeChart(weeks: data, weightUnit: 'kg')),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, offset);
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      // The week in progress can still be read, without a partial comparison.
      await tester.tap(
        find.byKey(ValueKey('week-${data.last.weekStart.toIso8601String()}')),
      );
      await tester.pump();
      expect(find.text('This week · In progress'), findsOneWidget);
      expect(find.text('19,200 kg'), findsOneWidget);
      expect(find.textContaining('the week before'), findsNothing);
      await tester.tap(
        find.byKey(
          ValueKey('week-${data[data.length - 3].weekStart.toIso8601String()}'),
        ),
      );
      await tester.pump();
      expect(find.text('18,960 kg'), findsOneWidget);
      expect(find.text('Last week'), findsNothing);
      await tester.pumpWidget(
        host(
          WeeklyVolumeChart(
            key: const ValueKey('another'),
            weeks: weeks(2),
            weightUnit: 'kg',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('volume-bar-0'))).width,
        24,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'exercise selection reads exact values; flat, single, and empty series render',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = [
        session('one', now),
        session('two', now.add(const Duration(days: 1))),
      ];
      final progress = analytics.exerciseProgress(
        data,
        'Bench press',
        ExerciseMetric.bestWeight,
      );
      await tester.pumpWidget(
        host(
          ExerciseTrendChart(
            progress: progress,
            metric: ExerciseMetric.bestWeight,
            weightUnit: 'kg',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest workout'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('progress-point-0')));
      await tester.pump();
      expect(find.text('Selected workout'), findsOneWidget);
      expect(find.text('80 kg'), findsOneWidget);
      for (final data in [
        [session('single', now)],
        <WorkoutSession>[],
      ]) {
        await tester.pumpWidget(
          host(
            ExerciseTrendChart(
              progress: analytics.exerciseProgress(
                data,
                'Bench press',
                ExerciseMetric.bestWeight,
              ),
              metric: ExerciseMetric.bestWeight,
              weightUnit: 'kg',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('same-day workouts label their date on the x-axis once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final day = DateTime(2026, 10, 7);
    final data = [
      session('earlier', DateTime(2026, 10, 3)),
      session('a', day),
      session('b', day.add(const Duration(hours: 2))),
      session('c', day.add(const Duration(hours: 4))),
    ];
    await tester.pumpWidget(
      host(
        ExerciseTrendChart(
          progress: analytics.exerciseProgress(
            data,
            'Bench press',
            ExerciseMetric.bestWeight,
          ),
          metric: ExerciseMetric.bestWeight,
          weightUnit: 'kg',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7 Oct'), findsOneWidget);
    expect(find.text('3 Oct'), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      expect(
        tester.getSemantics(find.byKey(ValueKey('progress-point-$i'))).label,
        contains(formatStatisticsDate(day)),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar value labels sit on a surface-coloured mask', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = weeks(3);
    await tester.pumpWidget(
      host(WeeklyVolumeChart(weeks: data, weightUnit: 'kg')),
    );
    await tester.pumpAndSettle();
    final surface = surfaceColor(
      tester.element(find.byType(WeeklyVolumeChart)),
    );
    for (final week in data) {
      final label = find.text(formatChartNumber(week.volumeLoad));
      expect(label, findsOneWidget);
      final masks = tester.widgetList<DecoratedBox>(
        find.ancestor(of: label, matching: find.byType(DecoratedBox)),
      );
      expect(
        masks.any(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color == surface,
        ),
        isTrue,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen order and independent exercise selectors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _Sessions([session('one', DateTime.now())]);
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkoutSessionProvider>.value(
        value: data,
        child: host(const StatsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent sessions'), findsNothing);
    final headings = ['Weekly training', 'Exercise progress', 'Recent records'];
    expect(
      tester.getTopLeft(find.text(headings[0])).dy,
      lessThan(tester.getTopLeft(find.text(headings[1])).dy),
    );
    expect(
      tester.getTopLeft(find.text(headings[1])).dy,
      lessThan(tester.getTopLeft(find.text(headings[2])).dy),
    );
    final selectors = find.byType(DropdownButtonFormField<String>);
    await tester.tap(selectors.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All exercises').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(selectors.first)
          .initialValue,
      '',
    );
    expect(selectors, findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('progress-exercise'))).data,
      'Bench press',
    );
    expect(find.text('800 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the progress summary leaves the latest value to the readout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final today = DateTime.now();
    final data = _Sessions([
      session('one', today.subtract(const Duration(days: 2))),
      session('two', today),
    ]);
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkoutSessionProvider>.value(
        value: data,
        child: host(const StatsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Best in period'), findsOneWidget);
    expect(find.text('Latest'), findsNothing);
    expect(find.text('Latest workout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('record rows', () {
    RecordAchievement achievement(RecordType type, {int? reps}) =>
        RecordAchievement(
          type: type,
          value: 100,
          setWeight: 85,
          setReps: 8,
          reps: reps,
        );
    RecordEvent event(List<RecordAchievement> achievements) => RecordEvent(
      exerciseName: 'Bench press',
      session: session('record', now),
      achievements: achievements,
    );

    testWidgets('lead with heaviest weight and expand in place', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          RecordEventRow(
            event: event([
              achievement(RecordType.setVolume),
              achievement(RecordType.estimatedOneRepMax),
              achievement(RecordType.heaviestWeight),
            ]),
            weightUnit: 'kg',
          ),
        ),
      );
      expect(find.text('Heaviest weight'), findsOneWidget);
      expect(find.text('Estimated 1RM'), findsNothing);
      expect(find.text('Best set volume'), findsNothing);
      await tester.tap(find.text('+2 more'));
      await tester.pump();
      final heaviest = tester.getTopLeft(find.text('Heaviest weight')).dy;
      final oneRepMax = tester.getTopLeft(find.text('Estimated 1RM')).dy;
      final volume = tester.getTopLeft(find.text('Best set volume')).dy;
      expect(heaviest, lessThan(oneRepMax));
      expect(oneRepMax, lessThan(volume));
      expect(find.text('+2 more'), findsNothing);
      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(find.text('Estimated 1RM'), findsNothing);
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('fall back by priority and skip the button for one tag', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          RecordEventRow(
            event: event([
              achievement(RecordType.setVolume),
              achievement(RecordType.repBest, reps: 8),
            ]),
            weightUnit: 'kg',
          ),
        ),
      );
      expect(find.text('8-rep best'), findsOneWidget);
      expect(find.text('+1 more'), findsOneWidget);
      await tester.pumpWidget(
        host(
          RecordEventRow(
            key: const ValueKey('single'),
            event: event([achievement(RecordType.setVolume)]),
            weightUnit: 'kg',
          ),
        ),
      );
      expect(find.text('Best set volume'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
