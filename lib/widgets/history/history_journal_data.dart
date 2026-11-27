import '../../services/exercise_catalog.dart';
import '../../models/exercise.dart';
import '../../models/statistics.dart';
import '../../models/workout_session.dart';
import '../../services/statistics_analytics_service.dart';

class HistoryJournalData {
  final List<WorkoutSession> eligibleSessions;
  final List<HistoryMonthGroup> groups;

  const HistoryJournalData({
    required this.eligibleSessions,
    required this.groups,
  });

  bool get isEmpty => groups.isEmpty;
}

class HistoryMonthGroup {
  final int year;
  final int month;
  final List<HistoryWorkoutSummary> workouts;

  const HistoryMonthGroup({
    required this.year,
    required this.month,
    required this.workouts,
  });
}

class HistoryWorkoutSummary {
  final WorkoutSession session;
  final SessionStatistics statistics;

  /// How many exercises set a personal record in this workout.
  final int recordCount;

  /// The exercises a search found this workout by, when its name didn't
  /// match. Empty outside a search.
  final List<String> matchedExercises;

  const HistoryWorkoutSummary({
    required this.session,
    required this.statistics,
    this.recordCount = 0,
    this.matchedExercises = const [],
  });

  bool get hasPersonalRecord => recordCount > 0;
}

HistoryJournalData buildHistoryJournalData(
  Iterable<WorkoutSession> sessions, {
  String query = '',
  String? splitId,
  StatisticsAnalyticsService analytics = const StatisticsAnalyticsService(),
}) {
  final eligible = analytics.eligibleSessions(sessions, splitId: splitId);
  final records = analytics.recordEvents(eligible);
  final normalizedQuery = query.trim().toLowerCase();
  final matchingIds = ExerciseCatalog.search(query).map((d) => d.id).toSet();
  bool exerciseMatches(Exercise exercise) =>
      exercise.name.toLowerCase().contains(normalizedQuery) ||
      matchingIds.contains(
        ExerciseCatalog.identity(exercise.name, exercise.exerciseId),
      );
  bool nameMatches(WorkoutSession session) =>
      session.planName.toLowerCase().contains(normalizedQuery);
  final filtered = eligible.where((session) {
    if (normalizedQuery.isEmpty) return true;
    if (nameMatches(session)) return true;
    return session.exercises.any(exerciseMatches);
  });

  final groups = <HistoryMonthGroup>[];
  int? currentYear;
  int? currentMonth;
  var currentWorkouts = <HistoryWorkoutSummary>[];
  for (final session in filtered) {
    if (session.date.year != currentYear ||
        session.date.month != currentMonth) {
      if (currentYear != null && currentMonth != null) {
        groups.add(
          HistoryMonthGroup(
            year: currentYear,
            month: currentMonth,
            workouts: List.unmodifiable(currentWorkouts),
          ),
        );
      }
      currentYear = session.date.year;
      currentMonth = session.date.month;
      currentWorkouts = [];
    }
    currentWorkouts.add(
      HistoryWorkoutSummary(
        session: session,
        statistics: analytics.sessionStatistics(session),
        recordCount:
            records
                .where((event) => _sameSession(event.session, session))
                .length,
        matchedExercises:
            normalizedQuery.isEmpty || nameMatches(session)
                ? const []
                : List.unmodifiable([
                  for (final exercise in session.exercises)
                    if (exerciseMatches(exercise))
                      ExerciseCatalog.label(exercise.name, exercise.exerciseId),
                ]),
      ),
    );
  }
  if (currentYear != null && currentMonth != null) {
    groups.add(
      HistoryMonthGroup(
        year: currentYear,
        month: currentMonth,
        workouts: List.unmodifiable(currentWorkouts),
      ),
    );
  }
  return HistoryJournalData(
    eligibleSessions: eligible,
    groups: List.unmodifiable(groups),
  );
}

bool _sameSession(WorkoutSession first, WorkoutSession second) {
  final firstId = first.id;
  final secondId = second.id;
  return firstId != null && secondId != null
      ? firstId == secondId
      : identical(first, second);
}

String historySessionIdentity(WorkoutSession session) =>
    session.id ??
    'legacy:${session.date.microsecondsSinceEpoch}:${session.weekNumber}:${session.planName}';

String historyMonthLabel(int month, int year) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[month - 1]} $year';
}

String historyWeekday(DateTime date) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return weekdays[date.weekday - 1];
}
