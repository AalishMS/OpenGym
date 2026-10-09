import '../../data/exercise_library.dart';
import '../../models/coach_proposal.dart';
import '../../models/set.dart' as gym;
import '../../models/split.dart';
import '../../models/workout_plan.dart';
import '../../models/workout_session.dart';
import '../statistics_analytics_service.dart';

enum ExerciseTrend {
  improving,
  stalled,
  declining,
  newExercise,
  notEnoughData,
  notRecent,
}

extension ExerciseTrendWire on ExerciseTrend {
  String get wireName => switch (this) {
    ExerciseTrend.improving => 'improving',
    ExerciseTrend.stalled => 'stalled',
    ExerciseTrend.declining => 'declining',
    ExerciseTrend.newExercise => 'new',
    ExerciseTrend.notEnoughData => 'not_enough_data',
    ExerciseTrend.notRecent => 'not_recent',
  };
}

/// How one exercise is going, in the few numbers a small model can use.
class ExerciseSummary {
  final String name;
  final DateTime lastDate;

  /// Heaviest set of the latest session, most reps breaking a tie.
  final CoachSet lastTopSet;

  /// Sessions in the trend window that included this exercise.
  final int sessionsInWindow;

  /// `e1rm`, or `reps` for work with no estimated 1RM. Null when the exercise
  /// wasn't trained in the window.
  final String? metric;
  final double? bestRecent;
  final double? bestEarlier;
  final ExerciseTrend trend;

  const ExerciseSummary({
    required this.name,
    required this.lastDate,
    required this.lastTopSet,
    required this.sessionsInWindow,
    required this.metric,
    required this.bestRecent,
    required this.bestEarlier,
    required this.trend,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lastDate': coachDate(lastDate),
    'lastTopSet': lastTopSet.toJson(),
    'sessions4w': sessionsInWindow,
    'metric': metric,
    'bestRecent': bestRecent == null ? null : coachNumber(bestRecent!),
    'bestEarlier': bestEarlier == null ? null : coachNumber(bestEarlier!),
    'trend': trend.wireName,
  };
}

/// The request context and the snapshot it was built from.
class CoachContext {
  final Map<String, dynamic> json;
  final CoachSnapshot snapshot;

  const CoachContext({required this.json, required this.snapshot});
}

String coachDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// Builds what the Coach is told about the active split. See `docs/coach.md`.
///
/// Pure: callers pass in the split's plans and sessions, so this reads no
/// storage and is tested without Hive.
class CoachContextBuilder {
  static const int maxExercises = 25;
  static const int windowDays = 28;
  static const int minSessionsForTrend = 3;

  /// A change smaller than this either way is a stall.
  static const double trendThreshold = 0.025;

  final StatisticsAnalyticsService analytics;

  const CoachContextBuilder({
    this.analytics = const StatisticsAnalyticsService(),
  });

