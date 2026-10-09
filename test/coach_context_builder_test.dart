import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/data/exercise_library.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/coach/coach_context_builder.dart';

import 'support/coach_fixtures.dart';

final DateTime now = DateTime(2026, 10, 9, 18);
DateTime daysAgo(int days) => DateTime(now.year, now.month, now.day - days, 9);

final Split activeSplit = Split(
  id: kSplitId,
  name: 'Push Pull Legs',
  createdAt: DateTime(2026, 1, 1),
);
final Split otherSplit = Split(
  id: 'split-2',
  name: 'Strength',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  const builder = CoachContextBuilder();

  CoachContext build({
    List<WorkoutSession> sessions = const [],
    List<Split>? splits,
  }) => builder.build(
    split: activeSplit,
    splits: splits ?? [activeSplit, otherSplit],
    plans: [
      plan('push', 'Push', [
        template('Bench Press', [
          (8, 60),
          (8, 60),
          (6, 65),
        ], note: '  Pause the first rep '),
        template('Landmine Press', [(10, 20)]),
      ], position: 0),
      plan('legs', 'Legs', [
        ExerciseTemplate(name: 'Squat', sets: 3),
      ], position: 1),
      plan('elsewhere', 'Other', [
        template('Deadlift', [(5, 140)]),
      ], splitId: 'split-2'),
      plan('gone', 'Deleted', [
        template('Bench Press', [(5, 80)]),
      ], deletedAt: DateTime(2026, 9, 2)),
    ],
    sessions: sessions,
    now: now,
  );

  group('plans', () {
    test('only live plans of the active split get refs, in order', () {
      final context = build();
      final plans = context.json['plans'] as List;
      expect(plans.map((plan) => plan['ref']), ['p1', 'p2']);
      expect(plans.map((plan) => plan['name']), ['Push', 'Legs']);
      expect(context.snapshot.planForRef('p2')!.id, 'legs');
      expect(context.snapshot.planForRef('P1')!.id, 'push');
      expect(context.snapshot.planForRef('p3'), isNull);
      expect(context.snapshot.planVersions.keys, ['push', 'legs']);
    });

    test('sets are reps and kg pairs; missing targets show as 8 at 0', () {
      final plans = build().json['plans'] as List;
      final bench = plans[0]['exercises'][0];
      expect(bench['sets'], [
        {'reps': 8, 'kg': 60},
        {'reps': 8, 'kg': 60},
        {'reps': 6, 'kg': 65},
      ]);
      expect(bench['note'], 'Pause the first rep');
      expect(plans[0]['exercises'][1].containsKey('note'), isFalse);
      expect(plans[1]['exercises'][0]['sets'], [
        {'reps': 8, 'kg': 0},
        {'reps': 8, 'kg': 0},
        {'reps': 8, 'kg': 0},
      ]);
    });

    test('custom exercises are names outside the library', () {
      final context = build(
        sessions: [
          session(daysAgo(3), {
            'Cable Woodchop': [(12, 15)],
            'bench press': [(5, 80)],
          }),
        ],
      );
      expect(context.snapshot.customExercises, [
        'Cable Woodchop',
        'Landmine Press',
      ]);
      expect(context.json['customExercises'], [
        'Cable Woodchop',
        'Landmine Press',
      ]);
    });
  });

  test('the header carries the split, unit, date, and library names', () {
    final json = build().json;
    expect(json['today'], '2026-10-09');
    expect(json['weightUnit'], 'kg');
    expect(json['split'], {
      'name': 'Push Pull Legs',
      'splitCount': 2,
      'maxSplits': 5,
    });
    expect(json['library'], ExerciseLibrary.allExercises);
    expect(json['library'], everyElement(isA<String>()));
  });

  test('deleted splits do not count toward the split total', () {
    final deleted = otherSplit.copyWith(deletedAt: DateTime(2026, 9, 1));
    final context = build(splits: [activeSplit, deleted]);
    expect(context.snapshot.splitNames, ['Push Pull Legs']);
  });

  test('training counts completed sessions of this split only', () {
    final json =
        build(
          sessions: [
            session(daysAgo(1), {
              'Squat': [(5, 100)],
            }),
            session(daysAgo(10), {
              'Squat': [(5, 100)],
            }),
            session(daysAgo(60), {
              'Squat': [(5, 90)],
            }),
            session(daysAgo(2), {
              'Squat': [(5, 200)],
            }, isCompleted: false),
            session(daysAgo(3), {
              'Squat': [(5, 200)],
            }, deletedAt: DateTime(2026, 10, 8)),
            session(daysAgo(4), {
              'Squat': [(5, 200)],
            }, splitId: 'split-2'),
          ],
        ).json;
    expect(json['training'], {
      'sessionsLast4Weeks': 2,
      'sessionsPerWeek': 0.5,
      'firstWorkout': '2026-08-10',
      'lastWorkout': '2026-10-08',
    });
    final squat = (json['exercises'] as List).single;
    expect(squat['lastTopSet'], {'reps': 5, 'kg': 100});
  });

  test('session and set notes are never sent', () {
    final encoded = jsonEncode(
      build(
        sessions: [
          session(daysAgo(1), {
            'Squat': [(5, 100)],
          }, note: 'left knee felt odd'),
        ],
      ).json,
    );
    expect(encoded, isNot(contains('knee')));
  });

  group('exercise trends', () {
    ExerciseSummary summarize(List<WorkoutSession> sessions, String name) =>
        builder
            .summarizeExercises(sessions, now: now)
            .singleWhere((summary) => summary.name == name);

    List<WorkoutSession> squatHistory(double earlier, double recent) => [
      session(daysAgo(90), {
        'Squat': [(5, 80)],
      }),
      session(daysAgo(20), {
        'Squat': [(5, earlier)],
      }),
      session(daysAgo(16), {
        'Squat': [(5, earlier)],
      }),
      session(daysAgo(6), {
        'Squat': [(5, recent)],
      }),
      session(daysAgo(1), {
        'Squat': [(5, recent), (3, recent)],
      }),
    ];

    test('a gain above 2.5% is improving', () {
      final squat = summarize(squatHistory(100, 105), 'Squat');
      expect(squat.trend, ExerciseTrend.improving);
      expect(squat.metric, 'e1rm');
      expect(squat.bestEarlier, 116.7);
      expect(squat.bestRecent, 122.5);
      expect(squat.sessionsInWindow, 4);
      expect(squat.lastTopSet.reps, 5);
      expect(squat.lastTopSet.kg, 105);
    });

    test('a change within 2.5% is stalled', () {
      expect(
        summarize(squatHistory(100, 101), 'Squat').trend,
        ExerciseTrend.stalled,
      );
    });

    test('a drop beyond 2.5% is declining', () {
      expect(
        summarize(squatHistory(100, 95), 'Squat').trend,
        ExerciseTrend.declining,
      );
    });

    test('an exercise first trained inside the window is new', () {
      final squat = summarize(squatHistory(100, 105).sublist(1), 'Squat');
      expect(squat.trend, ExerciseTrend.newExercise);
    });

    test('fewer than three sessions in the window is not enough data', () {
      final history = squatHistory(100, 105);
      final squat = summarize([history[0], history[2], history[4]], 'Squat');
      expect(squat.trend, ExerciseTrend.notEnoughData);
    });

    test('one empty half is not enough data', () {
      final history = squatHistory(100, 105);
      final squat = summarize([
        history[0],
        history[1],
        history[2],
        session(daysAgo(18), {
          'Squat': [(5, 100)],
        }),
      ], 'Squat');
      expect(squat.trend, ExerciseTrend.notEnoughData);
      expect(squat.bestRecent, isNull);
    });

    test('nothing in the window is not recent', () {
      final squat = summarize([
        session(daysAgo(40), {
          'Squat': [(5, 100)],
        }),
      ], 'Squat');
      expect(squat.trend, ExerciseTrend.notRecent);
      expect(squat.metric, isNull);
      expect(squat.bestRecent, isNull);
      expect(squat.toJson()['lastDate'], '2026-08-30');
    });

    test('bodyweight work is measured in reps', () {
      final pullUps = summarize([
        session(daysAgo(60), {
          'Pull-ups': [(5, 0)],
        }),
        session(daysAgo(20), {
          'Pull-ups': [(8, 0)],
        }),
        session(daysAgo(15), {
          'Pull-ups': [(8, 0), (7, 0)],
        }),
        session(daysAgo(2), {
          'Pull-ups': [(10, 0)],
        }),
      ], 'Pull-ups');
      expect(pullUps.metric, 'reps');
      expect(pullUps.bestEarlier, 8);
      expect(pullUps.bestRecent, 10);
      expect(pullUps.trend, ExerciseTrend.improving);
      expect(pullUps.toJson()['bestRecent'], 10);
    });

    test('the top set is the heaviest, with more reps breaking a tie', () {
      final bench = summarize([
        session(daysAgo(1), {
          'Bench Press': [(10, 60), (5, 80), (6, 80), (12, 50)],
        }),
      ], 'Bench Press');
      expect(bench.lastTopSet.reps, 6);
      expect(bench.lastTopSet.kg, 80);
    });

    test('names merge ignoring case and keep the latest spelling', () {
      final summaries = builder.summarizeExercises([
        session(daysAgo(10), {
          'squat': [(5, 100)],
        }),
        session(daysAgo(1), {
          'Squat ': [(5, 100)],
        }),
      ], now: now);
      expect(summaries.single.name, 'Squat');
      expect(summaries.single.sessionsInWindow, 2);
    });

    test('unperformed sets are ignored', () {
      final summaries = builder.summarizeExercises([
        session(daysAgo(1), {
          'Squat': [(0, 0), (0, 0)],
          'Leg Press': [(10, 150)],
        }),
      ], now: now);
      expect(summaries.map((s) => s.name), ['Leg Press']);
    });

    test('the most recent 25 exercises are kept, newest first', () {
      final sessions = [
        for (var day = 0; day < 30; day++)
          session(daysAgo(day), {
            'Custom $day': [(10, 10)],
          }),
      ];
      final summaries = builder.summarizeExercises(sessions, now: now);
      expect(summaries, hasLength(CoachContextBuilder.maxExercises));
      expect(summaries.first.name, 'Custom 0');
      expect(summaries.last.name, 'Custom 24');
    });
  });
}
