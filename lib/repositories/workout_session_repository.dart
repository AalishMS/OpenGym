import '../models/workout_session.dart';
import '../services/hive_service.dart';

class WorkoutSessionRepository {
  List<WorkoutSession> getSessions() => HiveService.getSessions();

  WorkoutSession? getSessionById(String id) => HiveService.getSessionById(id);

  Future<void> upsertSession(WorkoutSession session) =>
      HiveService.upsertSession(session);

  Future<void> softDeleteSession(String id) =>
      HiveService.softDeleteSession(id);

  List<WorkoutSession> getSessionsForPlan(String planName) =>
      HiveService.getSessionsForPlan(planName);

  List<int> getWeeksForPlan(String planName) =>
      HiveService.getWeeksForPlan(planName);

  WorkoutSession? getSessionForPlanAndWeek(String planName, int weekNumber) =>
      HiveService.getSessionForPlanAndWeek(planName, weekNumber);

  WorkoutSession? getLastSessionForExercise(String exerciseName) =>
      HiveService.getLastSessionForExercise(exerciseName);
}
