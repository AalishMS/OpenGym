# PROGRESS — online support migration

> **Resuming in a new session? Read this file first, then [README.md](README.md).**
> The phase files are the **spec**. This file is the **state**. If they disagree, this file wins.

- **Branch:** `feature/online-support`
- **Last updated:** 2026-08-22

---

## Current state

All app code for every phase is written and locally verified. What remains is console work: one
column type to widen in Postgres, then end-to-end sync verification, then hosting. Nothing left is
big — each unticked box below is minutes, not hours.

**The migration is still an uncommitted working tree.** Committing it is the first checklist item
below and is the one thing that isn't yours.

## NEXT ACTION

Two independent things — one yours, one Claude's. Neither blocks the other.

**Yours.** Run this in the **Supabase SQL editor** (DDL needs the SQL editor — the publishable key
cannot `ALTER`):

```sql
alter table public.workout_plans alter column plan_color type bigint;
```

Confirm it took:

```sql
select data_type from information_schema.columns
 where table_name = 'workout_plans' and column_name = 'plan_color';
-- must return: bigint
```

Then tick the first two boxes under **Phase 2** below and re-test a sync push.

**Claude's.** Finish the two-commit split under *Save the work in git* below — the migration is still
uncommitted.

---

## Environment facts

Things that cost time to rediscover:

- **Connection details** (project URL + publishable key) live in `.claude/launch.json` — gitignored,
  never committed. Open that file to see which Supabase project this is. It defines one launch
  config, `opengym-web`, which runs the app on `localhost:8080` via
  `flutter run -d web-server` with the two `--dart-define`s.
- **`supabase_flutter` resolved to 2.16.0**, where `Supabase.initialize` takes **`publishableKey:`** —
  `anonKey:` is deprecated. The dart-define is still *named* `SUPABASE_ANON_KEY` for continuity;
  `supabase_service.dart` passes it to `publishableKey:`. Don't "fix" this back.
- **Email autoconfirm is ON** in Supabase Auth, so sign-up logs straight in with no email link. One
  test user already exists.
- **Toolchain:** Flutter 3.44.1 / Dart 3.12.1. Re-run
  `dart run build_runner build --delete-conflicting-outputs` after any model change.
- **Landmarks:** `AppShell` is at `lib/app_shell.dart`; `MyApp` is already a `StatefulWidget` (the
  lifecycle-resume sync hook is wired into it).
- **Baseline for `flutter analyze`:** 0 errors, 18 warnings — all 18 pre-existing, unrelated to this
  migration. "Clean" means 0 errors and no *new* warnings.

---

## Phase status

| Phase | Scope | Code | Backend | Verified |
|------:|-------|:----:|:-------:|:--------:|
| 0 | ids + sync metadata, id-based CRUD, append + wrong-record bug fixes | done | n/a | analyze + tests |
| 1 | `supabase_service`, `auth/auth_gate`, `login_screen`, main init, sign-out tile | done | project created | live signup + login |
| 2 | Postgres tables, `server_seq` trigger, 8 RLS policies | n/a | ran, **1 column wrong** | pending |
| 3 | `sync_service` LWW push/pull/tombstones, triggers, Hive raw accessors | done | — | blocked by Phase 2 |
| 4 | `adopt_local_data` + `_PostLoginGate` | done | — | not started |
| 5 | web placeholders (`gymapp` → OpenGym) | done | not hosted | build web OK |

---

## Remaining checklist

Each item is owned by **[you]** (console / device work) or **[claude]** (code). Everything left is
currently yours. Tick as you go — a single ticked box is a clean place to stop.

### Save the work in git — do this first

Nothing is committed yet: ~680 insertions across 26 modified files plus 6 untracked files exist only
in the working tree. This was prepared on 2026-08-22 but not finished — `git` became unavailable
partway through, and the tree was restored to its verified state rather than left half-staged.

The split is Phase 0 separately from Phases 1–5, so the risky local Hive re-key can be reverted on
its own. `git add -p` is interactive and unavailable in this environment, so partial staging is done
by **temporarily removing the Phase-1/3 wiring, committing Phase 0, then restoring it.** The four
places to remove (all small and contiguous):

