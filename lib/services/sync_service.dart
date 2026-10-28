import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/split.dart';
import '../models/split_preference.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_plan.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../utils/training_block_identity.dart';
import 'hive_service.dart';
import 'supabase_service.dart';
import 'training_block_migration.dart';
import 'training_block_restore.dart';

enum SyncStatus {
  savedOnDevice,
  pending,
  synced,
  upgradeRequired,
  retryableError,
}

class _SyncAccount {
  final String id;
  final int generation;
  _SyncAccount(this.id) : generation = SupabaseService.accountGeneration;
  bool get current =>
      SupabaseService.currentUserId == id &&
      SupabaseService.accountGeneration == generation;
  void check() {
    if (!current) throw StateError('The sync account changed.');
  }
}

/// Whole-row LWW sync over the existing Hive graph. Table pulls use bounded
/// pages; full reconciliation repairs commits whose timestamps precede a cursor.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();
  static const _pageSize = 500;
  static const _tables = [
    'splits',
    'training_blocks',
    'training_weeks',
    'workout_plans',
    'workout_sessions',
    'workout_progress',
    'split_preferences',
  ];
  Future<void>? _activeSync;
  Future<void>? _exclusiveMutation;
  Timer? _debounce;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final StreamController<void> _statusChanges =
      StreamController<void>.broadcast();
  String? _lastSuccessfulUserId;
  String? _lastFailedUserId;
  String? _upgradeRequiredUserId;
  Stream<void> get changes => _changes.stream;
  Stream<void> get statusChanges => _statusChanges.stream;
  SupabaseClient get _db => SupabaseService.client;
  bool get _canSync =>
      SupabaseService.isConfigured && SupabaseService.currentUserId != null;

  SyncStatus get status {
    final user = SupabaseService.currentUserId;
    if (user == null) return SyncStatus.savedOnDevice;
    if (_upgradeRequiredUserId == user) return SyncStatus.upgradeRequired;
    if (_lastFailedUserId == user) return SyncStatus.retryableError;
    if (HiveService.getDirtySplits(deleted: false).isNotEmpty ||
        HiveService.getDirtySplits(deleted: true).isNotEmpty ||
        HiveService.getDirtySplitPreferences().isNotEmpty ||
        HiveService.getDirtyPlans().isNotEmpty ||
        HiveService.getDirtySessions().isNotEmpty ||
        HiveService.getAllTrainingBlocksRaw().any((r) => r.dirty == true) ||
        HiveService.getAllTrainingWeeksRaw().any((r) => r.dirty == true) ||
        HiveService.getAllWorkoutProgressRaw().any((r) => r.dirty == true)) {
      return SyncStatus.pending;
    }
    if (_activeSync != null || _lastSuccessfulUserId != user) {
      return SyncStatus.savedOnDevice;
    }
    return SyncStatus.synced;
  }

  void scheduleSync() {
    if (!_canSync) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
    _statusChanges.add(null);
  }

  Future<T> runExclusiveLocalMutation<T>(Future<T> Function() mutation) async {
    while (true) {
      final pending = _exclusiveMutation ?? _activeSync;
      if (pending == null) break;
      await pending;
    }
    _debounce?.cancel();
    _debounce = null;
    final completer = Completer<void>();
    _exclusiveMutation = completer.future;
    try {
      return await mutation();
    } finally {
      _exclusiveMutation = null;
      completer.complete();
    }
  }

  Future<void> syncNow({bool fullReconciliation = false}) async {
    if (!_canSync) return;
    final mutation = _exclusiveMutation;
    if (mutation != null) await mutation;
    final active = _activeSync;
    if (active != null) {
      await active;
      if (fullReconciliation) return syncNow(fullReconciliation: true);
      return;
    }
    final sync = _runSyncCycle(fullReconciliation);
    _activeSync = sync;
    _statusChanges.add(null);
    return sync;
  }

  Future<T> _checked<T>(Future<T> future, _SyncAccount account) async {
    final result = await future;
    account.check();
    return result;
  }

  Future<void> _runSyncCycle(bool requestedFull) async {
    final user = SupabaseService.currentUserId;
    if (user == null) return;
    final account = _SyncAccount(user);
    try {
      await _checked(TrainingBlockRestore().recover(ownerId: user), account);
      _db.rest.headers['x-opengym-training-schema'] = '1';
      await _checked(
        HiveService.recoverTrainingWeekRebase(ownerId: user),
        account,
      );
      // Activation/backfill is serialized on the server, and runs before any
      // migrated upload. Missing schema or an incompatible API fails closed.
      final capability = await _checked(
        _db.rpc('activate_training_schema'),
        account,
      );
      if (capability is! int || capability != 1) {
        throw StateError('The training schema was not acknowledged.');
      }
      final prefs = await _checked(SharedPreferences.getInstance(), account);
      final lastFull = DateTime.tryParse(
        prefs.getString('training_full_pull_$user') ?? '',
      );
      final full =
          requestedFull ||
          lastFull == null ||
          DateTime.now().difference(lastFull) >= const Duration(hours: 24);
      for (final table in _tables) {
        await _pull(
          table,
          account,
          full:
              full ||
              table == 'splits' ||
              table == 'training_blocks' ||
              table == 'training_weeks',
        );
      }
      await _checked(HiveService.ensureSplitWorkspace(user), account);
      await _checked(
        TrainingBlockMigration().normalizeUnderGate(ownerId: user),
        account,
      );
      for (final split in HiveService.getDirtySplits(deleted: false)) {
        await _pushSplit(split, account);
      }
      for (final block in HiveService.getAllTrainingBlocksRaw().where(
        (r) => r.dirty == true,
      )) {
        await _push('training_blocks', _blockRow(block), account);
      }
      for (final week in HiveService.getAllTrainingWeeksRaw().where(
        (r) => r.dirty == true,
      )) {
        await _pushWeek(week, account);
      }
      for (final plan in HiveService.getDirtyPlans()) {
        await _push('workout_plans', _planRow(plan), account);
      }
      for (final session in HiveService.getDirtySessions()) {
        await _push('workout_sessions', _sessionRow(session), account);
      }
      for (final progress in HiveService.getAllWorkoutProgressRaw().where(
        (r) => r.dirty == true,
      )) {
        await _push('workout_progress', _progressRow(progress), account);
      }
      for (final preference in HiveService.getDirtySplitPreferences()) {
        await _push('split_preferences', _preferenceRow(preference), account);
      }
      for (final split in HiveService.getDirtySplits(deleted: true)) {
        await _push('splits', _splitRow(split), account);
      }
      for (final table in _tables) {
        await _pull(table, account, full: false);
      }
      if (full) {
        await _checked(
          prefs.setString(
            'training_full_pull_$user',
            DateTime.now().toUtc().toIso8601String(),
          ),
          account,
        );
      }
      _lastSuccessfulUserId = user;
      _lastFailedUserId = null;
      _upgradeRequiredUserId = null;
    } catch (error) {
      if (account.current) {
        _lastFailedUserId = user;
        if (error is PostgrestException && error.code == 'PT426') {
          _upgradeRequiredUserId = user;
        }
        debugPrint('Sync deferred: $error');
      }
    } finally {
      _activeSync = null;
      if (account.current) {
        _changes.add(null);
        _statusChanges.add(null);
      }
    }
  }

  static String _cursorKey(String table) => switch (table) {
    'workout_plans' => 'plans_last_pulled',
    'workout_sessions' => 'sessions_last_pulled',
    _ => '${table}_last_pulled',
  };

  Future<void> _pull(
    String table,
    _SyncAccount account, {
    required bool full,
  }) async {
    final prefs = await _checked(SharedPreferences.getInstance(), account);
    final cursor = prefs.getString(_cursorKey(table));
    String? maxSeq = cursor;
    String? afterId;
    String? afterSequence;
    final idColumn = table == 'split_preferences' ? 'user_id' : 'id';
    while (true) {
      var query = _db.from(table).select().eq('user_id', account.id);
      if (full) {
        if (afterId != null) query = query.gt(idColumn, afterId);
      } else {
        if (cursor != null) query = query.gte('server_seq', cursor);
        if (afterId != null) {
          query = query.or(
            'server_seq.gt.$afterSequence,and(server_seq.eq.$afterSequence,$idColumn.gt.$afterId)',
          );
        }
      }
      final request =
          full
              ? query.order(idColumn, ascending: true).limit(_pageSize)
              : query
                  .order('server_seq', ascending: true)
                  .order(idColumn, ascending: true)
                  .limit(_pageSize);
      final rows = await _checked(request, account);
      for (final row in rows) {
        account.check();
        await _checked(_applyRow(table, row, account.id), account);
        maxSeq = _maxSequence(maxSeq, row['server_seq']);
      }
      if (rows.length < _pageSize) break;
      afterId = rows.last[idColumn] as String;
      afterSequence = rows.last['server_seq'] as String;
    }
    // No cursor passes a row that failed graph validation or local persistence.
    if (maxSeq != null) {
      await _checked(prefs.setString(_cursorKey(table), maxSeq), account);
    }
  }

  bool _isBootstrap(String table, String id) {
    if (table == 'training_blocks') {
      final b = HiveService.getTrainingBlockById(id);
      return b != null &&
          b.updatedAt == null &&
          b.id == legacyTrainingBlockId(b.splitId);
    }
    if (table == 'training_weeks') {
      final w = HiveService.getTrainingWeekById(id);
      return w != null &&
          w.updatedAt == null &&
          w.id == legacyTrainingWeekId(w.splitId, w.number);
    }
    if (table == 'workout_progress') {
      final p = HiveService.getWorkoutProgressById(id);
      return p != null &&
          p.updatedAt == null &&
          p.revision == initialProgressRevision(p.splitId, p.planId);
    }
    return false;
  }

  Future<void> _push(
    String table,
    Map<String, dynamic> row,
    _SyncAccount account,
  ) async {
    account.check();
    if (row['user_id'] != account.id) {
      throw StateError('A pending row belongs to a different account.');
    }
    _validateRow(table, row, account.id);
    final id = (row['id'] ?? row['user_id']) as String;
    final bootstrap = _isBootstrap(table, id) && row['deleted_at'] == null;
    var rows = await _checked(
      _db.from(table).upsert(row, ignoreDuplicates: bootstrap).select(),
      account,
    );
    if (bootstrap && rows.isEmpty) {
      rows = await _checked(
        _db
            .from(table)
            .select()
            .eq('user_id', account.id)
            .eq('id', id)
            .limit(1),
        account,
      );
    }
    if (rows.length != 1) {
      throw StateError('The server did not acknowledge this write.');
    }
    final acknowledged = rows.single;
    final latest = _localRow(table, id);
    if (latest == null || !_same(latest, row)) return;
    if (!_rowMatches(row, acknowledged)) {
      await _checked(_applyRow(table, acknowledged, account.id), account);
      return;
    }
    await _checked(_markClean(table, id), account);
  }

  Future<void> _pushSplit(Split split, _SyncAccount account) async {
    for (var attempt = 0; attempt <= 5; attempt++) {
      try {
        await _push('splits', _splitRow(split), account);
        return;
      } on PostgrestException catch (error) {
        final capacity =
            error.code == '23514' &&
            error.message.contains('at most 5 active splits');
        if ((capacity || error.code == '23505') &&
            await _releaseDeletedSplit(
              account,
              name: capacity ? null : split.name,
            )) {
          continue;
        }
        if (error.code != '23505') rethrow;
        final rows = await _checked(
          _db
              .from('splits')
              .select('name')
              .eq('user_id', account.id)
              .isFilter('deleted_at', null),
          account,
        );
        final names =
            rows.map((r) => (r['name'] as String).toLowerCase()).toSet();
        var index = 2;
        String candidate;
        do {
          final suffix = ' ($index)';
          candidate =
              '${split.name.substring(0, split.name.length.clamp(0, 24 - suffix.length))}$suffix';
          index++;
        } while (names.contains(candidate.toLowerCase()));
        final renamed = split.copyWith(
          name: candidate,
          updatedAt: DateTime.now(),
          dirty: true,
        );
        await _checked(HiveService.putSplitRaw(renamed), account);
        await _push('splits', _splitRow(renamed), account);
        return;
      }
    }
    throw StateError('Split replacement could not free capacity.');
  }

  /// Restores may replace all five profile identities. Release one pending
  /// tombstone only after the server rejects capacity/name reuse; ordinary
  /// cycles retain parents-first / deleted-splits-last ordering.
  Future<bool> _releaseDeletedSplit(
    _SyncAccount account, {
    String? name,
  }) async {
    final deleted =
        HiveService.getDirtySplits(deleted: true)
            .where(
              (s) => name == null || s.name.toLowerCase() == name.toLowerCase(),
            )
            .toList();
    if (deleted.isEmpty) return false;
    final remote = await _checked(
      _db
          .from('splits')
          .select()
          .eq('user_id', account.id)
          .isFilter('deleted_at', null),
      account,
    );
    final prefs = await _checked(
      _db.from('split_preferences').select().eq('user_id', account.id),
      account,
    );
    final active = prefs.firstOrNull?['active_split_id'];
    final candidates =
        deleted.where((s) => remote.any((r) => r['id'] == s.id)).toList()..sort(
          (a, b) => (a.id == active ? 1 : 0).compareTo(b.id == active ? 1 : 0),
        );
    if (candidates.isEmpty) return false;
    final target = candidates.first;
    if (target.id == active) {
      final alternate =
          remote
              .where(
                (r) =>
                    r['id'] != active &&
                    HiveService.getSplitById(r['id'] as String)?.deletedAt ==
                        null &&
                    HiveService.getSplitById(r['id'] as String) != null,
              )
              .firstOrNull;
      final preference = HiveService.getSplitPreference(account.id);
      if (alternate == null || preference == null) return false;
      await _push('split_preferences', {
        ..._preferenceRow(preference),
        'active_split_id': alternate['id'],
      }, account);
    }
    await _push('splits', _splitRow(target), account);
    return true;
  }

  Future<void> _pushWeek(TrainingWeek original, _SyncAccount account) async {
    var week = original;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _push('training_weeks', _weekRow(week), account);
        return;
      } on PostgrestException catch (error) {
        if (error.code != '23505' || attempt == 2) rethrow;
        // Refresh all competing weeks, retaining the rejected local week ID.
        await _pull('training_weeks', account, full: true);
        final numbers = HiveService.weeksForBlock(
          week.splitId,
          week.blockId,
        ).map((w) => w.number);
        final next = numbers.fold<int>(0, (max, n) => n > max ? n : max) + 1;
        week = week.copyWith(
          number: next,
          updatedAt: DateTime.now(),
          dirty: true,
        );
        await _checked(
          HiveService.persistTrainingWeekRebase(week, ownerId: account.id),
          account,
        );
      }
    }
  }

  void _validateRow(String table, Map<String, dynamic> row, String owner) {
    if (row['user_id'] != owner) {
      throw StateError('Remote row has the wrong owner.');
    }
    if (table == 'splits') return;
    final splitId =
        (table == 'split_preferences'
                ? row['active_split_id']
                : row['split_id'])
            as String;
    final split = HiveService.getSplitById(splitId);
    if (split == null ||
        split.userId != owner ||
        (row['deleted_at'] == null && split.deletedAt != null)) {
      throw StateError('The owning split is unavailable. Retry sync.');
    }
    if (table == 'training_weeks') {
      final parent = HiveService.getTrainingBlockById(
        row['block_id'] as String,
      );
      if (parent == null ||
          parent.splitId != splitId ||
          parent.userId != owner ||
          (row['deleted_at'] == null && parent.deletedAt != null)) {
        throw StateError('The owning block is unavailable. Retry sync.');
      }
    }
    if (table == 'workout_progress' ||
        (table == 'workout_sessions' && row['training_week_id'] != null)) {
      final week = HiveService.getTrainingWeekById(
        (table == 'workout_progress'
                ? row['active_week_id']
                : row['training_week_id'])
            as String,
      );
      if (week == null ||
          week.splitId != splitId ||
          week.userId != owner ||
          (row['deleted_at'] == null && week.deletedAt != null)) {
        throw StateError(
          'The linked training week is unavailable. Retry sync.',
        );
      }
      if (table == 'workout_sessions' && week.number != row['week_number']) {
        throw StateError('The session week label conflicts with its link.');
      }
    }
    if (table == 'workout_progress') {
      final plan = HiveService.getPlanById(row['plan_id'] as String);
      if (plan == null ||
          plan.splitId != splitId ||
          plan.userId != owner ||
          (row['deleted_at'] == null && plan.deletedAt != null)) {
        throw StateError('The progress plan is unavailable. Retry sync.');
      }
    }
  }

  bool _dominatedByParentDeletion(
    String table,
    Map<String, dynamic> row,
    String owner,
  ) {
    if (table == 'splits' ||
        row['deleted_at'] != null ||
        row['user_id'] != owner) {
      return false;
    }
    final splitId =
        (table == 'split_preferences'
                ? row['active_split_id']
                : row['split_id'])
            as String;
    final split = HiveService.getSplitById(splitId);
    if (split != null && split.userId == owner && split.deletedAt != null) {
      return true;
    }
    if (table == 'training_weeks') {
      final block = HiveService.getTrainingBlockById(row['block_id'] as String);
      if (block != null &&
          block.userId == owner &&
          block.splitId == splitId &&
          block.deletedAt != null) {
        return true;
      }
    }
    if (table == 'workout_sessions' || table == 'workout_progress') {
      final weekId =
          (table == 'workout_progress'
                  ? row['active_week_id']
                  : row['training_week_id'])
              as String?;
      final week =
          weekId == null ? null : HiveService.getTrainingWeekById(weekId);
      if (week != null &&
          week.userId == owner &&
          week.splitId == splitId &&
          week.deletedAt != null) {
        return true;
      }
    }
    if (table == 'workout_progress') {
      final plan = HiveService.getPlanById(row['plan_id'] as String);
      if (plan != null &&
          plan.userId == owner &&
          plan.splitId == splitId &&
          plan.deletedAt != null) {
        return true;
      }
    }
    return false;
  }

  Future<void> _applyRow(
    String table,
    Map<String, dynamic> row,
    String owner,
  ) async {
    // A durable parent deletion already represents the outcome for stale live
    // descendants. Do not resurrect them or block uploading the pending delete.
    if (_dominatedByParentDeletion(table, row, owner)) return;
    _validateRow(table, row, owner);
    final id = (row['id'] ?? row['user_id']) as String;
    final local = _localRow(table, id);
    final remoteTime = _parseTs(row['updated_at']);
    final localTime = _parseTs(local?['updated_at']);
    var wins =
        row['deleted_at'] != null ||
        local == null ||
        localTime == null ||
        (remoteTime != null && !localTime.isAfter(remoteTime));
    if (local?['deleted_at'] != null && row['deleted_at'] == null) wins = false;
    if (table == 'workout_progress' &&
        local != null &&
        local['deleted_at'] == null &&
        row['deleted_at'] == null &&
        localTime == remoteTime) {
      wins =
          (row['revision'] as String).compareTo(local['revision'] as String) >=
          0;
    }
    if (table == 'workout_progress' &&
        local != null &&
        local['revision'] ==
            initialProgressRevision(
              local['split_id'] as String,
              local['plan_id'] as String,
            )) {
      wins = row['deleted_at'] != null || local['deleted_at'] == null;
    }
    if (_isBootstrap(table, id) && local?['deleted_at'] == null) wins = true;
    if (!wins) return;
    switch (table) {
      case 'splits':
        final value = Split(
          id: id,
          userId: owner,
          name: row['name'] as String,
          createdAt: _parseTs(row['created_at'])!,
          updatedAt: remoteTime,
          deletedAt: _parseTs(row['deleted_at']),
          dirty: false,
        );
        await HiveService.putSplitRaw(value);
        if (value.deletedAt != null) await _tombstoneSplitChildren(value);
      case 'training_blocks':
        await HiveService.putTrainingBlockRaw(
          TrainingBlock(
            id: id,
            splitId: row['split_id'] as String,
            name: row['name'] as String,
            position: row['position'] as int,
            createdAt: _parseTs(row['created_at'])!,
            updatedAt: remoteTime,
            deletedAt: _parseTs(row['deleted_at']),
            userId: owner,
            dirty: false,
          ),
        );
      case 'training_weeks':
        final remoteWeek = TrainingWeek(
          id: id,
          splitId: row['split_id'] as String,
          blockId: row['block_id'] as String,
          number: row['number'] as int,
          createdAt: _parseTs(row['created_at'])!,
          updatedAt: remoteTime,
          deletedAt: _parseTs(row['deleted_at']),
          userId: owner,
          dirty: false,
        );
        if (local != null && local['number'] != remoteWeek.number) {
          await HiveService.persistTrainingWeekRebase(
            remoteWeek,
            ownerId: owner,
          );
        } else {
          await HiveService.putTrainingWeekRaw(remoteWeek);
        }
      case 'workout_plans':
        final data = _canonicalData(row, ['id', 'splitId']);
        final value = WorkoutPlan.fromJson(data);
        value.userId = owner;
        value.updatedAt = remoteTime;
        value.deletedAt = _parseTs(row['deleted_at']);
        value.dirty = false;
        await HiveService.putPlanRaw(value);
      case 'workout_sessions':
        final data = _canonicalData(row, [
          'id',
          'splitId',
          'planId',
          'trainingWeekId',
        ]);
        final value = WorkoutSession.fromJson(data);
        value.userId = owner;
        value.updatedAt = remoteTime;
        value.deletedAt = _parseTs(row['deleted_at']);
        value.dirty = false;
        await HiveService.putSessionRaw(value);
      case 'workout_progress':
        await HiveService.putWorkoutProgressRaw(
          WorkoutProgress(
            id: id,
            splitId: row['split_id'] as String,
            planId: row['plan_id'] as String,
            activeWeekId: row['active_week_id'] as String,
            state: row['state'] as String,
            revision: row['revision'] as String,
            updatedAt: remoteTime,
            deletedAt: _parseTs(row['deleted_at']),
            userId: owner,
            dirty: false,
          ),
        );
      case 'split_preferences':
        await HiveService.putSplitPreferenceRaw(
          SplitPreference(
            userId: owner,
            activeSplitId: row['active_split_id'] as String,
            updatedAt: remoteTime,
            dirty: false,
          ),
        );
    }
  }

  Future<void> _tombstoneSplitChildren(Split split) async {
    final deleted = split.deletedAt!;
    for (final b in HiveService.getAllTrainingBlocksRaw().where(
      (r) => r.splitId == split.id && r.deletedAt == null,
    )) {
      await HiveService.putTrainingBlockRaw(
        b.copyWith(deletedAt: deleted, dirty: true),
      );
    }
    for (final w in HiveService.getAllTrainingWeeksRaw().where(
      (r) => r.splitId == split.id && r.deletedAt == null,
    )) {
      await HiveService.putTrainingWeekRaw(
        w.copyWith(deletedAt: deleted, dirty: true),
      );
    }
    for (final p in HiveService.getAllWorkoutProgressRaw().where(
      (r) => r.splitId == split.id && r.deletedAt == null,
    )) {
      await HiveService.putWorkoutProgressRaw(
        p.copyWith(deletedAt: deleted, dirty: true),
      );
    }
    for (final p in HiveService.getAllPlansRaw().where(
      (r) => r.splitId == split.id && r.deletedAt == null,
    )) {
      await HiveService.putPlanRaw(p.copyWith(deletedAt: deleted, dirty: true));
    }
    for (final session in HiveService.getAllSessionsRaw().where(
      (r) => r.splitId == split.id && r.deletedAt == null,
    )) {
      await HiveService.putSessionRaw(
        session.copyWith(deletedAt: deleted, dirty: true),
      );
    }
  }

  Map<String, dynamic> _canonicalData(
    Map<String, dynamic> row,
    List<String> links,
  ) {
    final data = Map<String, dynamic>.from(row['data'] as Map);
    const columns = {
      'id': 'id',
      'splitId': 'split_id',
      'planId': 'plan_id',
      'trainingWeekId': 'training_week_id',
    };
    for (final link in links) {
      final canonical = row[columns[link]];
      if (data[link] != null && data[link] != canonical) {
        throw StateError('Conflicting remote $link.');
      }
      data[link] = canonical;
    }
    return data;
  }

  static String _ts(DateTime? value) =>
      (value ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
          .toUtc()
          .toIso8601String();
  Map<String, dynamic> _splitRow(Split r) => {
    'id': r.id,
    'user_id': r.userId,
    'name': r.name,
    'created_at': _ts(r.createdAt),
    'updated_at': _ts(r.updatedAt ?? r.createdAt),
    'deleted_at': r.deletedAt == null ? null : _ts(r.deletedAt),
  };
  Map<String, dynamic> _blockRow(TrainingBlock r) => {
    'id': r.id,
    'user_id': r.userId,
    'split_id': r.splitId,
    'name': r.name,
    'position': r.position,
    'created_at': _ts(r.createdAt),
    'updated_at': _ts(r.updatedAt),
    'deleted_at': r.deletedAt == null ? null : _ts(r.deletedAt),
  };
  Map<String, dynamic> _weekRow(TrainingWeek r) => {
    'id': r.id,
    'user_id': r.userId,
    'split_id': r.splitId,
    'block_id': r.blockId,
    'number': r.number,
    'created_at': _ts(r.createdAt),
    'updated_at': _ts(r.updatedAt),
    'deleted_at': r.deletedAt == null ? null : _ts(r.deletedAt),
  };
  Map<String, dynamic> _planRow(WorkoutPlan r) => {
    'id': r.id,
    'user_id': r.userId,
    'split_id': r.splitId,
    'name': r.name,
    'plan_color': r.planColor,
    'data': r.toJson(),
    'updated_at': _ts(r.updatedAt),
    'deleted_at': r.deletedAt == null ? null : _ts(r.deletedAt),
  };
  Map<String, dynamic> _sessionRow(WorkoutSession r) => {
    'id': r.id,
    'user_id': r.userId,
    'split_id': r.splitId,
    'plan_id': r.planId,
    'training_week_id': r.trainingWeekId,
    'plan_name': r.planName,
    'week_number': r.weekNumber,
    'date': _ts(r.date),
    'data': r.toJson(),
    'updated_at': _ts(r.updatedAt ?? r.date),
    'deleted_at': r.deletedAt == null ? null : _ts(r.deletedAt),
  };
  Map<String, dynamic> _progressRow(WorkoutProgress r) => {
    'id': r.id,
    'user_id': r.userId,
    'split_id': r.splitId,
    'plan_id': r.planId,
    'active_week_id': r.activeWeekId,
    'state': r.state,
    'revision': r.revision,
    'updated_at': _ts(r.updatedAt),
    'deleted_at': r.deletedAt == null ? null : _ts(r.deletedAt),
  };
  Map<String, dynamic> _preferenceRow(SplitPreference r) => {
    'user_id': r.userId,
    'active_split_id': r.activeSplitId,
    'updated_at': _ts(r.updatedAt),
  };

  Map<String, dynamic>? _localRow(String table, String id) {
    switch (table) {
      case 'splits':
        final r = HiveService.getSplitById(id);
        return r == null ? null : _splitRow(r);
      case 'training_blocks':
        final r = HiveService.getTrainingBlockById(id);
        return r == null ? null : _blockRow(r);
      case 'training_weeks':
        final r = HiveService.getTrainingWeekById(id);
        return r == null ? null : _weekRow(r);
      case 'workout_plans':
        final r = HiveService.getPlanById(id);
        return r == null ? null : _planRow(r);
      case 'workout_sessions':
        final r = HiveService.getSessionById(id);
        return r == null ? null : _sessionRow(r);
      case 'workout_progress':
        final r = HiveService.getWorkoutProgressById(id);
        return r == null ? null : _progressRow(r);
      case 'split_preferences':
        final r = HiveService.getSplitPreference(id);
        return r == null ? null : _preferenceRow(r);
      default:
        throw StateError('Unknown sync table.');
    }
  }

  Future<void> _markClean(String table, String id) async {
    switch (table) {
      case 'splits':
        await HiveService.clearSplitDirty(id);
      case 'workout_plans':
        await HiveService.clearPlanDirty(id);
      case 'workout_sessions':
        await HiveService.clearSessionDirty(id);
      case 'split_preferences':
        await HiveService.clearSplitPreferenceDirty(id);
      case 'training_blocks':
        final row = HiveService.getTrainingBlockById(id)!;
        await HiveService.putTrainingBlockRaw(row.copyWith(dirty: false));
      case 'training_weeks':
        final row = HiveService.getTrainingWeekById(id)!;
        await HiveService.putTrainingWeekRaw(row.copyWith(dirty: false));
      case 'workout_progress':
        final row = HiveService.getWorkoutProgressById(id)!;
        await HiveService.putWorkoutProgressRaw(row.copyWith(dirty: false));
    }
  }

  bool _rowMatches(Map<String, dynamic> sent, Map<String, dynamic> saved) =>
      sent.entries.every(
        (e) =>
            ['updated_at', 'created_at', 'deleted_at', 'date'].contains(e.key)
                ? _parseTs(e.value) == _parseTs(saved[e.key])
                : _same(e.value, saved[e.key]),
      );
  bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_same(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  DateTime? _parseTs(dynamic value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();

  @visibleForTesting
  static String? maxSequence(String? current, dynamic candidate) =>
      _maxSequence(current, candidate);

  static String? _maxSequence(String? current, dynamic candidate) {
    if (candidate == null) return current;
    final value = candidate.toString();
    if (current == null) return value;

    final currentDt = DateTime.tryParse(current);
    final valueDt = DateTime.tryParse(value);
    if (currentDt != null &&
        valueDt != null &&
        (value.contains('T') || current.contains('T'))) {
      return valueDt.isAfter(currentDt) ? value : current;
    }

    final currentInt = BigInt.tryParse(current);
    final valueInt = BigInt.tryParse(value);
    if (currentInt != null && valueInt != null) {
      return valueInt > currentInt ? value : current;
    }

    if (currentDt != null && valueDt != null) {
      return valueDt.isAfter(currentDt) ? value : current;
    }

    return value.compareTo(current) > 0 ? value : current;
  }
}
