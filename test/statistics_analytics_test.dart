import 'package:flutter_test/flutter_test.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/utils/statistics_format.dart';

void main() {
  const analytics = StatisticsAnalyticsService();

  WorkoutSession session({
    required String id,
    required DateTime date,
    String splitId = 'active',
    bool completed = true,
    DateTime? deletedAt,
    int? durationSeconds,
    String exerciseName = 'Bench Press',
    List<Set> sets = const [],
  }) => WorkoutSession(
    id: id,
    splitId: splitId,
    planName: 'Push Day',
    date: date,
    isCompleted: completed,
    deletedAt: deletedAt,
    durationSeconds: durationSeconds,
    exercises: [Exercise(name: exerciseName, sets: sets)],
  );

  group('session calculations', () {
    test('calculates volume, performed sets, reps, duration, and e1RM', () {
      final workout = session(
        id: 'one',
        date: DateTime(2026, 9, 1),
        durationSeconds: 3600,
        sets: [
          Set(weight: 100, reps: 5),
          Set(weight: 0, reps: 12),
          Set(weight: 200, reps: 0),
        ],
      );

      final result = analytics.sessionStatistics(workout);
      expect(result.volumeLoad, 500);
      expect(result.totalSets, 2);
      expect(result.totalReps, 17);
      expect(result.durationSeconds, 3600);
      expect(
        StatisticsAnalyticsService.estimatedOneRepMax(
          workout.exercises.first.sets.first,
        ),
        closeTo(116.67, 0.01),
      );
      expect(
        StatisticsAnalyticsService.estimatedOneRepMax(
          Set(weight: 100, reps: 13),
        ),
        0,
      );
      expect(
        StatisticsAnalyticsService.estimatedOneRepMax(Set(weight: 0, reps: 5)),
        0,
      );
    });

    test('keeps missing legacy duration distinct from zero', () {
      final result = analytics.sessionStatistics(
        session(id: 'legacy', date: DateTime(2026, 9, 1)),
      );
      expect(result.durationSeconds, isNull);
    });
  });

  group('record events', () {
    test('derives and groups genuine record types by exercise occurrence', () {
      final events = analytics.recordEvents([
        session(
          id: 'first',
          date: DateTime(2026, 8, 1),
          sets: [Set(weight: 80, reps: 8)],
        ),
        session(
          id: 'second',
          date: DateTime(2026, 8, 8),
          sets: [Set(weight: 85, reps: 8)],
        ),
      ]);

      final latest = events.first;
      expect(latest.session.id, 'second');
      expect(
        latest.achievements.map((item) => item.type),
        containsAll([
          RecordType.estimatedOneRepMax,
          RecordType.heaviestWeight,
          RecordType.repBest,
          RecordType.setVolume,
        ]),
      );
      expect(
        events.where((event) => event.session.id == 'second'),
        hasLength(1),
      );
    });

    test('historical edits and deletes change the derived record feed', () {
      final first = session(
        id: 'first',
        date: DateTime(2026, 8, 1),
        sets: [Set(weight: 80, reps: 5)],
      );
      final second = session(
        id: 'second',
        date: DateTime(2026, 8, 8),
        sets: [Set(weight: 90, reps: 5)],
      );
      expect(
        analytics.recordEvents([first, second]).first.session.id,
        'second',
      );

      final edited = session(
        id: 'second',
        date: DateTime(2026, 8, 8),
        sets: [Set(weight: 70, reps: 5)],
      );
      expect(analytics.recordEvents([first, edited]).first.session.id, 'first');

      final deleted = session(
        id: 'second',
        date: DateTime(2026, 8, 8),
        deletedAt: DateTime(2026, 8, 9),
        sets: [Set(weight: 90, reps: 5)],
      );
      expect(
        analytics.recordEvents([first, deleted]).first.session.id,
        'first',
      );
    });
  });

  group('exercise progress', () {
    test('returns one chronological point per matching workout', () {
      final progress = analytics.exerciseProgress(
        [
          session(
            id: 'new',
            date: DateTime(2026, 8, 8),
            sets: [Set(weight: 90, reps: 5), Set(weight: 0, reps: 0)],
          ),
          session(
            id: 'old',
            date: DateTime(2026, 8, 1),
            sets: [Set(weight: 80, reps: 5)],
          ),
        ],
        'Bench Press',
        ExerciseMetric.bestWeight,
      );

      expect(progress.points.map((point) => point.session.id), ['old', 'new']);
      expect(progress.currentValue, 90);
      expect(progress.change, 10);
      expect(progress.sessionCount, 2);
    });

    test('handles empty and single-point trends without invented change', () {
      final empty = analytics.exerciseProgress(
        const [],
        'Bench Press',
        ExerciseMetric.bestWeight,
      );
      expect(empty.points, isEmpty);
      expect(empty.change, isNull);

      final single = analytics.exerciseProgress(
        [
          session(
            id: 'only',
            date: DateTime(2026, 8, 1),
            sets: [Set(weight: 80, reps: 5)],
          ),
        ],
        'Bench Press',
        ExerciseMetric.bestWeight,
      );
      expect(single.currentValue, 80);
      expect(single.change, isNull);
    });

    test('omits e1RM points when no set is valid for estimation', () {
      final progress = analytics.exerciseProgress(
        [
          session(
            id: 'invalid',
            date: DateTime(2026, 8, 1),
            sets: [Set(weight: 100, reps: 15), Set(weight: 0, reps: 5)],
          ),
        ],
        'Bench Press',
        ExerciseMetric.estimatedOneRepMax,
      );
      expect(progress.points, isEmpty);
    });
  });

  group('statistics formatting', () {
    test('converts stored kilograms only at display time', () {
      expect(formatAnalyticsWeight(100, 'kg'), '100 kg');
      expect(formatAnalyticsWeight(100, 'lbs'), '220.5 lbs');
      expect(formatVolumeLoad(8420, 'kg'), '8.4 t');
      expect(formatVolumeLoad(500, 'kg'), '500 kg');
    });
  });
}
