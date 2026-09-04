import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/split.dart';
import '../models/split_preference.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import 'hive_service.dart';
import 'supabase_service.dart';

/// Last-write-wins synchronization for the complete split workspace graph.
/// Split metadata is pulled before legacy bootstrap and parents are always
/// pushed before plans/sessions. Deleted splits are pushed last so their server
/// trigger can safely tombstone descendants after every child mutation lands.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _splitsTable = 'splits';
  static const _preferencesTable = 'split_preferences';
  static const _plansTable = 'workout_plans';
  static const _sessionsTable = 'workout_sessions';
  static const _splitsCursorKey = 'splits_last_pulled';
  static const _preferencesCursorKey = 'split_preferences_last_pulled';
  static const _plansCursorKey = 'plans_last_pulled';
  static const _sessionsCursorKey = 'sessions_last_pulled';

  Future<void>? _activeSync;
  Timer? _debounce;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  SupabaseClient get _db => SupabaseService.client;
  bool get _canSync =>
      SupabaseService.isConfigured && SupabaseService.currentUserId != null;

  void scheduleSync() {
    if (!_canSync) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow() async {
    if (!_canSync) return;
    final active = _activeSync;
    if (active != null) return active;
    final sync = _runSyncCycle();
    _activeSync = sync;
    return sync;
  }

  Future<void> _runSyncCycle() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    try {
      // Learn server-side deletions and the account selection before creating
      // a deterministic fallback for legacy/offline-only local data.
      try {
        await _pullSplits(userId);
        await _pullPreference(userId);
      } catch (e) {
        // Offline startup can still bootstrap and use a local workspace.
        // ignore: avoid_print
        print('split metadata pull deferred: $e');
      }
      await HiveService.ensureSplitWorkspace(userId);

      await _pushSplits(userId, deleted: false);
      await _pushPlans(userId);
      await _pushSessions(userId);
      await _pushPreferences(userId);
      await _pushSplits(userId, deleted: true);

      await _pullSplits(userId);
      await _pullPreference(userId);
      await _pullPlans(userId);
      await _pullSessions(userId);
    } catch (e) {
      // Dirty records and cursors are intentionally retained for a later run.
      // ignore: avoid_print
      print('sync cycle error (will retry): $e');
    } finally {
      _activeSync = null;
      _changes.add(null);
    }
  }

  Future<void> _pushSplits(String userId, {required bool deleted}) async {
    for (final split in HiveService.getDirtySplits(deleted: deleted)) {
      var value = split;
      if (value.userId != userId) {
        value.userId = userId;
        await HiveService.putSplitRaw(value);
      }
      try {
        await _db.from(_splitsTable).upsert(_splitRow(value, userId));
      } on PostgrestException catch (error) {
        if (deleted || error.code != '23505') rethrow;
        value = await _renameConflictingSplit(value, userId);
        await _db.from(_splitsTable).upsert(_splitRow(value, userId));
      }
      await HiveService.clearSplitDirty(value.id);
    }
  }

  Map<String, dynamic> _splitRow(Split split, String userId) => {
    'id': split.id,
    'user_id': userId,
    'name': split.name,
    'created_at': split.createdAt.toUtc().toIso8601String(),
    'updated_at': (split.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'deleted_at': split.deletedAt?.toUtc().toIso8601String(),
  };

  Future<Split> _renameConflictingSplit(Split split, String userId) async {
    final rows = await _db
        .from(_splitsTable)
        .select('name')
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    final names =
        (rows as List)
            .map((row) => (row as Map<String, dynamic>)['name'] as String)
            .map((name) => name.toLowerCase())
            .toSet();
    var index = 2;
    String candidate;
    do {
      final suffix = ' ($index)';
      final keep = 24 - suffix.length;
      candidate =
          '${split.name.substring(0, split.name.length.clamp(0, keep))}'
          '$suffix';
      index++;
    } while (names.contains(candidate.toLowerCase()));
    final renamed = split.copyWith(
      name: candidate,
      updatedAt: DateTime.now(),
      dirty: true,
    );
    await HiveService.putSplitRaw(renamed);
    return renamed;
  }

  Future<void> _pushPreferences(String userId) async {
    for (final preference in HiveService.getDirtySplitPreferences().where(
      (p) => p.userId == userId,
    )) {
      await _db.from(_preferencesTable).upsert({
        'user_id': userId,
        'active_split_id': preference.activeSplitId,
        'updated_at':
            (preference.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      });
      await HiveService.clearSplitPreferenceDirty(userId);
    }
  }

  Future<void> _pushPlans(String userId) async {
    for (final plan in HiveService.getDirtyPlans()) {
      if (plan.id == null || plan.splitId == null) continue;
      plan.userId = userId;
      await _db.from(_plansTable).upsert({
        'id': plan.id,
        'user_id': userId,
        'split_id': plan.splitId,
        'name': plan.name,
        'plan_color': plan.planColor,
        'data': plan.toJson(),
        'updated_at':
            (plan.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'deleted_at': plan.deletedAt?.toUtc().toIso8601String(),
      });
      await HiveService.clearPlanDirty(plan.id!);
    }
  }

  Future<void> _pushSessions(String userId) async {
    for (final session in HiveService.getDirtySessions()) {
      if (session.id == null || session.splitId == null) continue;
      session.userId = userId;
      await _db.from(_sessionsTable).upsert({
        'id': session.id,
        'user_id': userId,
        'split_id': session.splitId,
        'plan_id': session.planId,
        'plan_name': session.planName,
        'week_number': session.weekNumber,
        'date': session.date.toUtc().toIso8601String(),
        'data': session.toJson(),
        'updated_at':
            (session.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'deleted_at': session.deletedAt?.toUtc().toIso8601String(),
      });
      await HiveService.clearSessionDirty(session.id!);
    }
  }

  Future<void> _pullSplits(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getString(_splitsCursorKey);
    final rows = await _selectSince(_splitsTable, cursor, userId);
    String? maxSeq = cursor;
    for (final row in rows) {
      maxSeq = _maxSequence(maxSeq, row['server_seq']);
      final remote = Split(
        id: row['id'] as String,
        userId: row['user_id'] as String?,
        name: row['name'] as String,
        createdAt: _parseTs(row['created_at'])!,
        updatedAt: _parseTs(row['updated_at']),
        deletedAt: _parseTs(row['deleted_at']),
        dirty: false,
      );
      final local = HiveService.getSplitById(remote.id);
      if (remote.deletedAt != null ||
          _remoteWins(local?.updatedAt, remote.updatedAt)) {
        await HiveService.putSplitRaw(remote);
      }
    }
    if (maxSeq != null) await prefs.setString(_splitsCursorKey, maxSeq);
  }

  Future<void> _pullPreference(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getString(_preferencesCursorKey);
    final rows = await _selectSince(_preferencesTable, cursor, userId);
    String? maxSeq = cursor;
    for (final row in rows) {
      maxSeq = _maxSequence(maxSeq, row['server_seq']);
      final remote = SplitPreference(
        userId: row['user_id'] as String,
        activeSplitId: row['active_split_id'] as String,
        updatedAt: _parseTs(row['updated_at']),
        dirty: false,
      );
      final local = HiveService.getSplitPreference(userId);
      if (_remoteWins(local?.updatedAt, remote.updatedAt)) {
        await HiveService.putSplitPreferenceRaw(remote);
      }
    }
    if (maxSeq != null) {
      await prefs.setString(_preferencesCursorKey, maxSeq);
    }
  }

  Future<void> _pullPlans(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getString(_plansCursorKey);
    final rows = await _selectSince(_plansTable, cursor, userId);
    String? maxSeq = cursor;
    for (final row in rows) {
      maxSeq = _maxSequence(maxSeq, row['server_seq']);
      final remote = _planFromRow(row);
      final local = HiveService.getPlanById(remote.id!);
      if (remote.deletedAt != null ||
          _remoteWins(local?.updatedAt, remote.updatedAt)) {
        remote.dirty = false;
        await HiveService.putPlanRaw(remote);
      }
    }
    if (maxSeq != null) await prefs.setString(_plansCursorKey, maxSeq);
  }

  Future<void> _pullSessions(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getString(_sessionsCursorKey);
    final rows = await _selectSince(_sessionsTable, cursor, userId);
    String? maxSeq = cursor;
    for (final row in rows) {
      maxSeq = _maxSequence(maxSeq, row['server_seq']);
      final remote = _sessionFromRow(row);
      final local = HiveService.getSessionById(remote.id!);
      if (remote.deletedAt != null ||
          _remoteWins(local?.updatedAt, remote.updatedAt)) {
        remote.dirty = false;
        await HiveService.putSessionRaw(remote);
      }
    }
    if (maxSeq != null) await prefs.setString(_sessionsCursorKey, maxSeq);
  }

  Future<List<Map<String, dynamic>>> _selectSince(
    String table,
    String? cursor,
    String userId,
  ) async {
    final query =
        cursor == null
            ? _db.from(table).select().eq('user_id', userId)
            : _db
                .from(table)
                .select()
                .eq('user_id', userId)
                .gt('server_seq', cursor);
    final result = await query.order('server_seq', ascending: true);
    return (result as List).cast<Map<String, dynamic>>();
  }

  bool _remoteWins(DateTime? local, DateTime? remote) {
    if (local == null) return true;
    if (remote == null) return false;
    return !local.isAfter(remote);
  }

  String? _maxSequence(String? current, dynamic candidate) {
    if (candidate == null) return current;
    final value = candidate.toString();
    if (current == null) return value;
    return BigInt.parse(value) > BigInt.parse(current) ? value : current;
  }

  WorkoutPlan _planFromRow(Map<String, dynamic> row) {
    final plan = WorkoutPlan.fromJson(
      Map<String, dynamic>.from(row['data'] as Map),
    );
    plan.id = row['id'] as String;
    plan.userId = row['user_id'] as String?;
    plan.splitId = row['split_id'] as String;
    plan.updatedAt = _parseTs(row['updated_at']);
    plan.deletedAt = _parseTs(row['deleted_at']);
    return plan;
  }

  WorkoutSession _sessionFromRow(Map<String, dynamic> row) {
    final session = WorkoutSession.fromJson(
      Map<String, dynamic>.from(row['data'] as Map),
    );
    session.id = row['id'] as String;
    session.userId = row['user_id'] as String?;
    session.splitId = row['split_id'] as String;
    session.planId = row['plan_id'] as String?;
    session.updatedAt = _parseTs(row['updated_at']);
    session.deletedAt = _parseTs(row['deleted_at']);
    return session;
  }

  DateTime? _parseTs(dynamic value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();
}
