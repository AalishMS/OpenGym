# PROGRESS — online support migration

> **Resuming in a new session? Read this file first, then [README.md](README.md).**
> The phase files are the **spec**. This file is the **state**. If they disagree, this file wins.

- **Branch:** `feature/online-support`
- **Last updated:** 2026-08-22

---

## Current state

All app code for every phase is written, locally verified, and committed. Phase 2's live `plan_color`
schema fix is done, and Phase 3 sync checks passed against the local web harness plus Supabase REST.
Phase 4 adoption checks passed manually. Phase 5 is deployed to Netlify
(<https://open-gym.netlify.app>) and HTTP-verified; only interactive sign-in/sync/offline checks on
the live site remain.

## NEXT ACTION

**Phase 5 is deployed** at <https://open-gym.netlify.app> and HTTP-verified. Two things remain, both
yours:

1. *(Optional, non-blocking — email autoconfirm is ON)* Supabase → Authentication → URL
   Configuration: set Site URL + Redirect URLs for the deployed origin.
2. Interactive verification on the live site: sign up / sign in, confirm a change syncs with the
   mobile build on the same account, and offline-reload shows cached data.

After that, all five phases are complete.

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
| 2 | Postgres tables, `server_seq` trigger, 8 RLS policies | n/a | done | bigint push + RLS verified |
| 3 | `sync_service` LWW push/pull/tombstones, triggers, Hive raw accessors | done | — | local web + REST verified |
| 4 | `adopt_local_data` + `_PostLoginGate` | done | — | manual pass |
| 5 | placeholders + web build + Netlify deploy + SPA redirect | done | hosted | deployed + HTTP-verified |

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

- [x] **[claude]** **Commit 1 — Phase 0.** Stage `lib/models/`, `lib/repositories/`,
      `lib/providers/`, `lib/services/hive_service.dart`, `lib/services/backup_service.dart`, the
      four screens (`home`, `edit_plan`, `history`, `workout`), `pubspec.yaml`, `pubspec.lock`, and
      `online-support-plan/`. **Guard:** `git diff --cached -- lib pubspec.yaml` must not contain
      `SyncService`, `scheduleSync`, `Supabase`, or `supabase_flutter`. Message:
      `feat(phase-0): stable ids + sync metadata, id-based CRUD, fix append/wrong-record bugs`
- [x] **[claude]** **Commit 2 — Phases 1–5.** Restore the four removals, then commit them with
      `lib/services/supabase_service.dart`, `lib/auth/`, `lib/screens/login_screen.dart`,
      `lib/services/sync_service.dart`, `lib/services/adopt_local_data.dart`, `lib/main.dart`,
      `lib/screens/settings_screen.dart`, `web/index.html`, `web/manifest.json`, `.gitignore`, and
      the generated plugin registrants. Message:
      `feat(phases-1-5): supabase auth, LWW cloud sync, data adoption, web config`
- [x] **[claude]** `flutter analyze` after the restore — back to 0 errors / 18 pre-existing warnings
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

- [x] **[you]** Run the `plan_color` → `bigint` ALTER (see NEXT ACTION)
- [x] **[you]** Confirm `information_schema.columns` reports `bigint`

### Phase 3 — sync, runtime verification

Two clients: the `:8080` web-server harness plus a device or a second browser profile.

- [x] **[you]** **Push** — create a plan → row appears in `workout_plans` with the right `user_id`
- [x] **[you]** **Pull** — second client, same account, foreground → the plan shows up
- [x] **[you]** **LWW** — edit the same plan on both within a few seconds → both converge on the
      later `updatedAt`
- [x] **[you]** **Offline drain** — go offline, edit (record goes `dirty`), reconnect, foreground →
      the edit reaches Postgres and the other client
- [x] **[you]** **Tombstone** — delete a session on A → after B syncs it's gone from B's History
- [x] **[you]** **RLS isolation** — second account cannot see the first account's rows
- [x] **[you]** **No duplicate sessions** — autosave one workout repeatedly → exactly one local row
      and one Postgres row (this is the Phase 0 append-bug fix holding through sync)

### Phase 4 — adoption, runtime verification

- [x] **[you]** **Adoption** — create data while logged out, then log in → same data present, rows
      land in Postgres under your `user_id`
- [x] **[you]** **No duplication on re-login** — sign out, sign back in → no duplicate rows
- [x] **[you]** **Pre-existing cloud data isn't clobbered** — log into an account that already has
      rows from another device, on a device holding different local data → both sets survive
- [x] **[you]** **Shared-device reset** — sign in as A, sign out, sign in as B → B does not see A's
      data

### Phase 5 — hosting

- [x] **[claude]** `flutter build web --release` with both `--dart-define`s — exit 0, `build/web` produced
- [x] **[you]** Deployed `build/web` to Netlify (drag-and-drop) — live at
      <https://open-gym.netlify.app>
- [x] **[claude]** SPA redirect added at `web/_redirects` (source) — Flutter copies it into
      `build/web/_redirects` on every build; confirmed present in the output
- [ ] **[you]** Supabase Auth → URL Configuration: Site URL `https://open-gym.netlify.app` +
      Redirect URLs `https://open-gym.netlify.app/**` and `http://localhost:8080/**` (not blocking —
      email autoconfirm is ON — but good practice)
- [x] **[claude]** Deployed site loads over HTTPS; hard refresh on non-root paths serves the app
      (SPA redirect verified: `/history` + a deep bogus route → 200 `index.html`); Supabase URL +
      publishable key confirmed baked into the shipped `main.dart.js`, no secret key leaked
- [ ] **[you]** Deployed site: **sign up / sign in works**, **syncs with mobile** on the same
      account, **offline reload** still shows cached data (needs a real signed-in session)
- [x] Tab title reads **OpenGym** — confirmed on the deployed `<title>`

---

## Known issues, trade-offs, and follow-ups

Found during implementation and a full verification sweep. None block the checklist above.

**Fixed, don't regress:**

- **Supabase config is baked into `supabase_service.dart` as the `String.fromEnvironment` *defaults***
  (URL + publishable key) so every build path — Android Studio Run/Build menu, `flutter build
  apk/appbundle`, `flutter run`, web, CI — has online support with **no `--dart-define` flags**;
  a `--dart-define`/`--dart-define-from-file` still overrides. The key is a *publishable* key (already
  public in the web bundle), RLS is the guard, and the `sb_secret_`/service_role key is never used.
  **Do not revert this to empty defaults** to satisfy the phase-5 "no Supabase literals in the repo"
  note — that was a deliberate trade made on 2026-08-22 for build convenience.
- **Login is mandatory on every build, by design.** With config always present, logged-out users get
  `LoginScreen` on all platforms — there is deliberately no "continue offline" / guest path (user
  decision, 2026-08-22). Don't add a skip to "restore" offline-first first-run usage.
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
- **2026-08-22** — Completed the planned two-commit split: Phase 0 in `e1dda55`, Phases 1–5 in
   `cbe08cc`. Re-ran `flutter analyze`: 0 errors, 18 pre-existing warnings/infos. Remaining work is
   the Supabase `plan_color` bigint ALTER, runtime sync checks, and hosting.
- **2026-08-22** — Ran the live `plan_color` bigint fix and Phase 3 runtime checks. Verified app push,
  pull, offline drain, bigint color push, LWW, tombstone, RLS isolation, and no duplicate session row.
  Fixed a startup/adoption sync race where concurrent `syncNow()` calls could return before the
  in-flight pull had refreshed providers. `flutter analyze`: 0 errors, 18 pre-existing warnings/infos.
- **2026-08-22** — User manually verified all Phase 4 adoption checks: first-login adoption, no
  duplicate rows on re-login, pre-existing cloud data preserved, and shared-device reset.
- **2026-08-22** — Phase 5 hosting. Added `web/_redirects` (SPA fallback), built `flutter build web
  --release` with the Supabase dart-defines (exit 0); user deployed `build/web` to Netlify via
  drag-and-drop → <https://open-gym.netlify.app>. HTTP-verified: root + `/history` + a deep bogus
  route all 200 serving `index.html` (SPA redirect live), assets served with correct MIME, tab title
  "OpenGym", and the Supabase URL + publishable key are baked into the shipped `main.dart.js` with no
  secret key leaked. Keys-hygiene `git grep` clean. In-app browser preview can't attach to a remote
  URL on this install, so interactive sign-in/sync/offline checks on the live site are left to the
  user, plus the optional Supabase Auth URL config.
- **2026-08-22** — Made online support the default for *every* build: moved the Supabase URL +
  publishable key from empty `String.fromEnvironment` defaults to the real values as defaults in
  `supabase_service.dart`, so Android Studio (Run button and Build → APK menu), `flutter build
  apk/appbundle`, `flutter run`, web, and CI all get auth/sync with no `--dart-define` flags. Removed
  the interim `dart_defines.json` / `.example` scaffolding and its gitignore line. Proof: a
  `flutter build web --release` with NO defines bakes the host + key into `main.dart.js`. `flutter
  analyze` still 0 errors / 18 pre-existing. Deliberate exception to the phase-5 "no literals" note
  (the publishable key is already public via the web deploy).
- **2026-08-22** — Decided (with user) to **require an account on every build**. Since config is now
  always present, `AuthGate` shows `LoginScreen` for logged-out users on all platforms, with no
  offline/guest path — the existing behavior, so no code change. Considered the alternative
  (offline-first + optional login: a "Continue offline" skip plus a Settings sign-in tile) and
  rejected it. Caveat recorded: first launch needs connectivity to sign up / sign in; the app is
  offline-capable only *after* that first sign-in.
