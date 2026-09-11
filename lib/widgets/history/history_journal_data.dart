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
  final bool hasPersonalRecord;

  const HistoryWorkoutSummary({
    required this.session,
    required this.statistics,
    required this.hasPersonalRecord,
  });
}

HistoryJournalData buildHistoryJournalData(
  Iterable<WorkoutSession> sessions, {
  String query = '',
  String? splitId,
  StatisticsAnalyticsService analytics = const StatisticsAnalyticsService(),
}) {
  final eligible = analytics.eligibleSessions(sessions, splitId: splitId);
  final recordSessions = <WorkoutSession>{
    for (final event in analytics.recordEvents(eligible)) event.session,
  };
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = eligible.where((session) {
    if (normalizedQuery.isEmpty) return true;
    if (session.planName.toLowerCase().contains(normalizedQuery)) return true;
    return session.exercises.any(
      (exercise) => exercise.name.toLowerCase().contains(normalizedQuery),
    );
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
        hasPersonalRecord: recordSessions.any(
          (recordSession) => _sameSession(recordSession, session),
        ),
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
