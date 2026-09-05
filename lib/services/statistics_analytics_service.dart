import '../models/set.dart' as gym;
import '../models/statistics.dart';
import '../models/workout_session.dart';

class StatisticsAnalyticsService {
  const StatisticsAnalyticsService();

  static double estimatedOneRepMax(gym.Set set) {
    if (set.weight <= 0 || set.reps < 1 || set.reps > 12) return 0;
    return set.weight * (1 + set.reps / 30);
  }

  List<WorkoutSession> eligibleSessions(
    Iterable<WorkoutSession> sessions, {
    String? splitId,
  }) {
    final result =
        sessions
            .where(
              (session) =>
                  session.isCompleted &&
                  session.deletedAt == null &&
                  (splitId == null || session.splitId == splitId),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(result);
  }

  SessionStatistics sessionStatistics(WorkoutSession session) {
    var volume = 0.0;
    var reps = 0;
    var sets = 0;
    for (final exercise in session.exercises) {
      for (final set in exercise.sets.where((set) => set.reps > 0)) {
        sets++;
        reps += set.reps;
        volume += set.weight * set.reps;
      }
    }
    return SessionStatistics(
      session: session,
      volumeLoad: volume,
      totalReps: reps,
      totalSets: sets,
    );
  }

  List<WorkoutSession> sessionsInPeriod(
    Iterable<WorkoutSession> sessions,
    StatisticsPeriod period, {
    DateTime? now,
    String? splitId,
  }) {
    final eligible = eligibleSessions(sessions, splitId: splitId);
    final weeks = period.weekCount;
    if (weeks == null) return eligible;
    final currentWeek = startOfWeek(now ?? DateTime.now());
    final start = currentWeek.subtract(Duration(days: (weeks - 1) * 7));
    final end = currentWeek.add(const Duration(days: 7));
    return List.unmodifiable(
      eligible.where(
        (session) =>
            !session.date.isBefore(start) && session.date.isBefore(end),
      ),
    );
  }

  TrainingOverview trainingOverview(
    Iterable<WorkoutSession> sessions,
    StatisticsPeriod period,
    TrainingMetric metric, {
    DateTime? now,
    String? splitId,
  }) {
    final eligible = eligibleSessions(sessions, splitId: splitId);
    final currentWeek = startOfWeek(now ?? DateTime.now());
    final weekCount = period.weekCount;
    DateTime start;
    if (weekCount == null) {
      start =
          eligible.isEmpty
              ? currentWeek
              : startOfWeek(
                eligible
                    .map((s) => s.date)
                    .reduce((a, b) => a.isBefore(b) ? a : b),
              );
    } else {
      start = currentWeek.subtract(Duration(days: (weekCount - 1) * 7));
    }
    final end = currentWeek.add(const Duration(days: 7));
    final buckets = <DateTime, _MutableWeek>{};
    for (
      var cursor = start;
      cursor.isBefore(end);
      cursor = cursor.add(const Duration(days: 7))
    ) {
      buckets[cursor] = _MutableWeek();
    }
    for (final session in eligible) {
      if (session.date.isBefore(start) || !session.date.isBefore(end)) continue;
      final bucket = buckets[startOfWeek(session.date)];
      if (bucket == null) continue;
      final stats = sessionStatistics(session);
      bucket.volumeLoad += stats.volumeLoad;
      bucket.totalReps += stats.totalReps;
      bucket.totalSets += stats.totalSets;
      final duration = session.durationSeconds;
      if (duration != null) {
        bucket.durationSeconds += duration;
        bucket.sessionsWithDuration++;
      }
    }
    final values = [
      for (final entry in buckets.entries)
        WeeklyTrainingValue(
          weekStart: entry.key,
          volumeLoad: entry.value.volumeLoad,
          totalReps: entry.value.totalReps,
          totalSets: entry.value.totalSets,
          durationSeconds: entry.value.durationSeconds,
          sessionsWithDuration: entry.value.sessionsWithDuration,
        ),
    ];

    PeriodComparison? comparison;
    if (weekCount != null) {
      final current = values.fold<double>(
        0,
        (sum, week) => sum + week.valueFor(metric),
      );
      final previousStart = start.subtract(Duration(days: weekCount * 7));
      var previous = 0.0;
      for (final session in eligible) {
        if (session.date.isBefore(previousStart) ||
            !session.date.isBefore(start)) {
          continue;
        }
        previous += _metricForSession(sessionStatistics(session), metric);
      }
      comparison = PeriodComparison(
        currentValue: current,
        previousValue: previous,
        absoluteChange: current - previous,
        percentageChange:
            previous == 0 ? null : ((current - previous) / previous) * 100,
      );
    }

    return TrainingOverview(
      weeks: List.unmodifiable(values),
      comparison: comparison,
      hasDurationData: values.any((week) => week.sessionsWithDuration > 0),
    );
  }

  List<RecordEvent> recordEvents(Iterable<WorkoutSession> sessions) {
    final ordered = eligibleSessions(sessions).reversed.toList();
    final states = <String, _RecordState>{};
    final events = <RecordEvent>[];
    for (final session in ordered) {
      for (final exercise in session.exercises) {
        final key = exercise.name.trim().toLowerCase();
        final state = states.putIfAbsent(key, _RecordState.new);
        final achievements = <RecordAchievement>[];
        for (final set in exercise.sets.where((set) => set.reps > 0)) {
          final setVolume = set.weight * set.reps;
          final e1rm = estimatedOneRepMax(set);
          if (e1rm > state.estimatedOneRepMax) {
            achievements.add(
              RecordAchievement(
                type: RecordType.estimatedOneRepMax,
                value: e1rm,
                setWeight: set.weight,
                setReps: set.reps,
              ),
            );
            state.estimatedOneRepMax = e1rm;
          }
          if (set.weight > state.heaviestWeight) {
            achievements.add(
              RecordAchievement(
                type: RecordType.heaviestWeight,
                value: set.weight,
                setWeight: set.weight,
                setReps: set.reps,
              ),
            );
            state.heaviestWeight = set.weight;
          }
          final repBest = state.repBests[set.reps] ?? 0;
          if (set.weight > repBest) {
            achievements.add(
              RecordAchievement(
                type: RecordType.repBest,
                value: set.weight,
                setWeight: set.weight,
                setReps: set.reps,
                reps: set.reps,
              ),
            );
            state.repBests[set.reps] = set.weight;
          }
          if (setVolume > state.bestSetVolume) {
            achievements.add(
              RecordAchievement(
                type: RecordType.setVolume,
                value: setVolume,
                setWeight: set.weight,
                setReps: set.reps,
              ),
            );
            state.bestSetVolume = setVolume;
          }
        }
        if (achievements.isNotEmpty) {
          events.add(
            RecordEvent(
              exerciseName: exercise.name,
              session: session,
              achievements: List.unmodifiable(achievements),
            ),
          );
        }
      }
    }
    events.sort((a, b) => b.session.date.compareTo(a.session.date));
    return List.unmodifiable(events);
  }

  List<String> exerciseNames(Iterable<WorkoutSession> sessions) {
    final names = <String, String>{};
    for (final session in eligibleSessions(sessions)) {
      for (final exercise in session.exercises) {
        names.putIfAbsent(exercise.name.toLowerCase(), () => exercise.name);
      }
    }
    final result = names.values.toList()..sort();
    return List.unmodifiable(result);
  }

  ExerciseProgress exerciseProgress(
    Iterable<WorkoutSession> sessions,
    String exerciseName,
    ExerciseMetric metric,
  ) {
    final ordered = eligibleSessions(sessions).reversed;
    final points = <ExerciseProgressPoint>[];
    double? overallBestWeight;
    int? overallBestReps;
    var overallBestVolume = -1.0;
    for (final session in ordered) {
      final matching = session.exercises.where(
        (exercise) => exercise.name.toLowerCase() == exerciseName.toLowerCase(),
      );
      final sets =
          matching
              .expand((exercise) => exercise.sets)
              .where((set) => set.reps > 0)
              .toList();
      if (sets.isEmpty) continue;
      final bestSet = sets.reduce(
        (a, b) => a.weight * a.reps >= b.weight * b.reps ? a : b,
      );
      final bestWeight = sets
          .map((set) => set.weight)
          .reduce((a, b) => a > b ? a : b);
      final bestE1rm = sets
          .map(estimatedOneRepMax)
          .reduce((a, b) => a > b ? a : b);
      if (metric == ExerciseMetric.estimatedOneRepMax && bestE1rm == 0) {
        continue;
      }
      final value = switch (metric) {
        ExerciseMetric.estimatedOneRepMax => bestE1rm,
        ExerciseMetric.bestWeight => bestWeight,
        ExerciseMetric.bestSetVolume => bestSet.weight * bestSet.reps,
        ExerciseMetric.sessionVolume => sets.fold<double>(
          0,
          (sum, set) => sum + set.weight * set.reps,
        ),
        ExerciseMetric.totalReps =>
          sets.fold<int>(0, (sum, set) => sum + set.reps).toDouble(),
        ExerciseMetric.totalSets => sets.length.toDouble(),
      };
      points.add(
        ExerciseProgressPoint(
          session: session,
          value: value,
          bestSetWeight: bestSet.weight,
          bestSetReps: bestSet.reps,
        ),
      );
      final bestVolume = bestSet.weight * bestSet.reps;
      if (bestVolume > overallBestVolume) {
        overallBestVolume = bestVolume;
        overallBestWeight = bestSet.weight;
        overallBestReps = bestSet.reps;
      }
    }
    return ExerciseProgress(
      points: List.unmodifiable(points),
      currentValue: points.isEmpty ? null : points.last.value,
      change: points.length < 2 ? null : points.last.value - points.first.value,
      bestSetWeight: overallBestWeight,
      bestSetReps: overallBestReps,
      sessionCount: points.length,
    );
  }

  static DateTime startOfWeek(DateTime date) {
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static double _metricForSession(
    SessionStatistics stats,
    TrainingMetric metric,
  ) => switch (metric) {
    TrainingMetric.volumeLoad => stats.volumeLoad,
    TrainingMetric.sets => stats.totalSets.toDouble(),
    TrainingMetric.reps => stats.totalReps.toDouble(),
    TrainingMetric.duration => (stats.durationSeconds ?? 0).toDouble(),
  };
}

class _MutableWeek {
  double volumeLoad = 0;
  int totalReps = 0;
  int totalSets = 0;
  int durationSeconds = 0;
  int sessionsWithDuration = 0;
}

class _RecordState {
  double estimatedOneRepMax = 0;
  double heaviestWeight = 0;
  double bestSetVolume = 0;
  final Map<int, double> repBests = {};
}
