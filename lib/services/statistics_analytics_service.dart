import '../data/exercise_library.dart';
import '../models/set.dart' as gym;
import '../models/statistics.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_session.dart';

class StatisticsAnalyticsService {
  const StatisticsAnalyticsService();

  /// Exercise volume across calendar weeks, including gaps through this week.
  /// Timed sets count toward a week being trained but add no volume.
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
      var performed = false;
      var volume = 0.0;
      for (final exercise in session.exercises) {
        if (exerciseName != null &&
            exercise.name.trim().toLowerCase() !=
                exerciseName.trim().toLowerCase()) {
          continue;
        }
        final timed = ExerciseLibrary.isTimed(exercise.name);
        for (final set in exercise.sets.where((set) => set.reps > 0)) {
          performed = true;
          if (!timed) volume += set.weight * set.reps;
        }
      }
      if (!performed) continue;
      totals.update(
        startOfWeek(session.date),
        (value) => value + volume,
        ifAbsent: () => volume,
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

  /// A performed set with no added load. Decided by the data, for library
  /// and custom exercises alike.
  static bool isBodyweightSet(gym.Set set) => set.weight <= 0 && set.reps > 0;

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
      // A timed set's reps are seconds: it counts as a set, not as reps.
      final timed = ExerciseLibrary.isTimed(exercise.name);
      for (final set in exercise.sets.where((set) => set.reps > 0)) {
        sets++;
        if (timed) continue;
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
  ///   with its own sets, so one workout breaks each record at most once.
  ///   Every record needs an earlier value of its own kind to beat:
  ///   - heaviest weight, best set volume (weight × reps) and estimated 1RM
  ///     go to the workout's best weighted set when it beats the previous
  ///     best. They need an earlier weighted set (weight above 0), so the
  ///     first loaded set after bodyweight-only workouts sets a baseline
  ///     instead of beating 0. An estimated 1RM likewise needs an earlier one
  ///     (a lift trained only above 12 reps has none yet);
  ///   - a weighted set of N reps at weight W is a rep best when W beats the
  ///     heaviest weight previously lifted for N or more reps, and no other
  ///     weighted set in the workout matched it with at least as many reps
  ///     and as much weight. With no earlier weighted set of N or more reps
  ///     there is nothing to beat;
  ///   - most reps goes to the workout's best bodyweight set (weight 0) when
  ///     it beats the most reps in an earlier bodyweight set.
  /// - A timed lift (`ExerciseLibrary.isTimed`) stores seconds in `reps`. It
  ///   only earns *longest hold*, against its earlier longest hold, and never
  ///   a weight, rep or estimated-1RM record.
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
                () => _PerformedLift(
                  exercise.name,
                  timed: ExerciseLibrary.isTimed(exercise.name),
                ),
              )
              .sets
              .add(_PerformedSet(exerciseIndex, setIndex, set));
        }
      }
      for (final MapEntry(:key, value: lift) in lifts.entries) {
        final state = states[key];
        if (state == null) {
          states[key] = _RecordState()..absorb(lift);
          continue;
        }
        final achievements = state.achievements(lift);
        state.absorb(lift);
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

  /// One lift's value per workout in [sessions], oldest first.
  ///
  /// A measure that can't describe the lift falls back, as
  /// [ExerciseProgress.fallback] says: a timed lift shows its longest hold
  /// under every measure but sets, and a lift whose sets in [sessions] are
  /// all at weight 0 shows its best reps in one set under the weight-based
  /// measures. Either way the lift stays listed and charted.
  ExerciseProgress exerciseProgress(
    Iterable<WorkoutSession> sessions,
    String exerciseName,
    ExerciseMetric metric,
  ) {
    final key = exerciseName.trim().toLowerCase();
    final performed = <(WorkoutSession, List<gym.Set>)>[];
    for (final session in eligibleSessions(sessions).reversed) {
      final sets =
          session.exercises
              .where((exercise) => exercise.name.trim().toLowerCase() == key)
              .expand((exercise) => exercise.sets)
              .where((set) => set.reps > 0)
              .toList();
      if (sets.isNotEmpty) performed.add((session, sets));
    }
    final fallback = progressFallback(
      metric,
      timed: ExerciseLibrary.isTimed(exerciseName),
      bodyweight: performed.every(
        (entry) => entry.$2.every((set) => set.weight <= 0),
      ),
    );
    // The set a point stands for: the biggest by weight × reps, or the most
    // reps (seconds for a hold) when the lift falls back.
    double size(gym.Set set) =>
        fallback == ProgressFallback.none
            ? set.weight * set.reps
            : set.reps.toDouble();
    final points = <ExerciseProgressPoint>[];
    double? overallBestWeight;
    int? overallBestReps;
    var overallBest = -1.0;
    for (final (session, sets) in performed) {
      final bestSet = sets.reduce((a, b) => size(a) >= size(b) ? a : b);
      final bestE1rm = sets
          .map(estimatedOneRepMax)
          .reduce((a, b) => a > b ? a : b);
      if (fallback == ProgressFallback.none &&
          metric == ExerciseMetric.estimatedOneRepMax &&
          bestE1rm == 0) {
        continue;
      }
      final value = switch (fallback) {
        ProgressFallback.bestReps ||
        ProgressFallback.bestTime => bestSet.reps.toDouble(),
        ProgressFallback.none => switch (metric) {
          ExerciseMetric.estimatedOneRepMax => bestE1rm,
          ExerciseMetric.bestWeight => sets
              .map((set) => set.weight)
              .reduce((a, b) => a > b ? a : b),
          ExerciseMetric.bestSetVolume => bestSet.weight * bestSet.reps,
          ExerciseMetric.sessionVolume => sets.fold<double>(
            0,
            (sum, set) => sum + set.weight * set.reps,
          ),
          ExerciseMetric.totalReps =>
            sets.fold<int>(0, (sum, set) => sum + set.reps).toDouble(),
          ExerciseMetric.totalSets => sets.length.toDouble(),
        },
      };
      points.add(
        ExerciseProgressPoint(
          session: session,
          value: value,
          bestSetWeight: bestSet.weight,
          bestSetReps: bestSet.reps,
        ),
      );
      if (size(bestSet) > overallBest) {
        overallBest = size(bestSet);
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
      fallback: points.isEmpty ? ProgressFallback.none : fallback,
    );
  }

  /// What a lift shows under [metric]: a [timed] lift its longest hold under
  /// every measure but sets, and a [bodyweight] lift (every set at weight 0)
  /// its best reps in one set under the weight-based measures.
  static ProgressFallback progressFallback(
    ExerciseMetric metric, {
    required bool timed,
    required bool bodyweight,
  }) {
    final weightBased = switch (metric) {
      ExerciseMetric.estimatedOneRepMax ||
      ExerciseMetric.bestWeight ||
      ExerciseMetric.bestSetVolume ||
      ExerciseMetric.sessionVolume => true,
      ExerciseMetric.totalReps || ExerciseMetric.totalSets => false,
    };
    if (metric == ExerciseMetric.totalSets) return ProgressFallback.none;
    if (timed) return ProgressFallback.bestTime;
    return bodyweight && weightBased
        ? ProgressFallback.bestReps
        : ProgressFallback.none;
  }

  /// One summary per block, in block order. Sessions find their block through
  /// their training week; ones whose week is gone stay out of every block.
  ///
  /// [records] are the [recordEvents] of [sessions] when the caller already
  /// has them, so they aren't worked out twice.
  List<BlockStatistics> blockStatistics(
    Iterable<WorkoutSession> sessions, {
    required List<TrainingBlock> blocks,
    required Map<String, List<TrainingWeek>> weeksByBlock,
    Iterable<RecordEvent>? records,
  }) {
    final eligible = eligibleSessions(sessions);
    final recordsBySession = Map<WorkoutSession, int>.identity();
    for (final event in records ?? recordEvents(eligible)) {
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
  /// workout in [ordered] (oldest first), biggest relative gain first. Timed
  /// lifts have no estimate.
  List<LiftGain> _gains(List<WorkoutSession> ordered) {
    final firsts = <String, (String, double)>{};
    final lasts = <String, double>{};
    for (final session in ordered) {
      for (final exercise in session.exercises) {
        if (ExerciseLibrary.isTimed(exercise.name)) continue;
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

  /// A hold: its sets' reps are seconds.
  final bool timed;
  final List<_PerformedSet> sets = [];

  _PerformedLift(this.name, {required this.timed});

  /// Sets with added load (weight above 0).
  List<_PerformedSet> get weighted =>
      sets.where((set) => set.weight > 0).toList();

  /// Sets at weight 0.
  List<_PerformedSet> get bodyweight =>
      sets.where((set) => set.weight <= 0).toList();
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

/// One lift's bests from the workouts judged so far. Each stays null until a
/// set of its own kind gives it a value, and a record needs a value to beat.
class _RecordState {
  /// From weighted sets only (weight above 0).
  double? heaviestWeight;
  double? bestSetVolume;

  /// Null until a set of 1–12 reps with weight gives an estimate.
  double? estimatedOneRepMax;

  /// The heaviest weight lifted for exactly each rep count, from weighted
  /// sets only.
  final Map<int, double> repBests = {};

  /// The most reps in one bodyweight set (weight 0).
  int? mostReps;

  /// The longest hold in seconds, for a timed lift.
  int? longestHold;

  /// The heaviest weight lifted for [reps] or more reps, if any.
  double? bestForAtLeast(int reps) {
    double? best;
    for (final MapEntry(key: count, value: weight) in repBests.entries) {
      if (count >= reps && (best == null || weight > best)) best = weight;
    }
    return best;
  }

  /// The first set wins a tie, so a repeated best set is reported once.
  static _PerformedSet _top(
    List<_PerformedSet> sets,
    num Function(_PerformedSet set) measure,
  ) => sets.reduce((a, b) => measure(b) > measure(a) ? b : a);

  /// What [lift] beat, against the bests before it. Does not update them.
  List<RecordAchievement> achievements(_PerformedLift lift) {
    if (lift.timed) {
      final held = _top(lift.sets, (set) => set.reps);
      final previous = longestHold;
      if (previous == null || held.reps <= previous) return const [];
      return [
        held.achievement(
          RecordType.longestHold,
          held.reps.toDouble(),
          previous.toDouble(),
        ),
      ];
    }
    final result = <RecordAchievement>[];
    final sets = lift.weighted;
    if (sets.isNotEmpty) {
      final heaviest = _top(sets, (set) => set.weight);
      final previousWeight = heaviestWeight;
      if (previousWeight != null && heaviest.weight > previousWeight) {
        result.add(
          heaviest.achievement(
            RecordType.heaviestWeight,
            heaviest.weight,
            previousWeight,
          ),
        );
      }

      final strongest = _top(sets, (set) => set.estimatedOneRepMax);
      final previousE1rm = estimatedOneRepMax;
      if (previousE1rm != null &&
          strongest.estimatedOneRepMax > previousE1rm) {
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

      final biggest = _top(sets, (set) => set.volume);
      final previousVolume = bestSetVolume;
      if (previousVolume != null && biggest.volume > previousVolume) {
        result.add(
          biggest.achievement(
            RecordType.setVolume,
            biggest.volume,
            previousVolume,
          ),
        );
      }
    }

    final bodyweight = lift.bodyweight;
    if (bodyweight.isNotEmpty) {
      final most = _top(bodyweight, (set) => set.reps);
      final previous = mostReps;
      if (previous != null && most.reps > previous) {
        result.add(
          most.achievement(
            RecordType.mostReps,
            most.reps.toDouble(),
            previous.toDouble(),
          ),
        );
      }
    }
    return result;
  }

  void absorb(_PerformedLift lift) {
    if (lift.timed) {
      for (final set in lift.sets) {
        if (set.reps > (longestHold ?? 0)) longestHold = set.reps;
      }
      return;
    }
    for (final set in lift.weighted) {
      if (set.weight > (heaviestWeight ?? 0)) heaviestWeight = set.weight;
      if (set.volume > (bestSetVolume ?? 0)) bestSetVolume = set.volume;
      final e1rm = set.estimatedOneRepMax;
      if (e1rm > 0 && e1rm > (estimatedOneRepMax ?? 0)) {
        estimatedOneRepMax = e1rm;
      }
      if (set.weight > (repBests[set.reps] ?? double.negativeInfinity)) {
        repBests[set.reps] = set.weight;
      }
    }
    for (final set in lift.bodyweight) {
      if (set.reps > (mostReps ?? 0)) mostReps = set.reps;
    }
  }
}
