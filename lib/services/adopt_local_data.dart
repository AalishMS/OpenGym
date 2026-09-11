import 'package:shared_preferences/shared_preferences.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';

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
    if (!SupabaseService.isConfigured) return;
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    await prepareLocalForUser(userId);
  }

  static Future<void> prepareLocalForUser(String userId) async {
    if (_preparedUserId == userId) return;

    final pending = _preparation;
    if (pending != null) {
      await pending;
      if (_preparedUserId == userId) return;
    }

    final preparation = _prepareLocalForUser(userId);
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
      // A different account signed in on this device: drop the previous user's
      // locally cached rows and their pull cursors before syncing.
      await HiveService.clearAllPlans();
      await HiveService.clearAllSessions();
      await HiveService.clearSplitData();
      await prefs.remove('splits_last_pulled');
      await prefs.remove('split_preferences_last_pulled');
      await prefs.remove('plans_last_pulled');
      await prefs.remove('sessions_last_pulled');
    }
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
        p.userId = userId;
        p.updatedAt ??= now;
        p.dirty = true;
        await HiveService.putPlanRaw(p);
      }
      for (final s in HiveService.getAllSessionsRaw()) {
        s.userId = userId;
        s.updatedAt ??= now;
        s.dirty = true;
        await HiveService.putSessionRaw(s);
      }
      await prefs.setBool(adoptedKey, true);
    }
  }

  /// Starts or joins the current user's network reconciliation.
  ///
  /// Callers intentionally do not await this on the launch path. Dirty rows
  /// remain queued when the request fails and connectivity/lifecycle events
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
