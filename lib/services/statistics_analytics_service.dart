import '../models/set.dart' as gym;
import '../models/statistics.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_session.dart';

class StatisticsAnalyticsService {
  const StatisticsAnalyticsService();

  /// Exercise volume across calendar weeks, including gaps through this week.
  List<WeeklyTrainingValue> weeklyVolume(
    Iterable<WorkoutSession> sessions, {
    String? exerciseName,
    String? splitId,
    DateTime? now,
  }) {
    final current = startOfWeek(now ?? DateTime.now());
    final end = DateTime(current.year, current.month, current.day + 7);
    final totals = <DateTime, double>{};
    for (final session in eligibleSessions(sessions, splitId: splitId)) {
      if (!session.date.isBefore(end)) continue;
      final sets = session.exercises
          .where(
            (exercise) =>
                exerciseName == null ||
                exercise.name.trim().toLowerCase() ==
                    exerciseName.trim().toLowerCase(),
          )
          .expand((exercise) => exercise.sets)
          .where((set) => set.reps > 0);
      if (sets.isEmpty) continue;
      final week = startOfWeek(session.date);
      totals.update(
        week,
        (value) =>
            value +
            sets.fold<double>(0, (sum, set) => sum + set.weight * set.reps),
        ifAbsent:
            () =>
                sets.fold<double>(0, (sum, set) => sum + set.weight * set.reps),
      );
    }
    final first = totals.keys.fold(current, (a, b) => a.isBefore(b) ? a : b);
    return List.unmodifiable([
      for (
        var week = first;
        !week.isAfter(current);
        week = DateTime(week.year, week.month, week.day + 7)
      )
        WeeklyTrainingValue(weekStart: week, volumeLoad: totals[week] ?? 0),
    ]);
  }

  String? latestExercise(Iterable<WorkoutSession> sessions) {
    final latest = <String, DateTime>{};
    for (final session in eligibleSessions(sessions)) {
      for (final exercise in session.exercises) {
        if (exercise.sets.any((set) => set.reps > 0)) {
          latest.putIfAbsent(
            exercise.name.trim().toLowerCase(),
            () => session.date,
          );
        }
      }
    }
    final names =
        exerciseNames(
            sessions,
          ).where((name) => latest.containsKey(name.toLowerCase())).toList()
          ..sort((a, b) {
            final date = latest[b.toLowerCase()]!.compareTo(
              latest[a.toLowerCase()]!,
            );
            return date == 0
                ? a.toLowerCase().compareTo(b.toLowerCase())
                : date;
          });
    return names.firstOrNull;
  }

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

  /// Every personal record in [sessions], newest workout first. This is the
  /// app's one definition of a record: Stats, History, Workout details and
  /// the result of logging a workout all read it.
  ///
  /// - Only completed, live workouts count, oldest first, and only sets with
  ///   reps above zero.
  /// - Lifts are matched by trimmed, case-insensitive name.
  /// - The first workout with performed sets of a lift sets its baselines and
  ///   yields no records, not even between its own sets.
  /// - After that, each workout is compared with the workouts before it, never
  ///   with its own sets, so one workout breaks each record at most once:
  ///   - heaviest weight, best set volume (weight × reps) and estimated 1RM
  ///     go to the workout's best set when it beats the previous best. An
  ///     estimated 1RM needs an earlier one to beat (a lift trained only above
  ///     12 reps has none yet);
  ///   - a set of N reps at weight W is a rep best when W beats the heaviest
  ///     weight previously lifted for N or more reps, and no other set in the
  ///     workout matched it with at least as many reps and as much weight.
  ///     With no earlier set of N or more reps there is nothing to beat.
  List<RecordEvent> recordEvents(Iterable<WorkoutSession> sessions) {
    final ordered = eligibleSessions(sessions).toList()..sort(_chronological);
    final states = <String, _RecordState>{};
    final events = <RecordEvent>[];
    for (final session in ordered) {
      final lifts = <String, _PerformedLift>{};
      for (final (exerciseIndex, exercise) in session.exercises.indexed) {
        for (final (setIndex, set) in exercise.sets.indexed) {
          if (set.reps <= 0) continue;
          lifts
              .putIfAbsent(
                exercise.name.trim().toLowerCase(),
                () => _PerformedLift(exercise.name),
              )
              .sets
              .add(_PerformedSet(exerciseIndex, setIndex, set));
        }
      }
      for (final MapEntry(:key, value: lift) in lifts.entries) {
        final state = states[key];
        if (state == null) {
          states[key] = _RecordState()..absorb(lift.sets);
          continue;
        }
        final achievements = state.achievements(lift.sets);
        state.absorb(lift.sets);
        if (achievements.isEmpty) continue;
        events.add(
          RecordEvent(
            exerciseName: lift.name,
            session: session,
            achievements: List.unmodifiable(achievements),
          ),
        );
      }
    }
    events.sort((a, b) => _chronological(b.session, a.session));
    return List.unmodifiable(events);
  }

