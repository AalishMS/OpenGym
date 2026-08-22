# Phase 3 — Sync engine (push / pull / LWW merge)

**Goal:** a small hand-rolled last-write-wins sync layer. Push local `dirty` records to Supabase,
pull rows changed since the last cursor, and merge by `id` with latest-`updatedAt`-wins. Offline
writes just set `dirty`; the next online cycle drains them.

**Depends on:** Phase 0 (ids + dirty + tombstones), Phase 1 (auth), Phase 2 (tables + RLS).

---

## Step 3.1 — Add raw accessors to `hive_service.dart`

Phase 0 deliberately kept the sync-only accessors out. Add them now. These bypass the
tombstone filter and the `dirty` stamping, because sync needs to see everything and to write pulled
records **without** re-marking them dirty.

Add these methods to `class HiveService` (anywhere among the other static methods):

```dart
  // ---------------------------------------------------------------------------
  // RAW accessors for the sync engine.
  // getAll*Raw: include tombstones (deletedAt != null) — sync must push deletes.
  // put*Raw: write WITHOUT touching dirty/updatedAt — used when applying a
  //          record pulled from the server (it is already authoritative).
  // ---------------------------------------------------------------------------
  static List<WorkoutPlan> getAllPlansRaw() => _plansBox.values.toList();

  static List<WorkoutSession> getAllSessionsRaw() =>
      _sessionsBox.values.toList();

  static List<WorkoutPlan> getDirtyPlans() =>
      _plansBox.values.where((p) => p.dirty == true).toList();

  static List<WorkoutSession> getDirtySessions() =>
      _sessionsBox.values.where((s) => s.dirty == true).toList();

  static Future<void> putPlanRaw(WorkoutPlan plan) async {
    await _plansBox.put(plan.id, plan);
  }

  static Future<void> putSessionRaw(WorkoutSession session) async {
    await _sessionsBox.put(session.id, session);
  }

  /// Clear the dirty flag after a successful push, without bumping updatedAt.
  static Future<void> clearPlanDirty(String id) async {
    final p = _plansBox.get(id);
    if (p == null) return;
    p.dirty = false;
    await _plansBox.put(id, p);
  }

  static Future<void> clearSessionDirty(String id) async {
    final s = _sessionsBox.get(id);
    if (s == null) return;
    s.dirty = false;
    await _sessionsBox.put(id, s);
  }
```

---

## Step 3.2 — New file `lib/services/sync_service.dart`

The whole engine. Read the inline comments — they explain the LWW rules.

```dart
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
      if (serverSeq != null && (maxSeq == null || serverSeq.compareTo(maxSeq) > 0)) {
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
      if (serverSeq != null && (maxSeq == null || serverSeq.compareTo(maxSeq) > 0)) {
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
```

> **Tombstone semantics fall out for free:** a delete is just a row with `deletedAt` set and a newer
> `updatedAt`. On pull, `_remoteWins` compares timestamps like any edit — an edit newer than a
> delete resurrects the record; a delete newer than an edit keeps it deleted. `putPlanRaw` writes
> the tombstone locally, and `getPlans()`/`getSessions()` (Phase 0) hide `deletedAt != null`, so the
> UI drops it. No special-casing needed.

> **Why pulled records are reconstructed from `data` then column-overridden:** `data` carries the
> full exercise/set tree (the app's own `fromJson`), while the promoted columns are the
> authoritative id/owner/timestamps. Reconstruct the tree, then trust the columns for identity.

---

## Step 3.3 — Trigger the sync (login, resume, after mutations)

**A — on login/resume.** In `lib/main.dart`, make `MyApp` a `StatefulWidget` with
`WidgetsBindingObserver` (if it isn't already) so we can sync on resume. Minimal wiring:

```dart
// in _MyAppState:
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  SyncService.instance.syncNow(); // initial cycle if already logged in
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    SyncService.instance.syncNow();
  }
}
```

Add `with WidgetsBindingObserver` to the state class and
`import 'services/sync_service.dart';`.

> If `MyApp` is currently a `StatelessWidget`, the smallest change is to convert it to a
> `StatefulWidget` keeping the exact same `build` body. Don't restructure the `MultiProvider` /
> `Consumer<SettingsProvider>` / `MaterialApp` tree — only move it into `State.build`.

**B — on auth change.** In `lib/auth/auth_gate.dart`, when a session becomes non-null, kick a sync.
Simplest: in the `session != null` branch, call it before returning `AppShell`:

```dart
        if (session != null) {
          // Fire and forget; guarded internally against re-entrancy.
          SyncService.instance.syncNow();
          return const AppShell();
        }
```

Add `import '../services/sync_service.dart';` to `auth_gate.dart`.

> Phase 4 will replace this bare `syncNow()` with `adoptLocalDataIfNeeded()` (which itself does a
> pull-then-push). For now, `syncNow()` is the placeholder.

**C — after each mutation (debounced).** In the two providers, call
`SyncService.instance.scheduleSync()` after a successful local write. Add
`import '../services/sync_service.dart';` to each provider.

In `workout_plan_provider.dart`, at the end of `addPlan`, `updatePlan`, `deletePlan` (after
`loadPlans()`):

```dart
    SyncService.instance.scheduleSync();
```

In `workout_session_provider.dart`, at the end of `upsertSession`, `updateSession`, `deleteSession`
(after `loadSessions()`):

```dart
    SyncService.instance.scheduleSync();
```

> `scheduleSync` no-ops when logged out or unconfigured, so this is safe in offline builds — the
> record just stays `dirty` until a future login drains it.

---

## Step 3.4 — Analyze & run

```bash
flutter analyze
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

---

## Verification checklist (two devices, or device + `flutter run -d chrome`)

Use two accounts for isolation, one account on two clients for convergence.

- [ ] **Push:** sign in on device A, create a plan. Within a few seconds the row appears in Supabase
      (Table editor → `workout_plans`) with the correct `user_id`, `data`, and `server_seq`.
- [ ] **Pull:** on device B (same account), foreground the app → the plan created on A appears.
- [ ] **LWW:** edit the same plan on A and B close together; after both sync, both converge to the
      later `updatedAt`.
- [ ] **Offline drain:** put A in airplane mode, edit a plan (it goes `dirty`), re-enable network,
      foreground → the edit reaches Supabase and B.
- [ ] **Delete propagates:** delete a session on A → after B syncs, it disappears from B's History
      (tombstone pulled, hidden by the `deletedAt` filter).
- [ ] **Isolation (RLS):** account B never sees account A's rows in the app or in a
      B-authenticated query. An attempt to push a row with the wrong `user_id` is rejected (the
      defensive stamp prevents this; if you force it, Supabase returns a policy violation).
- [ ] **No duplicate sessions:** autosave a workout repeatedly on A → exactly one session row
      locally AND one row in Supabase (Phase 0 fix holds through sync).
- [ ] `flutter analyze` clean.

## Suggested commit

```
feat(phase-3): LWW sync engine — push dirty, pull by cursor, tombstones
```
