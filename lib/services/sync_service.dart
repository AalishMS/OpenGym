import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';

/// Hand-rolled last-write-wins sync between Hive (local source of truth) and
/// Supabase Postgres. Aggregate-root granularity: one plan / one session = one
/// row, whole `toJson()` stored in a `data` jsonb column.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _plansTable = 'workout_plans';
  static const _sessionsTable = 'workout_sessions';
  static const _plansCursorKey = 'plans_last_pulled';
  static const _sessionsCursorKey = 'sessions_last_pulled';

  bool _syncing = false;
  Timer? _debounce;

  SupabaseClient get _db => SupabaseService.client;

  bool get _canSync =>
      SupabaseService.isConfigured && SupabaseService.currentUserId != null;

  /// Debounced trigger — call after any local mutation. Coalesces bursts.
  void scheduleSync() {
    if (!_canSync) return; // offline / logged out: writes stay dirty locally
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      syncNow();
    });
  }

  /// Full cycle: push local changes, then pull remote changes. Safe to call
  /// concurrently — re-entrancy is guarded. Never throws to the caller.
  Future<void> syncNow() async {
    if (!_canSync || _syncing) return;
    _syncing = true;
    try {
      await _pushPlans();
      await _pushSessions();
      await _pullPlans();
      await _pullSessions();
    } catch (e) {
      // Swallow — will retry on the next trigger (resume/login/next mutation).
      // ignore: avoid_print
      print('sync cycle error (will retry): $e');
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // PUSH
  // ---------------------------------------------------------------------------
  Future<void> _pushPlans() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final dirty = HiveService.getDirtyPlans();
    for (final p in dirty) {
      if (p.id == null) continue; // shouldn't happen post-Phase-0
      // Defensive: stamp ownership so RLS `with check` accepts the row.
      if (p.userId != userId) {
        p.userId = userId;
        await HiveService.putPlanRaw(p);
      }
      final row = {
        'id': p.id,
        'user_id': userId,
        'name': p.name,
        'plan_color': p.planColor,
        'data': p.toJson(),
        'updated_at': (p.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'deleted_at': p.deletedAt?.toUtc().toIso8601String(),
      };
      await _db.from(_plansTable).upsert(row); // upsert by primary key (id)
      await HiveService.clearPlanDirty(p.id!);
    }
  }

  Future<void> _pushSessions() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final dirty = HiveService.getDirtySessions();
    for (final s in dirty) {
      if (s.id == null) continue;
      if (s.userId != userId) {
        s.userId = userId;
        await HiveService.putSessionRaw(s);
      }
      final row = {
        'id': s.id,
        'user_id': userId,
        'plan_id': s.planId,
        'plan_name': s.planName,
        'week_number': s.weekNumber,
        'date': s.date.toUtc().toIso8601String(),
        'data': s.toJson(),
        'updated_at': (s.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'deleted_at': s.deletedAt?.toUtc().toIso8601String(),
      };
      await _db.from(_sessionsTable).upsert(row);
      await HiveService.clearSessionDirty(s.id!);
    }
  }

  // ---------------------------------------------------------------------------
  // PULL  (rows with server_seq > cursor; cursor persisted per table)
  // ---------------------------------------------------------------------------
  Future<void> _pullPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getString(_plansCursorKey);
    final rows = await _selectSince(_plansTable, cursor);

    String? maxSeq = cursor;
    for (final row in rows) {
      final serverSeq = row['server_seq'] as String?;
      if (serverSeq != null &&
          (maxSeq == null || serverSeq.compareTo(maxSeq) > 0)) {
        maxSeq = serverSeq;
      }
      final remote = _planFromRow(row);
      if (remote.id == null) continue;
      final local = HiveService.getPlanById(remote.id!);
      if (_remoteWins(local?.updatedAt, remote.updatedAt)) {
        remote.dirty = false; // pulled record is authoritative, not dirty
        await HiveService.putPlanRaw(remote);
      }
    }
    if (maxSeq != null) await prefs.setString(_plansCursorKey, maxSeq);
  }

  Future<void> _pullSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getString(_sessionsCursorKey);
    final rows = await _selectSince(_sessionsTable, cursor);

    String? maxSeq = cursor;
    for (final row in rows) {
      final serverSeq = row['server_seq'] as String?;
      if (serverSeq != null &&
          (maxSeq == null || serverSeq.compareTo(maxSeq) > 0)) {
        maxSeq = serverSeq;
      }
      final remote = _sessionFromRow(row);
      if (remote.id == null) continue;
      final local = HiveService.getSessionById(remote.id!);
      if (_remoteWins(local?.updatedAt, remote.updatedAt)) {
        remote.dirty = false;
        await HiveService.putSessionRaw(remote);
      }
    }
    if (maxSeq != null) await prefs.setString(_sessionsCursorKey, maxSeq);
  }

  Future<List<Map<String, dynamic>>> _selectSince(
      String table, String? cursor) async {
    final query = _db.from(table).select();
    final filtered = cursor == null ? query : query.gt('server_seq', cursor);
    final res = await filtered.order('server_seq', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------------
  // LWW rule + row → model reconstruction
  // ---------------------------------------------------------------------------
  /// Remote wins if there is no local copy, or local has no timestamp, or the
  /// remote updatedAt is >= local updatedAt (tie goes to remote — harmless,
  /// same content). A local record that is NEWER than remote is left alone; its
  /// own dirty push will carry it up on the push half of the cycle.
  bool _remoteWins(DateTime? local, DateTime? remote) {
    if (local == null) return true;
    if (remote == null) return false;
    return !local.isAfter(remote);
  }

  WorkoutPlan _planFromRow(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from(row['data'] as Map);
    final plan = WorkoutPlan.fromJson(data);
    // Authoritative overrides from promoted columns:
    plan.id = row['id'] as String;
    plan.userId = row['user_id'] as String?;
    plan.updatedAt = _parseTs(row['updated_at']);
    plan.deletedAt = _parseTs(row['deleted_at']);
    return plan;
  }

  WorkoutSession _sessionFromRow(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from(row['data'] as Map);
    final session = WorkoutSession.fromJson(data);
    session.id = row['id'] as String;
    session.userId = row['user_id'] as String?;
    session.planId = row['plan_id'] as String?;
    session.updatedAt = _parseTs(row['updated_at']);
    session.deletedAt = _parseTs(row['deleted_at']);
    return session;
  }

  DateTime? _parseTs(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
