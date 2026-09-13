import 'package:flutter/foundation.dart';
import '../models/workout_session.dart';
import '../services/hive_service.dart';
import '../services/sync_service.dart';
import 'split_provider.dart';

class WorkoutSessionProvider with ChangeNotifier {
  final SplitProvider? _splitProvider;
  List<WorkoutSession> _sessions = [];

  List<WorkoutSession> get sessions => _sessions;
  String? get activeSplitId => _splitProvider?.activeSplitId;

  WorkoutSessionProvider([this._splitProvider]) {
    _splitProvider?.addListener(loadSessions);
    loadSessions();
  }

  void loadSessions() {
    final splitId = _splitProvider?.activeSplitId;
    _sessions =
        splitId == null
            ? HiveService.getCompletedSessions()
            : HiveService.getCompletedSessions(splitId: splitId);
    notifyListeners();
  }

  /// Upsert-by-id. This is the core fix for the append-only bug: repeated
  /// autosaves of the same (plan, week) session replace ONE row instead of
  /// appending new ones. The session carries its own stable id.
  Future<void> upsertSession(WorkoutSession session) async {
    if (_splitProvider != null) session.splitId ??= _requireActiveSplit();
    await HiveService.upsertSession(session);
    loadSessions();
    SyncService.instance.scheduleSync();
  }

  Future<void> deleteSession(String id) async {
    await HiveService.softDeleteSession(id);
    loadSessions();
    SyncService.instance.scheduleSync();
  }

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
