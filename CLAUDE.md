# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

The import above holds the commands, code style, colour/radius rules, the
release procedure, and where project context lives. This file adds the parts of
the architecture that you only see by reading several files together.

## Startup and gating

`main.dart` runs `HiveService.init()` and `SupabaseService.init()` in parallel,
then runs `AdoptLocalData.prepareLocal()`. That step is offline-only: it hands
the on-device cache over to the current user and keeps one account's cache
hidden from the next user on a shared device. After startup, the widget tree is
`IntroScreen` (first run only) or `AuthGate` → `AppShell` (an `IndexedStack`
of Home, History, Stats, and Settings).

- `MaterialApp.builder` wraps the Navigator in `AuthGate`, so recovery and
  login UI can sit above pushed routes. When the account changes, `MyApp`
  replaces the navigator key, which throws away the previous user's route
  stack.
- Supabase config comes from `--dart-define` (`SUPABASE_URL`,
  `SUPABASE_ANON_KEY`). The checked-in defaults are a deliberate *publishable*
  key, and RLS is the security boundary, so don't blank or "fix" them. An empty
  override produces an offline-only build that skips auth entirely
  (`SupabaseService.isConfigured`).
- `--dart-define=OPENGYM_PREVIEW_UPDATE=true` forces the self-update dialog so
  you can preview it in debug mode on any platform. It uses sample release
  notes without GitHub requests or an APK download; Update now does nothing.
  Settings → Check for updates reopens it after Later. Stop and rerun the app
  when changing the define. Release builds ignore the flag.

## Data flow

Screens → Providers → `HiveService` (local source of truth) ↔ `SyncService` ↔
Supabase Postgres. Only `SplitProvider` goes through a repository
(`SplitRepository`). The plan and session providers call `HiveService`
directly.

- **Splits scope everything.** `SplitProvider` owns the active split.
  `WorkoutPlanProvider` and `WorkoutSessionProvider` take it in their
  constructors and reload split-scoped views when the active split changes.
  Plans, sessions, history, stats, PRs, and progression lookups are always
  filtered by `splitId`, so any new query has to be split-aware too.
- **Sync metadata lives on every synced model**: `id`, `userId`,
  `updatedAt`, `deletedAt` (a tombstone, never a hard delete), and `dirty`.
  A mutation marks the record dirty and schedules a debounced sync. UI reads
  hide tombstones, while raw reads include them so sync can push deletes.
- **`SyncService`** is a last-write-wins singleton. Parents are pushed before
  children (splits → plans/sessions), and deleted splits are pushed last
  because a server trigger tombstones their descendants. It keeps a pull cursor
  per table in SharedPreferences. Concurrent `syncNow()` calls share one
  in-flight future, errors are swallowed and retried on the next trigger, and
  app resume triggers a sync.
- Settings live in SharedPreferences (`SettingsProvider`), not Hive.
  `BackupService` exports and imports versioned JSON (currently v3, which
  includes splits). Older backups import into a single `My Split`.
- After changing a Hive model's fields, update `toJson`/`fromJson`, the sync
  row mapping, and the backup format together. Then regenerate the adapters.

## Tests

- `test/support/hive_test_harness.dart` opens real Hive boxes in a temp dir and
  registers adapters. Use `open(includeSplits: true)` for split-aware code.
- `pumpWithStorage(tester)` replaces `pumpAndSettle` whenever Hive I/O is
  involved. Widget tests use fake time, so `pumpAndSettle` can't drain real
  filesystem futures.
- `loadTestFonts()` loads deterministic local fonts and turns off google_fonts
  network fetching. Use it in widget tests that render text. A pure `test()` can't call `buildTheme`, so use `deriveColorScheme`
  for colour assertions.
- CI (`.github/workflows/release.yml`) runs `flutter test` before it builds a
  release, so a failing test blocks publishing.
