# OpenGym — Online Support (Hosting + Auth + Multi-Device Cloud Sync)

This folder is a **step-by-step execution plan**. It turns the "100% offline" OpenGym
(Flutter + Hive) into an **offline-first app with accounts and cloud sync** via **Supabase**,
without losing offline use. It is written so it can be executed **one phase at a time, in order**,
with copy-paste code and exact find/replace edits.

> **Read this whole README once before touching code.** It defines conventions every phase file
> relies on (secrets, verification, rollback). Then do the phases in order.

> **Picking up work already in progress?** Start with **[PROGRESS.md](PROGRESS.md)** — it holds the
> current state, the single next action, and the remaining checklist. This README and the phase files
> are the spec; PROGRESS.md is the state.

---

## What we are building (one paragraph)

Hive stays the **local source of truth**. Every plan/session gets a stable **UUID** + sync
metadata (`updatedAt`, `deletedAt`, `dirty`, `userId`). A small hand-rolled **last-write-wins
(LWW)** sync layer mirrors each record to Postgres as a **JSONB aggregate** (reusing the app's
existing `toJson`/`fromJson`), guarded by **Row-Level Security** so each account sees only its
own data. Writes stay instant and local; a background cycle reconciles with the cloud when online.

## The two problems being fixed

1. **No stable identity.** Today records are addressed by **list index** or matched by **name
   string**; sessions are written **append-only**. Sync needs stable ids, owners, and timestamps.
2. **A real bug fixed along the way.** `HiveService.getSessions()` returns a **date-sorted** copy,
   but `deleteSession(int)`/`updateSession(int)` use `deleteAt`/`putAt` on **insertion order**, and
   History passes the *sorted* index — so editing/deleting a workout from History can hit the
   **wrong record**. Moving to id-based CRUD (Phase 0) removes this entire bug class.

---

## Phase order (do NOT skip or reorder)

| Phase | File | What it does | Backend? | Ships alone? |
|------:|------|--------------|:--------:|:------------:|
| 0 | [phase-0-identity-groundwork.md](phase-0-identity-groundwork.md) | Add UUID + sync metadata; convert index→id CRUD; fix append/wrong-record bugs | No | ✅ (behaves identically offline) |
| 1 | [phase-1-supabase-auth.md](phase-1-supabase-auth.md) | Add Supabase + `uuid`; init; login screen + auth gate; sign-out | Yes | ✅ (auth only) |
| 2 | [phase-2-postgres-schema-rls.md](phase-2-postgres-schema-rls.md) | Postgres tables, indexes, `server_seq` trigger, RLS policies | Yes (SQL only) | ✅ |
| 3 | [phase-3-sync-engine.md](phase-3-sync-engine.md) | `SyncService`: push dirty, pull by cursor, LWW merge, triggers | Yes | ✅ |
| 4 | [phase-4-first-login-adoption.md](phase-4-first-login-adoption.md) | Adopt existing on-device data into the account once, idempotently | Yes | ✅ |
| 5 | [phase-5-web-hosting.md](phase-5-web-hosting.md) | Web build, fix placeholders, host on Netlify/Cloudflare, Supabase URL config | Yes | ✅ |

**Phase 0 is the foundation and the riskiest** (it re-keys the local database). Land it, verify it
hard, and commit before starting Phase 1. Phases 1–5 are mostly **additive** (new files + small
wiring), so they are lower risk.

---

## Conventions used by every phase file

- **Exact edits.** "REPLACE" blocks give the *exact current text* to find (copied verbatim from the
  repo at planning time) and the exact replacement. If the "find" text does not match, STOP and
  re-read the file — do not guess. Line numbers are hints; match on text.
- **Full files.** For files that change substantially (models, `hive_service.dart`, repositories,
  providers, `backup_service.dart`), the phase file gives the **complete new file** — overwrite the
  whole file with it.
