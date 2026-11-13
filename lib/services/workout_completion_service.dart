import '../models/statistics.dart';
import '../models/workout_session.dart';
import 'hive_service.dart';
import 'pr_tracking_service.dart';
import 'statistics_analytics_service.dart';

class WorkoutCompletionResult {
  final WorkoutSession session;

  /// The records the logged workout set, one event per exercise, judged by
  /// `StatisticsAnalyticsService.recordEvents` against the split's earlier
  /// workouts, so they match what Stats and History show for it.
  final List<RecordEvent> records;

  /// The heaviest-weight subset of [records], in the shape the workout
  /// screen's record dialog reads. A later task replaces the dialog and
  /// removes this field together with `PRResult`.
  final List<PRResult> personalRecords;
  final bool progressPending;

  const WorkoutCompletionResult({
    required this.session,
    required this.records,
    required this.personalRecords,
    this.progressPending = false,
  });
}

/// Finalizes a draft as one aggregate write. No draft is mutated before the
/// upsert succeeds, so callers can safely leave their current timer active and
/// retry after an error.
class WorkoutCompletionService {
  static Future<WorkoutCompletionResult> complete(
    WorkoutSession draft, {
    DateTime? now,
    List<WorkoutSession>? history,
    Future<void> Function(WorkoutSession session)? upsert,
  }) async {
    if (draft.isCompleted) {
      return WorkoutCompletionResult(
        session: draft,
        records: const [],
        personalRecords: const [],
      );
    }
    if (!draft.hasStarted) {
      throw StateError('Start the timer before logging this workout.');
    }

    final stoppedAt = now ?? DateTime.now();
    final finalDuration = draft.elapsedSeconds(stoppedAt);
    final baseline = List<WorkoutSession>.unmodifiable(
      (history ?? HiveService.getCompletedSessions(splitId: draft.splitId))
          .where((session) => session.id != draft.id),
    );
    final completed = draft.copyWith(
      isCompleted: true,
      timerStartedAt: null,
      durationSeconds: finalDuration,
    );
    const analytics = StatisticsAnalyticsService();
    final records = analytics.sessionRecords([
      ...analytics.eligibleSessions(baseline, splitId: draft.splitId),
      completed,
    ], completed);

    await (upsert ?? HiveService.upsertSession)(completed);
    return WorkoutCompletionResult(
      session: completed,
      records: records,
      personalRecords: PRTrackingService.heaviestWeightResults(records),
    );
  }
}
