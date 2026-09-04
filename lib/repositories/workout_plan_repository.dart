import '../models/workout_plan.dart';
import '../services/hive_service.dart';

class WorkoutPlanRepository {
  List<WorkoutPlan> getPlans(String splitId) =>
      HiveService.getPlans(splitId: splitId);

  WorkoutPlan? getPlanById(String id) => HiveService.getPlanById(id);

  Future<void> addPlan(WorkoutPlan plan) => HiveService.addPlan(plan);

  Future<void> upsertPlan(WorkoutPlan plan) => HiveService.upsertPlan(plan);

  Future<void> softDeletePlan(String id) => HiveService.softDeletePlan(id);
}
