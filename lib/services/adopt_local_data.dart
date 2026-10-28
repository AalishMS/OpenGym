import 'package:shared_preferences/shared_preferences.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import 'training_block_migration.dart';
import 'training_block_restore.dart';

/// One-time-per-user adoption of on-device data into the signed-in account,
/// plus a shared-device guard.
class AdoptLocalData {
  AdoptLocalData._();

  static const _lastUserKey = 'lastUserId';
  static String? _preparedUserId;
  static String? _preparingUserId;
  static Future<void>? _preparation;
  static String? _syncingUserId;
  static Future<void>? _backgroundSync;

  static bool get isPreparedForCurrentUser {
    final userId = SupabaseService.currentUserId;
    return userId != null && _preparedUserId == userId;
  }

  /// Performs only the on-device work required before showing account data.
  ///
  /// This deliberately contains no network calls. A returning user can open
  /// cached data immediately, while a different user cannot see the previous
  /// account's cache during the handover.
  static Future<void> prepareLocal() async {
    if (!SupabaseService.isConfigured) {
      await prepareOffline();
      return;
    }
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    await prepareLocalForUser(userId);
  }

  static Future<void> prepareOffline() async {
    await SyncService.instance.runExclusiveLocalMutation(() async {
      await TrainingBlockRestore().recover(ownerId: null);
      await HiveService.ensureOfflineSplitWorkspace();
      await TrainingBlockMigration().normalizeUnderGate(ownerId: null);
    });
  }

  static Future<void> prepareLocalForUser(String userId) async {
    final pending = _preparation;
    if (pending != null) {
      await pending;
    }
    if (_preparedUserId == userId) return;
    _preparedUserId = null;

    final preparation = SyncService.instance.runExclusiveLocalMutation(
      () => _prepareLocalForUser(userId),
    );
    _preparingUserId = userId;
    _preparation = preparation;
    try {
      await preparation;
      _preparedUserId = userId;
    } finally {
      if (_preparingUserId == userId) {
        _preparingUserId = null;
        _preparation = null;
      }
    }
  }

  static Future<void> _prepareLocalForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();

    final lastUser = prefs.getString(_lastUserKey);
    final userChanged = lastUser != null && lastUser != userId;
    if (userChanged) {
      await TrainingBlockRestore().removeOwnerRecovery(lastUser);
      // A different account signed in on this device: drop the previous user's
      // locally cached rows and their pull cursors before syncing.
      await HiveService.clearAllPlans();
      await HiveService.clearAllSessions();
      await HiveService.clearSplitData();
      await HiveService.clearTrainingData();
      await prefs.remove('splits_last_pulled');
      await prefs.remove('split_preferences_last_pulled');
      await prefs.remove('plans_last_pulled');
      await prefs.remove('sessions_last_pulled');
      await prefs.remove('training_blocks_last_pulled');
      await prefs.remove('training_weeks_last_pulled');
      await prefs.remove('workout_progress_last_pulled');
    }
    if (!userChanged && lastUser == null) {
      // Finish unowned durable intents before stamping their fixed identities.
      await TrainingBlockRestore().recover(ownerId: null);
      await HiveService.recoverTrainingOperation(ownerId: null);
      await HiveService.recoverTrainingWeekRebase(ownerId: null);
    }
    await TrainingBlockRestore().recover(ownerId: userId);
    await prefs.setString(_lastUserKey, userId);

    final adoptedKey = 'adopted_$userId';
    final isFirstAdoption = prefs.getBool(adoptedKey) != true;

    await HiveService.ensureSplitWorkspace(
      userId,
      provisional: isFirstAdoption,
    );

    if (isFirstAdoption) {
      // Stamp legacy rows locally before the UI opens. The following sync pulls
      // remote split metadata first, so a provisional default never overwrites
      // an existing cloud workspace.
      final now = DateTime.now();
      for (final p in HiveService.getAllPlansRaw()) {
        if (p.userId != null && p.userId != userId) {
          throw StateError('Plan belongs to a different account.');
        }
        p.userId = userId;
        p.updatedAt ??= now;
        p.dirty = true;
        await HiveService.putPlanRaw(p);
      }
      for (final s in HiveService.getAllSessionsRaw()) {
        if (s.userId != null && s.userId != userId) {
          throw StateError('Session belongs to a different account.');
        }
        s.userId = userId;
        s.updatedAt ??= now;
        s.dirty = true;
        await HiveService.putSessionRaw(s);
      }
      for (final split in HiveService.getAllSplitsRaw()) {
        if (split.userId != null && split.userId != userId) {
          throw StateError('Split belongs to a different account.');
        }
        split.userId = userId;
        await HiveService.putSplitRaw(split);
      }
      for (final b in HiveService.getAllTrainingBlocksRaw()) {
        if (b.userId != null && b.userId != userId) {
          throw StateError('Block belongs to a different account.');
        }
        await HiveService.putTrainingBlockRaw(
          b.copyWith(userId: userId, dirty: true),
        );
      }
      for (final w in HiveService.getAllTrainingWeeksRaw()) {
        if (w.userId != null && w.userId != userId) {
          throw StateError('Week belongs to a different account.');
        }
        await HiveService.putTrainingWeekRaw(
          w.copyWith(userId: userId, dirty: true),
        );
      }
      for (final p in HiveService.getAllWorkoutProgressRaw()) {
        if (p.userId != null && p.userId != userId) {
          throw StateError('Progress belongs to a different account.');
        }
        await HiveService.putWorkoutProgressRaw(
          p.copyWith(userId: userId, dirty: true),
        );
      }
      await prefs.setBool(adoptedKey, true);
    }
    await TrainingBlockMigration().normalizeUnderGate(ownerId: userId);
    if (isFirstAdoption) await TrainingBlockRestore().removeOwnerRecovery(null);
  }

  /// Starts or joins the current user's network reconciliation.
  ///
  /// Callers intentionally do not await this on the launch path. Dirty rows
  /// remain queued when the request fails and later mutation/lifecycle events
  /// will retry later.
  static Future<void> syncInBackground() async {
    await prepareLocal();
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    final pending = _backgroundSync;
    final pendingUserId = _syncingUserId;
    if (pending != null) {
      await pending;
      if (pendingUserId == userId) return;
    }

    final sync = SyncService.instance.syncNow();
    _syncingUserId = userId;
    _backgroundSync = sync;
    try {
      await sync;
    } finally {
      if (_syncingUserId == userId) {
        _syncingUserId = null;
        _backgroundSync = null;
      }
    }
  }
}
