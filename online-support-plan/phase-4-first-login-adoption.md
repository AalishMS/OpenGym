# Phase 4 — First-login data adoption

**Goal:** the first time a user logs in on a device that already has local (offline) data, adopt
that data into their account — stamp it with their `userId` and push it — **once**, idempotently.
Also guard a shared device so one friend never inherits another's cached data.

**Depends on:** Phases 0–3.

---

## The two behaviors this phase adds

1. **Adoption (per user, once):** stamp every local record with the signed-in `userId`, ensure ids,
   mark `dirty`, **pull first** (learn what the account already has from other devices, LWW-merge),
   then push all dirty. Guarded by a `shared_preferences` flag `adopted_<userId>` so it never runs
   twice for the same account on this device.
2. **Shared-device reset:** track `lastUserId` in prefs. If a **different** user logs in (old value
   non-null and changed), **clear both Hive boxes before the first pull** so account B doesn't see
   account A's locally-cached rows. **First-ever login (old value null) keeps local data** — that's
   the adoption case for the offline user's own data.

> **Order matters:** the shared-device check runs **before** adoption. If we cleared because the
> user changed, there's nothing local to adopt (correct — that data belonged to the previous user
> and is safe in *their* account/cloud). If we did **not** clear (first-ever login), adoption
> stamps and uploads the existing offline data.

---

## Step 4.1 — New file `lib/services/adopt_local_data.dart`

```dart
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
```

> **Idempotency comes from three things:** client-UUID `upsert` (re-pushing the same id updates the
> same row, never duplicates), the per-user `adopted_<userId>` flag, and pull-first (so a record
> already in the account merges by id instead of being re-created).

---

## Step 4.2 — Wire adoption into the auth gate

In `lib/auth/auth_gate.dart`, replace the bare `SyncService.instance.syncNow()` (added in Phase 3)
with a call to adoption. Because adoption is async and the gate's `build` is sync, run it via a
tiny stateful wrapper so we can show a loading state during the first pull/clear.

Replace the whole `AuthGate` with:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/adopt_local_data.dart';
import '../screens/login_screen.dart';
import '../app_shell.dart'; // match the path used in main.dart

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.isConfigured) {
      return const AppShell();
    }
    return StreamBuilder<AuthState>(
      stream: SupabaseService.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = SupabaseService.auth.currentSession;
        if (session != null) {
          return const _PostLoginGate();
        }
        return const LoginScreen();
      },
    );
  }
}

/// Runs adoption once when a session is present, showing a loader until the
/// first clear/pull settles, then the app.
class _PostLoginGate extends StatefulWidget {
  const _PostLoginGate();

  @override
  State<_PostLoginGate> createState() => _PostLoginGateState();
}

class _PostLoginGateState extends State<_PostLoginGate> {
  late final Future<void> _ready = AdoptLocalData.run();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const AppShell();
      },
    );
  }
}
```

> The `late final Future _ready` is created once when `_PostLoginGate` mounts, so adoption runs a
> single time per login even though `build` may run many times. `AdoptLocalData.run()` never throws,
> so the `FutureBuilder` always reaches `done` and shows the app even if the network is down (local
> data is already stamped and will drain later).

> After this, the providers still need to reload from Hive so the UI reflects any pulled data. The
> simplest reliable approach: the providers' `loadPlans()`/`loadSessions()` run in their
> constructors; because `AppShell` is built fresh after `_ready` completes and the providers were
> created at app root, call a reload. If your provider instances live above `AuthGate` (created in
> `main.dart`'s `MultiProvider`), add a one-liner in `_PostLoginGateState` after `_ready` completes:
> use `context.read<WorkoutPlanProvider>().loadPlans()` and
> `context.read<WorkoutSessionProvider>().loadSessions()` inside a `then(...)` on `_ready`, guarded
> by `mounted`. This guarantees freshly pulled rows show without an app restart.

Concretely, replace `late final Future<void> _ready = AdoptLocalData.run();` with:

```dart
  late final Future<void> _ready = _adoptThenReload();

  Future<void> _adoptThenReload() async {
    await AdoptLocalData.run();
    if (!mounted) return;
    context.read<WorkoutPlanProvider>().loadPlans();
    context.read<WorkoutSessionProvider>().loadSessions();
  }
```

and add imports:

```dart
import 'package:provider/provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
```

---

## Step 4.3 — Analyze & run

```bash
flutter analyze
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

---

## Verification checklist

- [ ] **Offline data adoption:** on a fresh app with Supabase configured, create plans/sessions
      *before* logging in (or with a brand-new account). Log in → after the loader, the same data is
      present, and rows appear in Supabase with your `user_id`.
- [ ] **No duplication on re-login:** sign out and sign back in (same account) → no duplicate rows
      locally or in Supabase (adopted flag + upsert-by-id).
- [ ] **Second device:** log in with the same account on device B → B pulls the adopted data; making
      a change on B and returning to A converges (no dupes).
- [ ] **Account with pre-existing cloud data isn't clobbered:** log into an account that already has
      rows from another device on a device that also has different local data → pull-first merges,
      both sets survive by id (LWW on any true collisions).
- [ ] **Shared-device reset:** on one device, sign in as A (see A's data), sign out, sign in as B →
      B does **not** see A's data; boxes were cleared and B's own cloud data pulled.
- [ ] **Known accepted edge (document, don't fix):** the *same logical* record created offline on
      two devices *before* login gets different ids → two rows after both adopt. De-dup is out of
      scope; surface it in UI copy ("your on-device data will be merged into your account").
- [ ] `flutter analyze` clean.

## Suggested commit

```
feat(phase-4): one-time per-user data adoption + shared-device reset
```
