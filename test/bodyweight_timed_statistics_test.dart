import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/statistics_format.dart';
import 'package:gymapp/widgets/history/workout_details_widgets.dart';
import 'package:gymapp/widgets/statistics/lift_list.dart';
import 'package:gymapp/widgets/statistics/statistics_widgets.dart';
import 'package:gymapp/widgets/statistics/training_charts.dart';

void main() {
  const analytics = StatisticsAnalyticsService();

  WorkoutSession workout(
    String id,
    int day,
    List<Exercise> exercises, {
    String? weekId,
  }) => WorkoutSession(
    id: id,
    date: DateTime(2026, 9, day),
    planName: 'Upper',
    isCompleted: true,
    trainingWeekId: weekId,
    exercises: exercises,
  );

  WorkoutSession lift(String id, int day, String name, List<Set> sets) =>
      workout(id, day, [Exercise(name: name, sets: sets)]);

  final block = TrainingBlock(
    id: 'b1',
    splitId: 's',
    name: 'Block 1',
    position: 0,
    createdAt: DateTime(2026),
  );
  final week = TrainingWeek(
    id: 'w1',
    splitId: 's',
    blockId: 'b1',
    number: 1,
    createdAt: DateTime(2026),
  );

  List<RecordAchievement> achievements(List<WorkoutSession> sessions) =>
      analytics.recordEvents(sessions).expand((e) => e.achievements).toList();

  group('bodyweight lifts', () {
    test('stay listed and charted in Exercise progress, as reps', () {
      final sessions = [
        lift('a', 1, 'Pull-ups', [Set(weight: 0, reps: 8)]),
        lift('b', 3, 'Pull-ups', [
          Set(weight: 0, reps: 10),
          Set(weight: 0, reps: 7),
        ]),
        lift('c', 5, 'Bench Press', [Set(weight: 80, reps: 5)]),
      ];
      for (final metric in [
        ExerciseMetric.estimatedOneRepMax,
        ExerciseMetric.bestWeight,
        ExerciseMetric.bestSetVolume,
        ExerciseMetric.sessionVolume,
      ]) {
        final lifts = analytics.liftSummaries(sessions, metric);
        expect(lifts.map((lift) => lift.exerciseName), [
          'Bench Press',
          'Pull-ups',
        ], reason: '$metric');
        final pullUps = lifts.last.progress;
        expect(pullUps.fallback, ProgressFallback.bestReps);
        expect(pullUps.points.map((point) => point.value), [8, 10]);
        expect(pullUps.change, 2);
        expect(lifts.first.progress.fallback, ProgressFallback.none);
      }
      // Reps and sets already describe a bodyweight lift.
      final reps = analytics.exerciseProgress(
        sessions,
        'pull-ups',
        ExerciseMetric.totalReps,
      );
      expect(reps.fallback, ProgressFallback.none);
      expect(reps.points.map((point) => point.value), [8, 17]);
    });

    test('a lift with any loaded set in range keeps its measure', () {
      final sessions = [
        lift('a', 1, 'Dips', [Set(weight: 0, reps: 12)]),
        lift('b', 3, 'Dips', [Set(weight: 10, reps: 8)]),
      ];
      final progress = analytics.exerciseProgress(
        sessions,
        'Dips',
        ExerciseMetric.bestWeight,
      );
      expect(progress.fallback, ProgressFallback.none);
      expect(progress.points.map((point) => point.value), [0, 10]);
    });

    test('most reps needs an earlier bodyweight set to beat', () {
      final first = lift('a', 1, 'Push-ups', [
        Set(weight: 0, reps: 10),
        Set(weight: 0, reps: 15),
      ]);
      final better = lift('b', 3, 'Push-ups', [
        Set(weight: 0, reps: 12),
        Set(weight: 0, reps: 18),
        Set(weight: 0, reps: 18),
      ]);
      final worse = lift('c', 5, 'Push-ups', [Set(weight: 0, reps: 17)]);
      expect(achievements([first]), isEmpty);
      final records = achievements([first, better, worse]);
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.type, RecordType.mostReps);
      expect(record.value, 18);
      expect(record.previousValue, 15);
      expect(record.setWeight, 0);
      expect(record.setIndex, 1);
      expect(
        analytics.recordEvents([first, better, worse]).single.session,
        better,
      );
    });

    test('the first loaded set after bodyweight workouts sets baselines', () {
      final sessions = [
        lift('a', 1, 'Pull-ups', [Set(weight: 0, reps: 12)]),
        lift('b', 3, 'Pull-ups', [Set(weight: 10, reps: 8)]),
      ];
      // Added load after performed bodyweight sets is a heaviest weight over
      // a baseline of 0, as the live mark has always shown. Set volume, rep
      // bests and 1RM have nothing of their own kind to beat yet.
      final first = achievements(sessions);
      expect(first.map((record) => record.type), [RecordType.heaviestWeight]);
      expect(first.single.previousValue, 0);
      expect(first.single.value, 10);
      final next = [
        ...sessions,
        lift('c', 5, 'Pull-ups', [Set(weight: 12.5, reps: 8)]),
      ];
      // Newest first: the third workout breaks every weighted record, then
      // the second workout's heaviest weight over the bodyweight baseline.
      expect(achievements(next).map((record) => record.type), [
        RecordType.heaviestWeight,
        RecordType.estimatedOneRepMax,
        RecordType.repBest,
        RecordType.setVolume,
        RecordType.heaviestWeight,
      ]);
      expect(achievements(next).first.previousValue, 10);
    });

    test('bodyweight sets add no volume load', () {
      final stats = analytics.sessionStatistics(
        lift('a', 1, 'Pull-ups', [Set(weight: 0, reps: 10)]),
      );
      expect(stats.volumeLoad, 0);
      expect(stats.totalReps, 10);
      expect(stats.totalSets, 1);
    });
  });

  group('timed lifts', () {
    test('count as sets but not as reps, volume or a 1RM', () {
      final session = workout('a', 1, [
        Exercise(
          name: 'Plank',
          sets: [Set(weight: 0, reps: 60), Set(weight: 10, reps: 45)],
        ),
        Exercise(name: 'Bench Press', sets: [Set(weight: 80, reps: 5)]),
      ]);
      final stats = analytics.sessionStatistics(session);
      expect(stats.totalSets, 3);
      expect(stats.totalReps, 5);
      expect(stats.volumeLoad, 400);
      expect(
        analytics
            .weeklyVolume(
              [session],
              exerciseName: 'plank',
              now: DateTime(2026, 9, 1),
            )
            .single
            .volumeLoad,
        0,
      );
    });

    test('earn only a longest hold, after a baseline', () {
      final sessions = [
        lift('a', 1, 'Side Plank', [Set(weight: 0, reps: 45)]),
        lift('b', 3, 'Side Plank', [
          Set(weight: 10, reps: 30),
          Set(weight: 0, reps: 70),
        ]),
        lift('c', 5, 'side plank ', [Set(weight: 20, reps: 60)]),
      ];
      final records = achievements(sessions);
      expect(records, hasLength(1));
      expect(records.single.type, RecordType.longestHold);
      expect(records.single.value, 70);
      expect(records.single.previousValue, 45);
      expect(records.single.setIndex, 1);
      expect(achievements(sessions.take(1).toList()), isEmpty);
    });

    test('show their best time in Exercise progress', () {
      final sessions = [
        lift('a', 1, 'Plank', [Set(weight: 0, reps: 60)]),
        lift('b', 3, 'Plank', [
          Set(weight: 0, reps: 90),
          Set(weight: 0, reps: 75),
        ]),
      ];
      for (final metric in ExerciseMetric.values) {
        final progress = analytics.exerciseProgress(sessions, 'Plank', metric);
        if (metric == ExerciseMetric.totalSets) {
          expect(progress.fallback, ProgressFallback.none);
          expect(progress.points.map((point) => point.value), [1, 2]);
        } else {
          expect(
            progress.fallback,
            ProgressFallback.bestTime,
            reason: '$metric',
          );
          expect(progress.points.map((point) => point.value), [60, 90]);
        }
      }
    });

    test('stay out of block gains', () {
      Exercise plank(int seconds) =>
          Exercise(name: 'Plank', sets: [Set(weight: 10, reps: seconds)]);
      final stats =
          analytics
              .blockStatistics(
                [
                  workout('a', 1, [plank(5)], weekId: 'w1'),
                  workout('b', 3, [plank(8)], weekId: 'w1'),
                ],
                blocks: [block],
                weeksByBlock: {
                  'b1': [week],
                },
              )
              .single;
      expect(stats.gains, isEmpty);
      expect(stats.records, 1);
    });
  });

  test('block statistics count supplied record events', () {
    final sessions = [
      workout('a', 1, [
        Exercise(name: 'Squat', sets: [Set(weight: 100, reps: 5)]),
      ], weekId: 'w1'),
      workout('b', 3, [
        Exercise(name: 'Squat', sets: [Set(weight: 110, reps: 5)]),
      ], weekId: 'w1'),
    ];
    BlockStatistics run([List<RecordEvent>? records]) =>
        analytics
            .blockStatistics(
              sessions,
              blocks: [block],
              weeksByBlock: {
                'b1': [week],
              },
              records: records,
            )
            .single;
    expect(run().records, 1);
    expect(run(analytics.recordEvents(sessions)).records, 1);
    expect(run(const []).records, 0);
  });

  group('display helpers', () {
    test('format hold times one way everywhere', () {
      expect(formatHoldTime(0), '0 s');
      expect(formatHoldTime(45), '45 s');
      expect(formatHoldTime(89), '89 s');
      expect(formatHoldTime(90), '1:30');
      expect(formatHoldTime(125), '2:05');
      expect(formatHoldTime(-15), '-15 s');
      expect(formatHoldTimeSpoken(45), '45 seconds');
      expect(formatHoldTimeSpoken(1), '1 second');
      expect(formatHoldTimeSpoken(90), '1 minute 30 seconds');
      expect(formatHoldTimeSpoken(120), '2 minutes');
      expect(formatRepCount(1), '1 rep');
      expect(formatRepCount(12), '12 reps');
      expect(setCountLabel(timed: true), 'Time');
      expect(setCountLabel(timed: false), 'Reps');
      expect(formatSetCount(95, timed: true), '1:35');
      expect(formatSetCount(95, timed: false), '95');
    });

    test('print a set by what it measures', () {
      expect(formatSetSummary(80, 5, 'kg', timed: false), '80 kg × 5');
      expect(formatSetSummary(0, 12, 'kg', timed: false), '12 reps');
      expect(formatSetSummary(0, 45, 'kg', timed: true), '45 s');
      expect(formatSetSummary(10, 90, 'kg', timed: true), '10 kg · 1:30');
    });

    test('format every record type and the value it beat', () {
      RecordAchievement record(
        RecordType type,
        double value,
        double? previous, {
        int? reps,
      }) => RecordAchievement(
        type: type,
        value: value,
        previousValue: previous,
        setWeight: 0,
        setReps: 0,
        reps: reps,
      );
      final cases = {
        record(RecordType.heaviestWeight, 100, 95): ('100 kg', '95 kg'),
        record(RecordType.estimatedOneRepMax, 116.5, 110): (
          '116.5 kg',
          '110 kg',
        ),
        record(RecordType.repBest, 85, 80, reps: 5): ('85 kg', '80 kg'),
        record(RecordType.setVolume, 800, 750): ('800 kg', '750 kg'),
        record(RecordType.mostReps, 18, 15): ('18 reps', '15 reps'),
        record(RecordType.longestHold, 95, 60): ('1:35', '60 s'),
      };
      expect(
        cases.keys.map((record) => record.type).toSet(),
        RecordType.values.toSet(),
      );
      for (final MapEntry(key: record, value: (value, previous))
          in cases.entries) {
        expect(formatRecordValue(record, 'kg'), value);
        expect(formatRecordPreviousValue(record, 'kg'), previous);
      }
      expect(
        formatRecordValue(record(RecordType.heaviestWeight, 100, 95), 'lbs'),
        '220.5 lbs',
      );
      expect(
        formatRecordPreviousValue(
          record(RecordType.longestHold, 95, null),
          'kg',
        ),
        isNull,
      );
      expect(
        formatRecordTitle(record(RecordType.repBest, 1, 1, reps: 5)),
        '5-rep best',
      );
      expect(RecordType.mostReps.label(), 'New most reps');
      expect(RecordType.longestHold.label(), 'New longest hold');
    });

    test('label Exercise progress values by what they measure', () {
      expect(
        progressMeasureLabel(
          ExerciseMetric.estimatedOneRepMax,
          ProgressFallback.bestReps,
        ),
        'Best reps in one set',
      );
      expect(
        progressMeasureLabel(ExerciseMetric.bestWeight, ProgressFallback.none),
        'Best weight',
      );
      expect(
        formatProgressValue(
          12,
          ExerciseMetric.bestWeight,
          ProgressFallback.bestReps,
          'kg',
        ),
        '12 reps',
      );
      expect(
        formatProgressValue(
          90,
          ExerciseMetric.bestWeight,
          ProgressFallback.bestTime,
          'kg',
        ),
        '1:30',
      );
      expect(
        formatProgressValue(
          80,
          ExerciseMetric.bestWeight,
          ProgressFallback.none,
          'kg',
        ),
        '80 kg',
      );
    });
  });

  group('widgets', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

    Widget host(Widget child) => MaterialApp(
      theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('Workout details shows a timed exercise as time', (
      tester,
    ) async {
      final session = workout('a', 1, [
        Exercise(
          name: 'Plank',
          sets: [Set(weight: 0, reps: 45), Set(weight: 0, reps: 90)],
        ),
        Exercise(name: 'Bench Press', sets: [Set(weight: 80, reps: 5)]),
      ]);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              WorkoutDetailsSummary(
                statistics: analytics.sessionStatistics(session),
                weightUnit: 'kg',
              ),
              for (final exercise in session.exercises)
                WorkoutExerciseDetails(exercise: exercise, weightUnit: 'kg'),
            ],
          ),
        ),
      );
      await tester.pump();
      // Reps leave out the plank's seconds.
      expect(find.bySemanticsLabel('Reps: 5'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Reps'), findsWidgets);
      expect(find.text('45 s'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('2 sets · longest 1:30'), findsOneWidget);
      expect(find.text('1 set · 5 reps'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('1:30')).value,
        '1 minute 30 seconds',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('record rows print values in the record\'s unit', (
      tester,
    ) async {
      final session = workout('a', 1, []);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              RecordEventRow(
                event: RecordEvent(
                  exerciseName: 'Pull-ups',
                  session: session,
                  achievements: const [
                    RecordAchievement(
                      type: RecordType.mostReps,
                      value: 15,
                      previousValue: 12,
                      setWeight: 0,
                      setReps: 15,
                    ),
                  ],
                ),
                weightUnit: 'kg',
              ),
              RecordEventRow(
                event: RecordEvent(
                  exerciseName: 'Plank',
                  session: session,
                  achievements: const [
                    RecordAchievement(
                      type: RecordType.longestHold,
                      value: 95,
                      previousValue: 60,
                      setWeight: 0,
                      setReps: 95,
                    ),
                  ],
                ),
                weightUnit: 'kg',
              ),
            ],
          ),
        ),
      );
      expect(find.text('Most reps · 15 reps, up from 12 reps'), findsOneWidget);
      expect(find.textContaining('15 reps · Upper'), findsOneWidget);
      expect(find.text('Longest hold · 1:35, up from 60 s'), findsOneWidget);
      expect(find.textContaining('1:35 · Upper'), findsOneWidget);
      expect(find.textContaining('0 kg'), findsNothing);
    });

    testWidgets('Exercise progress labels a bodyweight lift as reps', (
      tester,
    ) async {
      final sessions = [
        lift('a', 1, 'Pull-ups', [Set(weight: 0, reps: 8)]),
        lift('b', 3, 'Pull-ups', [Set(weight: 0, reps: 11)]),
      ];
      final lifts = analytics.liftSummaries(
        sessions,
        ExerciseMetric.estimatedOneRepMax,
      );
      await tester.pumpWidget(
        host(
          Column(
            children: [
              LiftList(
                lifts: lifts,
                selected: 'Pull-ups',
                metric: ExerciseMetric.estimatedOneRepMax,
                weightUnit: 'kg',
                onSelect: (_) {},
              ),
              ExerciseTrendChart(
                progress: lifts.single.progress,
                metric: ExerciseMetric.estimatedOneRepMax,
                weightUnit: 'kg',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('11 reps'), findsWidgets);
      expect(find.text('+3 reps'), findsOneWidget);
      expect(find.text('reps'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('lift-builtin:pull-ups')))
            .label,
        contains('Best reps in one set 11 reps'),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
