import 'package:shared_preferences/shared_preferences.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';

/// One-time-per-user adoption of on-device data into the signed-in account,
/// plus a shared-device guard. Call once after a successful login (from the
/// auth gate), before showing the main app.
class AdoptLocalData {
  AdoptLocalData._();

  static const _lastUserKey = 'lastUserId';

  /// Returns when it is safe to show the app. Never throws.
  static Future<void> run() async {
    if (!SupabaseService.isConfigured) return;
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();

    // --- 1. Shared-device guard --------------------------------------------
    final lastUser = prefs.getString(_lastUserKey);
    final userChanged = lastUser != null && lastUser != userId;
    if (userChanged) {
      // A different account signed in on this device: drop the previous user's
      // locally cached rows and their pull cursors before syncing.
      await HiveService.clearAllPlans();
      await HiveService.clearAllSessions();
      await prefs.remove('plans_last_pulled');
      await prefs.remove('sessions_last_pulled');
    }
    await prefs.setString(_lastUserKey, userId);

    // --- 2. Adoption (once per user on this device) -------------------------
    final adoptedKey = 'adopted_$userId';
    if (prefs.getBool(adoptedKey) == true) {
      // Already adopted here — a normal sync is enough.
      await SyncService.instance.syncNow();
      return;
    }

    try {
      // Stamp every local record for this user and mark dirty. If we cleared
      // above (userChanged), these lists are empty and this is a no-op.
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

      // Pull-before-push: merge anything the account already has (other
      // devices) so we don't clobber it, then push our now-dirty local data.
      await SyncService.instance.syncNow();

      await prefs.setBool(adoptedKey, true);
    } catch (e) {
      // Leave the flag unset so adoption retries on the next login.
      // ignore: avoid_print
      print('adoption failed (will retry next login): $e');
    }
  }
}
