import '../models/training_week.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../services/hive_service.dart';

/// Stable route intent. Display labels never identify a training location.
class WorkoutDestination {
  final String? planId;
  final String? weekId;
  final String? sessionId;

  const WorkoutDestination.active(String this.planId)
    : weekId = null,
      sessionId = null;
  const WorkoutDestination.week(String this.planId, String this.weekId)
    : sessionId = null;
  const WorkoutDestination.session(String this.sessionId)
    : planId = null,
      weekId = null;

  bool get isActive => weekId == null && sessionId == null;
  String get navigationKey => sessionId ?? 'plan:$planId:week:$weekId';

  /// Call when delivering the route, after any modal/save has finished.
  ResolvedWorkoutDestination? resolve({required String? ownerId}) {
    final session =
        sessionId == null ? null : HiveService.getSessionById(sessionId!);
    if (sessionId != null &&
        (session == null ||
            session.deletedAt != null ||
            session.userId != ownerId)) {
      return null;
    }
    final id = session?.planId ?? planId;
    var plan = id == null ? null : HiveService.getPlanById(id);
    if (plan?.deletedAt != null || plan?.userId != ownerId) plan = null;
    final splitId = session?.splitId ?? plan?.splitId;
    final split = splitId == null ? null : HiveService.getSplitById(splitId);
    if (split == null || split.deletedAt != null || split.userId != ownerId) {
      return null;
    }
    if (plan != null && plan.splitId != splitId) plan = null;
    if (session == null && plan == null) return null;
    final requestedWeek =
        session?.trainingWeekId ??
        weekId ??
        (sessionId == null
            ? HiveService.progressForPlan(splitId!, id!)?.activeWeekId
            : null);
    final week =
        requestedWeek == null
            ? null
            : HiveService.getTrainingWeekById(requestedWeek);
    final block =
        week == null ? null : HiveService.getTrainingBlockById(week.blockId);
    final liveWeek =
        week != null &&
        week.deletedAt == null &&
        week.splitId == splitId &&
        week.userId == ownerId &&
        block != null &&
        block.deletedAt == null &&
        block.userId == ownerId;
    // An exact orphan remains a historical detail, never another plan's logger.
    if (session == null && !liveWeek) return null;
    return ResolvedWorkoutDestination(
      plan: plan,
      week: liveWeek ? week : null,
      session: session,
    );
  }
}

class ResolvedWorkoutDestination {
  final WorkoutPlan? plan;
  final TrainingWeek? week;
  final WorkoutSession? session;
  const ResolvedWorkoutDestination({this.plan, this.week, this.session});
}
