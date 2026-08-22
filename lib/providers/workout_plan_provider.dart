import 'package:flutter/foundation.dart';
import '../models/workout_plan.dart';
import '../repositories/workout_plan_repository.dart';
import '../services/sync_service.dart';

class WorkoutPlanProvider with ChangeNotifier {
  final WorkoutPlanRepository _repository = WorkoutPlanRepository();
  List<WorkoutPlan> _plans = [];

  List<WorkoutPlan> get plans => _plans;

  WorkoutPlanProvider() {
    loadPlans();
  }

  void loadPlans() {
    _plans = _repository.getPlans();
    notifyListeners();
  }

  Future<void> addPlan(WorkoutPlan plan) async {
    await _repository.addPlan(plan);
    loadPlans();
    SyncService.instance.scheduleSync();
  }

  Future<void> updatePlan(WorkoutPlan plan) async {
    await _repository.upsertPlan(plan);
    loadPlans();
    SyncService.instance.scheduleSync();
  }

  Future<void> deletePlan(String id) async {
    await _repository.softDeletePlan(id);
    loadPlans();
    SyncService.instance.scheduleSync();
  }
}
