import '../models/exercise.dart';
import '../models/statistics.dart';
import '../models/workout_session.dart';
import 'statistics_analytics_service.dart';

/// A heaviest-weight record in the shape the workout screen's record dialog
/// reads. A later task moves that dialog onto `RecordEvent` and removes this
/// class; until then it is derived from the shared record rules and never
/// computed on its own.
class PRResult {
  final String exerciseName;
  final double previousPR;
  final double newPR;
  final int reps;

  PRResult({
    required this.exerciseName,
    required this.previousPR,
    required this.newPR,
    required this.reps,
  });
}

class PRTrackingService {
  /// The heaviest-weight records among [events], one per exercise.
  static List<PRResult> heaviestWeightResults(Iterable<RecordEvent> events) => [
    for (final event in events)
      for (final achievement in event.achievements)
        if (achievement.type == RecordType.heaviestWeight)
          PRResult(
            exerciseName: event.exerciseName,
            previousPR: achievement.previousValue ?? 0,
            newPR: achievement.value,
            reps: achievement.setReps,
          ),
  ];

  /// Heaviest-weight records [exercises] would set if logged after every
  /// workout in [completedHistory], by the rules of
  /// `StatisticsAnalyticsService.recordEvents`. The caller is responsible for
  /// excluding the candidate's saved version.
  static List<PRResult> checkAgainstHistory(
    List<Exercise> exercises,
    Iterable<WorkoutSession> completedHistory,
  ) {
    const analytics = StatisticsAnalyticsService();
    final history = analytics.eligibleSessions(completedHistory);
    final latest = history.firstOrNull?.date ?? DateTime(2000);
    final candidate = WorkoutSession(
      date: latest.add(const Duration(microseconds: 1)),
      planName: '',
      exercises: exercises,
    );
    return heaviestWeightResults(
      analytics.sessionRecords([...history, candidate], candidate),
    );
  }
}
