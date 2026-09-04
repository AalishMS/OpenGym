import 'package:flutter/foundation.dart';
import '../models/workout_plan.dart';
import '../repositories/workout_plan_repository.dart';
import '../services/hive_service.dart';
import '../services/sync_service.dart';
import 'split_provider.dart';

class WorkoutPlanProvider with ChangeNotifier {
  final WorkoutPlanRepository _repository = WorkoutPlanRepository();
  final SplitProvider? _splitProvider;
  List<WorkoutPlan> _plans = [];

  List<WorkoutPlan> get plans => _plans;

  WorkoutPlanProvider([this._splitProvider]) {
    _splitProvider?.addListener(loadPlans);
    loadPlans();
  }

  void loadPlans() {
    final splitId = _splitProvider?.activeSplitId;
    _plans =
        splitId == null
            ? HiveService.getPlans()
            : _repository.getPlans(splitId);
    notifyListeners();
  }

  Future<void> addPlan(WorkoutPlan plan) async {
    if (_splitProvider != null) plan.splitId ??= _requireActiveSplit();
    await _repository.addPlan(plan);
    loadPlans();
    SyncService.instance.scheduleSync();
  }

  Future<void> updatePlan(WorkoutPlan plan) async {
    if (_splitProvider != null) plan.splitId ??= _requireActiveSplit();
    await _repository.upsertPlan(plan);
    loadPlans();
    SyncService.instance.scheduleSync();
  }

  Future<void> deletePlan(String id) async {
    await _repository.softDeletePlan(id);
    loadPlans();
    SyncService.instance.scheduleSync();
  }

  String _requireActiveSplit() {
    final splitId = _splitProvider?.activeSplitId;
    if (splitId == null) throw StateError('No active split is available.');
    return splitId;
  }

  @override
  void dispose() {
    _splitProvider?.removeListener(loadPlans);
    super.dispose();
  }
}