  /// [plans] must be in display order (`HiveService.getPlans` order); plans
  /// from other splits and tombstones are dropped here regardless.
  CoachContext build({
    required Split split,
    required List<Split> splits,
    required List<WorkoutPlan> plans,
    required Iterable<WorkoutSession> sessions,
    int maxSplits = 5,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final splitPlans = [
      for (final plan in plans)
        if (plan.deletedAt == null && plan.splitId == split.id) plan,
    ];
    final eligible = analytics.eligibleSessions(sessions, splitId: split.id);
    final snapshot = CoachSnapshot(
      splitId: split.id,
      splitName: split.name,
      plans: splitPlans,
      splitNames: [
        for (final other in splits)
          if (other.deletedAt == null) other.name,
      ],
      maxSplits: maxSplits,
      customExercises: customExercises(splitPlans, eligible),
    );

    final windowStart = _windowStart(today);
    final inWindow =
        eligible
            .where((session) => !_day(session.date).isBefore(windowStart))
            .length;

    return CoachContext(
      snapshot: snapshot,
      json: {
        'today': coachDate(today),
        'weightUnit': 'kg',
        'split': {
          'name': split.name,
          'splitCount': snapshot.splitNames.length,
          'maxSplits': maxSplits,
        },
        'plans': [
          for (var index = 0; index < splitPlans.length; index++)
            _planJson(CoachSnapshot.refAt(index), splitPlans[index]),
        ],
        'training': {
          'sessionsLast4Weeks': inWindow,
          'sessionsPerWeek': coachNumber(
            double.parse((inWindow / (windowDays / 7)).toStringAsFixed(1)),
          ),
          'firstWorkout':
              eligible.isEmpty ? null : coachDate(eligible.last.date),
          'lastWorkout':
              eligible.isEmpty ? null : coachDate(eligible.first.date),
        },
        'exercises': [
          for (final summary in summarizeExercises(eligible, now: today))
            summary.toJson(),
        ],
        'library': ExerciseLibrary.allExercises,
        'customExercises': snapshot.customExercises,
      },
    );
  }

  /// Per-exercise summaries over completed [sessions], most recently trained
  /// first, capped at [maxExercises].
  List<ExerciseSummary> summarizeExercises(
    Iterable<WorkoutSession> sessions, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final windowStart = _windowStart(today);
    final recentStart = _daysBefore(today, windowDays ~/ 2 - 1);

    // Newest first, so each history list is newest first too and the display
    // name is the one used most recently.
    final ordered = analytics.eligibleSessions(sessions);
    final histories = <String, List<_SessionBest>>{};
    final names = <String, String>{};
    for (final session in ordered) {
      final performed = <String, List<gym.Set>>{};
      for (final exercise in session.exercises) {
        final sets = exercise.sets.where((set) => set.reps > 0);
        if (sets.isEmpty) continue;
        final key = _key(exercise.name);
        names.putIfAbsent(key, () => exercise.name.trim());
        performed.putIfAbsent(key, () => []).addAll(sets);
      }
      for (final entry in performed.entries) {
        histories
            .putIfAbsent(entry.key, () => [])
            .add(_SessionBest.of(_day(session.date), entry.value));
      }
    }

    final summaries = [
      for (final entry in histories.entries)
        _summarize(names[entry.key]!, entry.value, windowStart, recentStart),
    ]..sort((a, b) {
      final byDate = b.lastDate.compareTo(a.lastDate);
      return byDate != 0
          ? byDate
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List.unmodifiable(summaries.take(maxExercises));
  }

  /// Names used in [plans] or [sessions] that aren't library exercises, in
  /// their most recent casing, sorted.
  static List<String> customExercises(
    Iterable<WorkoutPlan> plans,
    Iterable<WorkoutSession> sessions,
  ) {
    final library = {
      for (final name in ExerciseLibrary.allExercises) _key(name),
    };
    final custom = <String, String>{};
    void add(String name) {
      final key = _key(name);
      if (key.isEmpty || library.contains(key)) return;
      custom.putIfAbsent(key, () => name.trim().replaceAll(_spaces, ' '));
    }

    for (final plan in plans) {
      for (final exercise in plan.exercises) {
        add(exercise.name);
      }
    }
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        add(exercise.name);
      }
    }
    return custom.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  ExerciseSummary _summarize(
    String name,
    List<_SessionBest> history,
    DateTime windowStart,
    DateTime recentStart,
  ) {
    final inWindow =
        history.where((entry) => !entry.day.isBefore(windowStart)).toList();
    final recent = inWindow.where((entry) => !entry.day.isBefore(recentStart));
    final earlier = inWindow.where((entry) => entry.day.isBefore(recentStart));
    final useE1rm = inWindow.any((entry) => entry.e1rm > 0);

    double? best(Iterable<_SessionBest> entries) {
      final values =
          useE1rm
              ? entries.map((entry) => entry.e1rm).where((value) => value > 0)
              : entries.map((entry) => entry.reps.toDouble());
      if (values.isEmpty) return null;
      final top = values.reduce((a, b) => a > b ? a : b);
      return double.parse(top.toStringAsFixed(1));
    }

    final bestRecent = inWindow.isEmpty ? null : best(recent);
    final bestEarlier = inWindow.isEmpty ? null : best(earlier);
    final ExerciseTrend trend;
    if (inWindow.isEmpty) {
      trend = ExerciseTrend.notRecent;
    } else if (!history.last.day.isBefore(windowStart)) {
      trend = ExerciseTrend.newExercise;
    } else if (inWindow.length < minSessionsForTrend ||
        bestRecent == null ||
        bestEarlier == null ||
        bestEarlier <= 0) {
      trend = ExerciseTrend.notEnoughData;
    } else {
      final change = (bestRecent - bestEarlier) / bestEarlier;
      trend =
          change > trendThreshold
              ? ExerciseTrend.improving
              : change < -trendThreshold
              ? ExerciseTrend.declining
              : ExerciseTrend.stalled;
    }

    return ExerciseSummary(
      name: name,
      lastDate: history.first.day,
      lastTopSet: history.first.top,
      sessionsInWindow: inWindow.length,
      metric: inWindow.isEmpty ? null : (useE1rm ? 'e1rm' : 'reps'),
      bestRecent: bestRecent,
      bestEarlier: bestEarlier,
      trend: trend,
    );
  }

  Map<String, dynamic> _planJson(String ref, WorkoutPlan plan) => {
    'ref': ref,
    'name': plan.name,
    'exercises': [
      for (final exercise in plan.exercises)
        {
          'name': exercise.name,
          'sets': [for (final set in coachSetsOf(exercise)) set.toJson()],
          if (coachNote(exercise.note) != null)
            'note': coachNote(exercise.note),
        },
    ],
  };

  static DateTime _windowStart(DateTime now) =>
      _daysBefore(now, windowDays - 1);

  static DateTime _daysBefore(DateTime date, int days) {
    final day = _day(date);
    return DateTime(day.year, day.month, day.day - days);
  }

  static DateTime _day(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static final RegExp _spaces = RegExp(r'\s+');

  static String _key(String name) =>
      name.trim().replaceAll(_spaces, ' ').toLowerCase();
}

class _SessionBest {
  final DateTime day;
  final CoachSet top;
  final double e1rm;
  final int reps;

  const _SessionBest({
    required this.day,
    required this.top,
    required this.e1rm,
    required this.reps,
  });

  factory _SessionBest.of(DateTime day, List<gym.Set> sets) {
    var top = sets.first;
    var e1rm = 0.0;
    var reps = 0;
    for (final set in sets) {
      if (set.weight > top.weight ||
          (set.weight == top.weight && set.reps > top.reps)) {
        top = set;
      }
      final estimate = StatisticsAnalyticsService.estimatedOneRepMax(set);
      if (estimate > e1rm) e1rm = estimate;
      if (set.reps > reps) reps = set.reps;
    }
    return _SessionBest(
      day: day,
      top: CoachSet(reps: top.reps, kg: top.weight),
      e1rm: e1rm,
      reps: reps,
    );
  }
}
