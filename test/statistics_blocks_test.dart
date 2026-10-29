import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/training_block_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/theme/app_theme.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> data;
  _Sessions(this.data);
  @override
  void loadSessions() {}
  @override
  List<WorkoutSession> get sessions => data;
}

const _split = 'split';
final _created = DateTime(2026);

TrainingBlock _block(String id, String name, int position, int planned) =>
    TrainingBlock(
      id: id,
      splitId: _split,
      name: name,
      position: position,
      createdAt: _created,
      plannedWeekCount: planned,
    );

TrainingWeek _week(String blockId, int number) => TrainingWeek(
  id: '$blockId-$number',
  splitId: _split,
  blockId: blockId,
  number: number,
  createdAt: _created,
);

WorkoutSession _session(
  String weekId,
  DateTime date, {
  double bench = 80,
  int reps = 5,
  int sets = 3,
  bool completed = true,
}) => WorkoutSession(
  id: '$weekId-${date.toIso8601String()}',
  date: date,
  planName: 'Push',
  splitId: _split,
  trainingWeekId: weekId,
  isCompleted: completed,
  exercises: [
    Exercise(
      name: 'Bench press',
      sets: [for (var i = 0; i < sets; i++) gym.Set(weight: bench, reps: reps)],
    ),
    Exercise(name: 'Curl', sets: [gym.Set(weight: 10, reps: 15)]),
  ],
);

