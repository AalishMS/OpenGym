import '../models/workout_session.dart';
import '../services/hive_service.dart';

class WorkoutSessionRepository {
  List<WorkoutSession> getSessions(String splitId) =>
      HiveService.getSessions(splitId: splitId);

  WorkoutSession? getSessionById(String id) => HiveService.getSessionById(id);

  Future<void> upsertSession(WorkoutSession session) =>
      HiveService.upsertSession(session);

  Future<void> softDeleteSession(String id) =>
      HiveService.softDeleteSession(id);

  List<WorkoutSession> getSessionsForPlan(String planName, String splitId) =>
      HiveService.getSessionsForPlan(planName, splitId);

  List<int> getWeeksForPlan(String planName, String splitId) =>
      HiveService.getWeeksForPlan(planName, splitId);

  WorkoutSession? getSessionForPlanAndWeek(
    String planName,
    int weekNumber,
    String splitId,
  ) => HiveService.getSessionForPlanAndWeek(planName, weekNumber, splitId);

  WorkoutSession? getLastSessionForExercise(
    String exerciseName,
    String splitId,
  ) => HiveService.getLastSessionForExercise(exerciseName, splitId);
}
