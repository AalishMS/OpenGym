import 'package:flutter/foundation.dart';
import '../models/workout_plan.dart';
import '../repositories/workout_plan_repository.dart';

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
  }

  Future<void> updatePlan(WorkoutPlan plan) async {
    await _repository.upsertPlan(plan);
    loadPlans();
  }

  Future<void> deletePlan(String id) async {
    await _repository.softDeletePlan(id);
    loadPlans();
  }
}
