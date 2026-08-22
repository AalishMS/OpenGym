import 'package:flutter/foundation.dart';
import '../models/workout_session.dart';
import '../repositories/workout_session_repository.dart';

class WorkoutSessionProvider with ChangeNotifier {
  final WorkoutSessionRepository _repository = WorkoutSessionRepository();
  List<WorkoutSession> _sessions = [];
  WorkoutSession? _currentSession;
  int _currentWeek = 1;

  List<WorkoutSession> get sessions => _sessions;
  WorkoutSession? get currentSession => _currentSession;
  int get currentWeek => _currentWeek;

  WorkoutSessionProvider() {
    loadSessions();
  }

  void loadSessions() {
    _sessions = _repository.getSessions();
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
    await _repository.upsertSession(session);
    loadSessions();
  }

  /// Kept for API symmetry with the History edit screen.
  Future<void> updateSession(WorkoutSession session) async {
    await _repository.upsertSession(session);
    loadSessions();
  }

  Future<void> deleteSession(String id) async {
    await _repository.softDeleteSession(id);
    loadSessions();
  }

  List<int> getWeeksForPlan(String planName) =>
      _repository.getWeeksForPlan(planName);

  WorkoutSession? getSessionForPlanAndWeek(String planName, int week) =>
      _repository.getSessionForPlanAndWeek(planName, week);
}
