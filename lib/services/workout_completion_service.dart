import '../models/workout_session.dart';
import 'hive_service.dart';
import 'pr_tracking_service.dart';

class WorkoutCompletionResult {
  final WorkoutSession session;
  final List<PRResult> personalRecords;

  const WorkoutCompletionResult({
    required this.session,
    required this.personalRecords,
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
      return WorkoutCompletionResult(session: draft, personalRecords: const []);
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
    final prs = PRTrackingService.checkAgainstHistory(
      draft.exercises,
      baseline,
    );
    final completed = draft.copyWith(
      isCompleted: true,
      timerStartedAt: null,
      durationSeconds: finalDuration,
    );

    await (upsert ?? HiveService.upsertSession)(completed);
    return WorkoutCompletionResult(session: completed, personalRecords: prs);
  }
}