void main() {
  const analytics = StatisticsAnalyticsService();
  final blocks = [_block('a', 'Base', 0, 3), _block('b', 'Build', 1, 4)];
  final weeksByBlock = {
    'a': [_week('a', 1), _week('a', 2), _week('a', 3)],
    'b': [_week('b', 1)],
  };
  final today = DateTime.now();
  DateTime daysAgo(int days) =>
      DateTime(today.year, today.month, today.day - days, 12);
  final sessions = [
    _session('a-1', daysAgo(30), bench: 80),
    _session('a-1', daysAgo(28), bench: 82.5),
    _session('a-2', daysAgo(21), bench: 85),
    _session('a-3', daysAgo(14), bench: 87.5, sets: 2),
    _session('b-1', daysAgo(2), bench: 90, sets: 4),
    _session('b-1', daysAgo(1), bench: 95, completed: false),
  ];

  group('block statistics', () {
    test('sums each block through its weeks and keeps planned weeks', () {
      final stats = analytics.blockStatistics(
        sessions,
        blocks: blocks,
        weeksByBlock: weeksByBlock,
      );
      expect(stats.map((s) => s.block.name), ['Base', 'Build']);
      final base = stats.first;
      expect(base.workouts, 4);
      // Curls count as sets and volume but never as an estimated 1RM.
      expect(base.sets, 3 + 3 + 3 + 2 + 4);
      expect(base.weeks.map((w) => (w.number, w.workouts)), [
        (1, 2),
        (2, 1),
        (3, 1),
      ]);
      expect(base.trainedWeeks, 3);
      expect(base.latestWeekId, 'a-3');
      expect(base.perWeek(BlockMeasure.workouts), closeTo(4 / 3, 1e-9));

      final build = stats.last;
      // The draft is not a completed workout.
      expect(build.workouts, 1);
      expect(build.weeks.map((w) => (w.number, w.reached)), [
        (1, true),
        (2, false),
        (3, false),
        (4, false),
      ]);
      expect(build.plannedWeeks, 4);
      expect(build.latestWeek?.number, 1);
    });

    test(
      'gains run first to latest workout and records stay in their block',
      () {
        final stats = analytics.blockStatistics(
          sessions,
          blocks: blocks,
          weeksByBlock: weeksByBlock,
        );
        final gain = stats.first.gains.single;
        expect(gain.exerciseName, 'Bench press');
        expect(gain.start, closeTo(80 * (1 + 5 / 30), 1e-9));
        expect(gain.end, closeTo(87.5 * (1 + 5 / 30), 1e-9));
        expect(gain.percent, closeTo(9.375, 1e-9));
        // A single Build workout has nothing to compare.
        expect(stats.last.gains, isEmpty);
        final records = analytics.recordEvents(sessions).length;
        expect(stats.first.records + stats.last.records, records);
        expect(stats.last.records, greaterThan(0));
      },
    );

    test('sessions whose week is gone belong to no block', () {
      final stats = analytics.blockStatistics(
        [...sessions, _session('deleted-week', daysAgo(3))],
        blocks: blocks,
        weeksByBlock: weeksByBlock,
      );
      expect(stats.fold<int>(0, (sum, s) => sum + s.workouts), 5);
    });
  });

  test('lift summaries list the most recently trained lift first', () {
    final lifts = analytics.liftSummaries([
      WorkoutSession(
        date: daysAgo(3),
        planName: 'Legs',
        exercises: [
          Exercise(name: 'Squat', sets: [gym.Set(weight: 100, reps: 5)]),
        ],
      ),
      ...sessions,
    ], ExerciseMetric.bestWeight);
    expect(lifts.map((l) => l.exerciseName), ['Bench press', 'Curl', 'Squat']);
    expect(lifts.first.progress.change, 10);
  });

  group('statistics screen', () {
    late HiveTestHarness storage;
    late TrainingBlockProvider training;

    setUp(() async {
      await loadTestFonts();
    });

    Future<void> pumpStats(WidgetTester tester, {int weeklyRequest = 0}) =>
        tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<WorkoutSessionProvider>.value(
                value: _Sessions(sessions),
              ),
              ChangeNotifierProvider<TrainingBlockProvider?>.value(
                value: training,
              ),
            ],
            child: MaterialApp(
              theme: buildTheme(const Color(0xFF41B9B9), Brightness.light),
              home: StatsScreen(weeklyTrainingRequest: weeklyRequest),
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      storage = HiveTestHarness();
      await tester.runAsync(() async {
        await storage.open(includeSplits: true);
        for (final block in blocks) {
          await HiveService.putTrainingBlockRaw(block.copyWith());
        }
        for (final week in weeksByBlock.values.expand((w) => w)) {
          await HiveService.putTrainingWeekRaw(week.copyWith());
        }
      });
      training = TrainingBlockProvider(
        splitIdProvider: () => _split,
        ownerId: () => null,
      );
      addTearDown(() async {
        training.dispose();
        await tester.runAsync(storage.close);
      });
      await pumpStats(tester);
      await pumpWithStorage(tester);
    }

    String overviewName(WidgetTester tester) =>
        tester
            .widget<Text>(find.byKey(const ValueKey('block-overview-name')))
            .data!;

    testWidgets('leads with the current block and switches between blocks', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Training blocks'), findsOneWidget);
      expect(overviewName(tester), 'Build');
      expect(find.text('Build · Now'), findsOneWidget);
      expect(find.textContaining('Week 1 of 4'), findsOneWidget);
      expect(
        find.text('Arrows compare an average week with Base.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('block-chip-a')));
      await tester.pump();
      expect(overviewName(tester), 'Base');
      expect(find.text('Bench press'), findsWidgets);
      expect(find.textContaining('+9%'), findsOneWidget);
      // The first block has nothing earlier to compare with.
      expect(find.textContaining('Arrows compare'), findsNothing);

      await tester.ensureVisible(find.text('Compare blocks'));
      await tester.tap(
        find.byKey(ValueKey('block-measure-${BlockMeasure.workouts}')),
      );
      await tester.pump();
      expect(find.text('1.3 workouts'), findsOneWidget);
      expect(find.text('1 workouts'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('block-compare-b')));
      await tester.pump();
      expect(overviewName(tester), 'Build');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lift row opens that lift in the progress chart', (
      tester,
    ) async {
      await open(tester);
      final title = find.byKey(const ValueKey('progress-exercise'));
      final curl = find.byKey(const ValueKey('lift-Curl'));
      expect(tester.widget<Text>(title).data, 'Bench press');
      expect(
        find.text(ExerciseMetric.estimatedOneRepMax.description),
        findsOneWidget,
      );
      // Fifteen-rep sets have no estimated 1RM, so curls only join the list
      // under a measure that counts them.
      expect(curl, findsNothing);
      final topWeight = find.byKey(
        ValueKey('progress-metric-${ExerciseMetric.bestWeight}'),
      );
      await tester.ensureVisible(topWeight);
      await tester.tap(topWeight);
      await tester.pumpAndSettle();
      expect(find.text(ExerciseMetric.bestWeight.description), findsOneWidget);
      await tester.ensureVisible(curl);
      await tester.tap(curl);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(title).data, 'Curl');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the weekly link lands on weekly training below the blocks', (
      tester,
    ) async {
      await open(tester);
      await pumpStats(tester, weeklyRequest: 1);
      await tester.pump();
      final scroll =
          tester
              .widget<SingleChildScrollView>(
                find.byKey(const ValueKey('statistics-scroll')),
              )
              .controller!;
      expect(scroll.offset, greaterThan(0));
      final heading = tester.getTopLeft(find.text('Weekly training')).dy;
      final viewport =
          tester.getTopLeft(find.byKey(const ValueKey('statistics-scroll'))).dy;
      expect(heading - viewport, lessThan(24));
    });
  });
}