  /// The records [session] set, judged against the other workouts in
  /// [sessions] exactly as [recordEvents] judges them. [session] matches by
  /// id, or by identity when either id is missing.
  List<RecordEvent> sessionRecords(
    Iterable<WorkoutSession> sessions,
    WorkoutSession session,
  ) => List.unmodifiable(
    recordEvents(
      sessions,
    ).where((event) => _sameSession(event.session, session)),
  );

  static bool _sameSession(WorkoutSession a, WorkoutSession b) =>
      a.id != null && b.id != null ? a.id == b.id : identical(a, b);

  /// Oldest first, with a stable order for workouts logged at the same time.
  static int _chronological(WorkoutSession a, WorkoutSession b) {
    final date = a.date.compareTo(b.date);
    return date != 0 ? date : (a.id ?? '').compareTo(b.id ?? '');
  }

  List<String> exerciseNames(Iterable<WorkoutSession> sessions) {
    final names = <String, String>{};
    for (final session in eligibleSessions(sessions)) {
      for (final exercise in session.exercises) {
        if (exercise.sets.any((set) => set.reps > 0)) {
          names.putIfAbsent(
            exercise.name.trim().toLowerCase(),
            () => exercise.name.trim(),
          );
        }
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
        (exercise) =>
            exercise.name.trim().toLowerCase() ==
            exerciseName.trim().toLowerCase(),
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

  /// One summary per block, in block order. Sessions find their block through
  /// their training week; ones whose week is gone stay out of every block.
  List<BlockStatistics> blockStatistics(
    Iterable<WorkoutSession> sessions, {
    required List<TrainingBlock> blocks,
    required Map<String, List<TrainingWeek>> weeksByBlock,
  }) {
    final eligible = eligibleSessions(sessions);
    final recordsBySession = Map<WorkoutSession, int>.identity();
    for (final event in recordEvents(eligible)) {
      recordsBySession.update(
        event.session,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final byWeek = <String, List<WorkoutSession>>{};
    for (final session in eligible.reversed) {
      final weekId = session.trainingWeekId;
      if (weekId != null) byWeek.putIfAbsent(weekId, () => []).add(session);
    }
    return List.unmodifiable([
      for (final block in blocks)
        _blockStatistics(
          block,
          weeksByBlock[block.id] ?? const [],
          byWeek,
          recordsBySession,
        ),
    ]);
  }

  BlockStatistics _blockStatistics(
    TrainingBlock block,
    List<TrainingWeek> weeks,
    Map<String, List<WorkoutSession>> byWeek,
    Map<WorkoutSession, int> recordsBySession,
  ) {
    final weekStats = <BlockWeekStatistics>[];
    final ordered = <WorkoutSession>[];
    for (final week in weeks) {
      final sessions = byWeek[week.id] ?? const <WorkoutSession>[];
      ordered.addAll(sessions);
      var sets = 0;
      var volume = 0.0;
      for (final session in sessions) {
        final stats = sessionStatistics(session);
        sets += stats.totalSets;
        volume += stats.volumeLoad;
      }
      weekStats.add(
        BlockWeekStatistics(
          weekId: week.id,
          number: week.number,
          workouts: sessions.length,
          sets: sets,
          volumeLoad: volume,
        ),
      );
    }
    final last = weeks.isEmpty ? 0 : weeks.last.number;
    for (var n = last + 1; n <= (block.plannedWeekCount ?? 0); n++) {
      weekStats.add(BlockWeekStatistics(weekId: null, number: n));
    }
    ordered.sort((a, b) => a.date.compareTo(b.date));
    return BlockStatistics(
      block: block,
      weeks: List.unmodifiable(weekStats),
      workouts: ordered.length,
      sets: weekStats.fold(0, (sum, week) => sum + week.sets),
      volumeLoad: weekStats.fold(0, (sum, week) => sum + week.volumeLoad),
      records: ordered.fold(
        0,
        (sum, session) => sum + (recordsBySession[session] ?? 0),
      ),
      firstDate: ordered.firstOrNull?.date,
      lastDate: ordered.lastOrNull?.date,
      latestWeekId: ordered.lastOrNull?.trainingWeekId,
      gains: _gains(ordered),
    );
  }

  /// Lifts whose best estimated 1RM rose from their first to their latest
  /// workout in [ordered] (oldest first), biggest relative gain first.
  List<LiftGain> _gains(List<WorkoutSession> ordered) {
    final firsts = <String, (String, double)>{};
    final lasts = <String, double>{};
    for (final session in ordered) {
      for (final exercise in session.exercises) {
        var best = 0.0;
        for (final set in exercise.sets) {
          final e1rm = estimatedOneRepMax(set);
          if (e1rm > best) best = e1rm;
        }
        if (best == 0) continue;
        final key = exercise.name.trim().toLowerCase();
        firsts.putIfAbsent(key, () => (exercise.name.trim(), best));
        lasts[key] = best;
      }
    }
    final gains = [
      for (final MapEntry(:key, value: (name, start)) in firsts.entries)
        if (lasts[key]! > start)
          LiftGain(exerciseName: name, start: start, end: lasts[key]!),
    ]..sort((a, b) => b.percent.compareTo(a.percent));
    return List.unmodifiable(gains);
  }

  /// Every lift trained in [sessions], most recently trained first.
  List<LiftSummary> liftSummaries(
    Iterable<WorkoutSession> sessions,
    ExerciseMetric metric,
  ) {
    final summaries =
        [
            for (final name in exerciseNames(sessions))
              LiftSummary(
                exerciseName: name,
                progress: exerciseProgress(sessions, name, metric),
              ),
          ].where((lift) => lift.progress.points.isNotEmpty).toList()
          ..sort((a, b) {
            final date = b.progress.points.last.session.date.compareTo(
              a.progress.points.last.session.date,
            );
            return date != 0
                ? date
                : a.exerciseName.toLowerCase().compareTo(
                  b.exerciseName.toLowerCase(),
                );
          });
    return List.unmodifiable(summaries);
  }

  static DateTime startOfWeek(DateTime date) {
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }
}

/// One lift's performed sets in one workout, gathered across every exercise
/// entry that shares its name.
class _PerformedLift {
  final String name;
  final List<_PerformedSet> sets = [];

  _PerformedLift(this.name);
}

class _PerformedSet {
  final int exerciseIndex;
  final int setIndex;
  final gym.Set set;

  const _PerformedSet(this.exerciseIndex, this.setIndex, this.set);

  double get weight => set.weight;
  int get reps => set.reps;
  double get volume => set.weight * set.reps;
  double get estimatedOneRepMax =>
      StatisticsAnalyticsService.estimatedOneRepMax(set);

  RecordAchievement achievement(
    RecordType type,
    double value,
    double previous, {
    int? reps,
  }) => RecordAchievement(
    type: type,
    value: value,
    setWeight: weight,
    setReps: this.reps,
    reps: reps,
    previousValue: previous,
    exerciseIndex: exerciseIndex,
    setIndex: setIndex,
  );
}

/// One lift's bests from the workouts judged so far.
class _RecordState {
  double heaviestWeight = 0;
  double bestSetVolume = 0;

  /// Null until a set of 1–12 reps with weight gives an estimate.
  double? estimatedOneRepMax;

  /// The heaviest weight lifted for exactly each rep count.
  final Map<int, double> repBests = {};

  /// The heaviest weight lifted for [reps] or more reps, if any.
  double? bestForAtLeast(int reps) {
    double? best;
    for (final MapEntry(key: count, value: weight) in repBests.entries) {
      if (count >= reps && (best == null || weight > best)) best = weight;
    }
    return best;
  }

  /// What [sets] beat, against the bests before them. Does not update them.
  List<RecordAchievement> achievements(List<_PerformedSet> sets) {
    // The first set wins a tie, so a repeated best set is reported once.
    _PerformedSet top(double Function(_PerformedSet set) measure) =>
        sets.reduce((a, b) => measure(b) > measure(a) ? b : a);
    final result = <RecordAchievement>[];

    final heaviest = top((set) => set.weight);
    if (heaviest.weight > heaviestWeight) {
      result.add(
        heaviest.achievement(
          RecordType.heaviestWeight,
          heaviest.weight,
          heaviestWeight,
        ),
      );
    }

    final strongest = top((set) => set.estimatedOneRepMax);
    final previousE1rm = estimatedOneRepMax;
    if (previousE1rm != null && strongest.estimatedOneRepMax > previousE1rm) {
      result.add(
        strongest.achievement(
          RecordType.estimatedOneRepMax,
          strongest.estimatedOneRepMax,
          previousE1rm,
        ),
      );
    }

    final repBestSets = <_PerformedSet>[];
    for (final (index, set) in sets.indexed) {
      final matched = sets.indexed.any(
        (other) =>
            other.$1 != index &&
            other.$2.reps >= set.reps &&
            other.$2.weight >= set.weight &&
            (other.$2.reps > set.reps ||
                other.$2.weight > set.weight ||
                other.$1 < index),
      );
      if (matched) continue;
      final previous = bestForAtLeast(set.reps);
      if (previous != null && set.weight > previous) repBestSets.add(set);
    }
    repBestSets.sort((a, b) => a.reps.compareTo(b.reps));
    for (final set in repBestSets) {
      result.add(
        set.achievement(
          RecordType.repBest,
          set.weight,
          bestForAtLeast(set.reps)!,
          reps: set.reps,
        ),
      );
    }

    final biggest = top((set) => set.volume);
    if (biggest.volume > bestSetVolume) {
      result.add(
        biggest.achievement(
          RecordType.setVolume,
          biggest.volume,
          bestSetVolume,
        ),
      );
    }
    return result;
  }

  void absorb(List<_PerformedSet> sets) {
    for (final set in sets) {
      if (set.weight > heaviestWeight) heaviestWeight = set.weight;
      if (set.volume > bestSetVolume) bestSetVolume = set.volume;
      final e1rm = set.estimatedOneRepMax;
      if (e1rm > 0 && e1rm > (estimatedOneRepMax ?? 0)) {
        estimatedOneRepMax = e1rm;
      }
      if (set.weight > (repBests[set.reps] ?? double.negativeInfinity)) {
        repBests[set.reps] = set.weight;
      }
    }
  }
}