| File | What to remove |
|------|----------------|
| `lib/services/hive_service.dart` | the `// RAW accessors for the sync engine` block — 8 methods, `getAllPlansRaw` → `clearSessionDirty` |
| `lib/providers/workout_plan_provider.dart` | the `sync_service.dart` import + 3 `scheduleSync()` calls |
| `lib/providers/workout_session_provider.dart` | the `sync_service.dart` import + 3 `scheduleSync()` calls |
| `pubspec.yaml` | the `supabase_flutter` line (keep `uuid` — that's Phase 0) |

- [ ] **[claude]** **Commit 1 — Phase 0.** Stage `lib/models/`, `lib/repositories/`,
      `lib/providers/`, `lib/services/hive_service.dart`, `lib/services/backup_service.dart`, the
      four screens (`home`, `edit_plan`, `history`, `workout`), `pubspec.yaml`, `pubspec.lock`, and
      `online-support-plan/`. **Guard:** `git diff --cached -- lib pubspec.yaml` must not contain
      `SyncService`, `scheduleSync`, `Supabase`, or `supabase_flutter`. Message:
      `feat(phase-0): stable ids + sync metadata, id-based CRUD, fix append/wrong-record bugs`
- [ ] **[claude]** **Commit 2 — Phases 1–5.** Restore the four removals, then commit them with
      `lib/services/supabase_service.dart`, `lib/auth/`, `lib/screens/login_screen.dart`,
      `lib/services/sync_service.dart`, `lib/services/adopt_local_data.dart`, `lib/main.dart`,
      `lib/screens/settings_screen.dart`, `web/index.html`, `web/manifest.json`, `.gitignore`, and
      the generated plugin registrants. Message:
      `feat(phases-1-5): supabase auth, LWW cloud sync, data adoption, web config`
- [ ] **[claude]** `flutter analyze` after the restore — back to 0 errors / 18 pre-existing warnings
- [ ] Don't push. `.claude/launch.json` and `.claude/settings.local.json` stay gitignored.

**A ready-to-run script already exists:** `.dart_tool/opengym-split.sh`. It does both commits, strips
and restores the wiring with a `trap` so a mid-way failure can't leave the tree broken, asserts every
string edit, and refuses to run unless `HEAD` is still `b2d109c` — so it is safe to retry but will
never run twice. Run it with:

```bash
tr -d '\r' < .dart_tool/opengym-split.sh > .dart_tool/s.sh && bash .dart_tool/s.sh
```

Caveat: `.dart_tool/` is gitignored and `flutter clean` deletes it. If the script is gone, the table
and two bullets above are enough to recreate it.

### Phase 2 — schema fix

- [ ] **[you]** Run the `plan_color` → `bigint` ALTER (see NEXT ACTION)
- [ ] **[you]** Confirm `information_schema.columns` reports `bigint`

### Phase 3 — sync, runtime verification

Two clients: the `:8080` web-server harness plus a device or a second browser profile.

- [ ] **[you]** **Push** — create a plan → row appears in `workout_plans` with the right `user_id`
- [ ] **[you]** **Pull** — second client, same account, foreground → the plan shows up
- [ ] **[you]** **LWW** — edit the same plan on both within a few seconds → both converge on the
      later `updatedAt`
- [ ] **[you]** **Offline drain** — go offline, edit (record goes `dirty`), reconnect, foreground →
      the edit reaches Postgres and the other client
- [ ] **[you]** **Tombstone** — delete a session on A → after B syncs it's gone from B's History
- [ ] **[you]** **RLS isolation** — second account cannot see the first account's rows
- [ ] **[you]** **No duplicate sessions** — autosave one workout repeatedly → exactly one local row
      and one Postgres row (this is the Phase 0 append-bug fix holding through sync)

### Phase 4 — adoption, runtime verification

- [ ] **[you]** **Adoption** — create data while logged out, then log in → same data present, rows
      land in Postgres under your `user_id`
- [ ] **[you]** **No duplication on re-login** — sign out, sign back in → no duplicate rows
- [ ] **[you]** **Pre-existing cloud data isn't clobbered** — log into an account that already has
      rows from another device, on a device holding different local data → both sets survive
- [ ] **[you]** **Shared-device reset** — sign in as A, sign out, sign in as B → B does not see A's
      data

### Phase 5 — hosting

- [ ] **[you]** `flutter build web --release` with both `--dart-define`s
- [ ] **[you]** Deploy `build/web` to Netlify or Cloudflare Pages
- [ ] **[you]** Add the SPA redirect — `build/web/_redirects` containing `/*    /index.html   200`
- [ ] **[you]** Supabase Auth → URL Configuration: Site URL + Redirect URLs (deployed origin and
      `http://localhost:8080/**`)
- [ ] **[you]** Deployed site: signup/login works, syncs with the local build, hard refresh on a
      non-root path still loads, offline reload still shows cached data
- [ ] **[you]** Tab title reads **OpenGym**, not `gymapp`

---

## Known issues, trade-offs, and follow-ups

Found during implementation and a full verification sweep. None block the checklist above.

**Fixed, don't regress:**

- **`plan_color` must be `bigint`.** A Flutter ARGB `Color` is a uint32 (e.g. `4294688548`), which
  overflows Postgres `int4` (max `2147483647`) → `PostgrestException 22003, out of range for type
  integer`. The client sends `planColor` raw (`sync_service.dart:75`), which is correct *provided*
  the column is `bigint`. The phase-2 doc is corrected; the live database needs the ALTER.

**Accepted trade-offs (by design, documented in the phase files):**

- Same logical record created offline on **two** devices *before* login gets two different UUIDs →
  two rows after both adopt. De-duplication is out of scope.
- `getPlans()` / `getSessions()` do **not** filter by `userId`. Shared-device correctness rests
  entirely on `AdoptLocalData` clearing both boxes when `lastUserId` changes — a single point of
  failure, which is why the shared-device check above matters.

**Real gaps worth fixing later (not yet done):**

- **Hard-clear paths bypass sync entirely.** `SampleDataSeeder.clearAllData()` — reached from
  "CLEAR ALL DATA" (`settings_screen.dart:912`) and "LOAD SAMPLE DATA" (`:573`) — calls
  `HiveService.clearAllPlans/clearAllSessions`, a hard box clear that writes **no tombstones** and
  fires **no sync**. The cloud rows survive but are never re-pulled, because the pull cursor is
  already past them. Local and cloud diverge silently. Fix would be to soft-delete instead of
  clearing, or to reset the pull cursors so the cloud state is re-fetched.
- **Three mutation paths never call `scheduleSync()`** — they only set `dirty`, so they sync late (on
  the next provider mutation or app resume) rather than within ~2s: import restore
  (`settings_screen.dart:800-803`), `renameSessionWeek` (`workout_screen.dart:450`), and
  `deleteSessionForPlanAndWeek` (`workout_screen.dart:474`). Low severity — nothing is lost, it's
  just delayed.
- **`.claude/settings.local.json` holds a copy of the publishable key** but is ignored only by the
  global gitignore, so a fresh clone on another machine wouldn't be protected. Now also listed in the
  repo `.gitignore`.

---

## How to work on this

1. **Start:** read this file. Do the one item under **NEXT ACTION**.
2. **Finish an item:** tick its box, and move NEXT ACTION on to the following item.
3. **End of session:** append one line to the Session log, then commit. `docs: update migration
   progress` on its own is fine.

A phase is not the unit of work — a checkbox is. Stopping after one tick is a clean stop.

---

## Session log

- **2026-08-21** — Wrote the `online-support-plan/` spec (README + 6 phase files). Implemented
  Phase 0: ids + sync metadata on both models, regenerated adapters, id-keyed Hive with tombstones
  and the one-shot re-key migration, id-based repositories/providers/screens, backup format v2 with
  v1 import.
- **2026-08-22** — Implemented Phase 1 (supabase_service, auth_gate, login_screen, main init,
  sign-out tile), Phase 3 (Hive raw accessors, sync_service, triggers), Phase 4 (adopt_local_data +
  `_PostLoginGate`), Phase 5 code (web placeholders). `flutter analyze` 0 errors, `flutter test`
  green, `flutter build web --release` succeeds. Created the Supabase project and ran the Phase 2
  SQL; live signup and login verified. First sync push failed on `plan_color` int4 overflow → phase-2
  doc corrected to `bigint`, live ALTER still pending. Full verification sweep of all phases found no
  stubs or dangling call-sites. Added this progress ledger, plus `.claude/settings.local.json` to the
  repo `.gitignore`. The two-commit split was prepared but **not** completed — `git` became
  unavailable partway through (sandbox classifier down); the working tree was restored to its
  verified state and nothing was committed.
