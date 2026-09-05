import 'package:flutter/foundation.dart';
import '../models/workout_session.dart';
import '../repositories/workout_session_repository.dart';
import '../services/hive_service.dart';
import '../services/sync_service.dart';
import 'split_provider.dart';

class WorkoutSessionProvider with ChangeNotifier {
  final WorkoutSessionRepository _repository = WorkoutSessionRepository();
  final SplitProvider? _splitProvider;
  List<WorkoutSession> _sessions = [];
  WorkoutSession? _currentSession;
  int _currentWeek = 1;

  List<WorkoutSession> get sessions => _sessions;
  WorkoutSession? get currentSession => _currentSession;
  int get currentWeek => _currentWeek;

  WorkoutSessionProvider([this._splitProvider]) {
    _splitProvider?.addListener(loadSessions);
    loadSessions();
  }

  void loadSessions() {
    final splitId = _splitProvider?.activeSplitId;
    _sessions =
        splitId == null
            ? HiveService.getCompletedSessions()
            : _repository.getSessions(splitId);
    notifyListeners();
  }

  void setCurrentWeek(int week) {
    _currentWeek = week;
    notifyListeners();
  }

  /// Upsert-by-id. This is the core fix for the append-only bug: repeated
  /// autosaves of the same (plan, week) session replace ONE row instead of
  /// appending new ones. The session carries its own stable id.
  Future<void> upsertSession(WorkoutSession session) async {
    if (_splitProvider != null) session.splitId ??= _requireActiveSplit();
    await _repository.upsertSession(session);
    loadSessions();
    SyncService.instance.scheduleSync();
  }

  /// Kept for API symmetry with the History edit screen.
  Future<void> updateSession(WorkoutSession session) async {
    if (_splitProvider != null) session.splitId ??= _requireActiveSplit();
    await _repository.upsertSession(session);
    loadSessions();
    SyncService.instance.scheduleSync();
  }

  Future<void> deleteSession(String id) async {
    await _repository.softDeleteSession(id);
    loadSessions();
    SyncService.instance.scheduleSync();
  }

  List<int> getWeeksForPlan(String planName) =>
      _splitProvider == null
          ? HiveService.getWeeksForPlan(planName, null)
          : _repository.getWeeksForPlan(planName, _requireActiveSplit());

  WorkoutSession? getSessionForPlanAndWeek(String planName, int week) =>
      _splitProvider == null
          ? HiveService.getSessionForPlanAndWeek(planName, week, null)
          : _repository.getSessionForPlanAndWeek(
            planName,
            week,
            _requireActiveSplit(),
          );

  String _requireActiveSplit() {
    final splitId = _splitProvider?.activeSplitId;
    if (splitId == null) throw StateError('No active split is available.');
    return splitId;
  }

  @override
  void dispose() {
    _splitProvider?.removeListener(loadSessions);
    super.dispose();
  }
}