- **New files** are given in full with their target path.
- **After any model change**, regenerate Hive adapters (Phase 0 explains):
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```
- **Verify before commit.** Each phase ends with a concrete verification checklist and a suggested
  commit message. Run `flutter analyze` (must be clean) and the relevant manual checks before
  committing. Do not `git commit`/`git push` unless the human asks.

## Non-negotiable data-safety rules (Hive)

These make the identity migration safe and keep old data readable:

1. **All new model fields are nullable** (`String?`, `DateTime?`, `bool?`). Hive's generated
   `read()` returns `null` for a field index that is absent on an old on-disk record; a
   **non-nullable** field would throw (`null as String`) and make old records unreadable.
2. **Never renumber existing `@HiveField` indices and never change `typeId`s.** Only *append* new
   field numbers. (Plan keeps `id=4, userId=5, updatedAt=6, deletedAt=7, dirty=8`; Session keeps
   `id=4, userId=5, planId=6, updatedAt=7, deletedAt=8, dirty=9`. Plan's field `3` is intentionally
   left unused — that gap is harmless.)
3. **New metadata fields are non-`final`** so the sync engine can flip `dirty`/`updatedAt`/
   `deletedAt` in place and persist with `.save()`/`box.put(id, obj)`.
4. **Nested types are untouched** (`Set` t0, `Exercise` t1, `ExerciseTemplate` t2). They travel
   inside JSONB and need no identity.

## Secrets & keys (read before Phases 1–5)

- Supabase gives you a project **URL**, an **anon key**, and a **service_role key**.
- The **anon key is safe to ship** in the client — **RLS** is what protects data.
- **NEVER ship or hardcode the `service_role` key** anywhere in the app or repo. It bypasses RLS.
- Pass URL + anon key at build time via `--dart-define` (see Phases 1 and 5), never committed:
  ```bash
  flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  ```
- RLS gates every table on `auth.uid() = user_id`. Every pushed row **must** carry the correct
  `user_id` or the insert is rejected (defensive checks are built into Phase 3).

## Rollback strategy (global)

- Work on a branch: `git switch -c feature/online-support` before Phase 0.
- Commit after each verified phase so any phase can be reverted independently with `git revert`.
- Phase 0's local DB migration writes a **JSON safety backup** into `shared_preferences`
  (`idkey_backup_plans` / `idkey_backup_sessions`) before re-keying — recovery net if it fails.
- The in-app **Export Data** feature (Settings → DATA) is your user-facing backup: export before
  running Phase 0 on a device with real data.

## Critical files (touched across phases)

- `lib/services/hive_service.dart` — persistence seam: index→id, keyed boxes, tombstone filter,
  upsert, re-key migration, raw accessors for sync. *(Phase 0; Phase 3 adds raw accessors.)*
- `lib/models/workout_plan.dart`, `lib/models/workout_session.dart` — id/meta fields + `copyWith`;
  regenerate `.g.dart`. *(Phase 0)*
- `lib/repositories/*`, `lib/providers/*` — id-based signatures; `saveWorkout`→upsert. *(Phase 0)*
- `lib/screens/{home,edit_plan,history,workout}_screen.dart` — id-based call-sites. *(Phase 0)*
- `lib/services/backup_service.dart` — bump to v2, keep v1 import. *(Phase 0)*
- `lib/main.dart` — Supabase init + auth-gate wiring. *(Phase 1)*
- **New:** `lib/services/supabase_service.dart`, `lib/auth/auth_gate.dart`,
  `lib/screens/login_screen.dart` *(Phase 1)*; `lib/services/sync_service.dart` *(Phase 3)*;
  `lib/services/adopt_local_data.dart` *(Phase 4)*.

## Reuse (do NOT rebuild)

- `backup_service.dart` `toJson`/`fromJson` on every model → the exact JSONB payload.
- The Repository seam → where id-based / sync-aware data access swaps in with minimal screen churn.
- Existing name-based analytics (`getExercisePR`, `getExerciseProgression`, `getWorkoutFrequency`,
  progression suggestions) stay client-side and unchanged — JSONB carries the whole tree.
