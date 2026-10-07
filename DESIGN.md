# OpenGym Design

## Purpose

OpenGym is an offline-first workout tracking app. It lets users create workout
plans, log sets, reps, weights, RPE, and notes, review workout history, track
personal records, and sync data across devices when signed in.

The app favors fast local use in the gym over server-first workflows. Local Hive
storage is the primary runtime data source; Supabase is used for account-based
backup and cross-device sync.

OpenGym is made for anyone who wants a dependable record of their training. It
should feel clear on first use and efficient on the hundredth workout. The app's
identity comes from its measured use of color, compact training data, and a few
recognizable details rather than a theme that users need to understand. The
`> OpenGym` wordmark remains a deliberate link to the app's original character.

## Product Principles

- Offline use must remain reliable.
- Logging a workout should require minimal navigation and minimal typing.
- Data ownership stays local first, with explicit export/import support.
- A new user should understand the main actions without learning a visual motif.
- Training information should lead; decoration should stay quiet.
- Color and small signature details should add character without competing with
  the workout.
- Sync must be resilient: failed network work should retry later, not block local
  training logs.

## Technology Stack

| Area | Choice |
| --- | --- |
| App framework | Flutter |
| Language | Dart |
| State management | Provider with `ChangeNotifier` |
| Local storage | Hive |
| Settings storage | SharedPreferences |
| Charts | Flutter canvas and custom chart widgets |
| Auth and cloud sync | Supabase |
| Typography | Readable app typography via `google_fonts` |

## Runtime Architecture

```text
main.dart
  -> HiveService.init() + SupabaseService.init()   (in parallel)
  -> AdoptLocalData.prepareLocal()                 (offline-only cache handover)
  -> MultiProvider
  -> IntroScreen (first run) or AuthGate
  -> AppShell
  -> Home / History / Stats / Settings
```

`AuthGate` wraps the app Navigator through `MaterialApp.builder`, so login and
password-recovery UI can appear above pushed routes. When the signed-in account
changes, the navigator key is replaced so the previous user's route stack is
discarded. `AdoptLocalData` adopts on-device data into an account the first
time that user signs in, and keeps one account's cache hidden from the next
user on a shared device.

The app is split into small layers:

| Layer | Location | Responsibility |
| --- | --- | --- |
| Models | `lib/models/` | Hive objects and JSON serialization |
| Providers | `lib/providers/` | UI-facing state and `notifyListeners()` |
| Repositories | `lib/repositories/` | Thin data-access wrappers around services (currently splits only) |
| Services | `lib/services/` | Storage, sync, backup, PR tracking, seeding |
| Screens | `lib/screens/` | Page-level UI |
| Widgets | `lib/widgets/` | Reusable UI components |
| Theme | `lib/theme/` | Colors, typography, spacing, breakpoints, corner radii, theme helpers |

## State Management

Provider is the only app-wide state pattern.

| Provider | State |
| --- | --- |
| `SplitProvider` | Available splits, the active split, split CRUD and preset installs |
| `WorkoutPlanProvider` | Workout plan list and plan CRUD for the active split |
| `WorkoutSessionProvider` | Session list, current week, session mutations for the active split |
| `SettingsProvider` | Theme mode, accent color, units, auto-fill |
| `UpdateProvider` | Self-update check against GitHub Releases |

Providers mutate data through `HiveService` (`SplitProvider` goes through
`SplitRepository`), reload local state, notify listeners, and schedule sync
where needed. The plan and session providers take
`SplitProvider` in their constructors and reload when the active split changes.
See [docs/splits.md](docs/splits.md).

On Android, the activity requests the display's highest supported refresh rate
whenever it resumes, without changing the display resolution. This is automatic
and has no user setting; Android display settings and power-saving policies can
limit the actual rate. Legacy refresh-rate preferences in storage or backups are
ignored.

## Data Model

The core model is intentionally small.

| Model | Purpose |
| --- | --- |
| `Set` | One performed set: reps, weight, optional RPE, optional note |
| `Exercise` | One logged exercise with a list of sets |
| `SetTemplate` | One target set in a plan: reps and weight (display-only) |
| `ExerciseTemplate` | Exercise entry with targets and optional workout guidance |
| `WorkoutPlan` | Named plan with exercises, optional color, explicit order, and `splitId` |
| `WorkoutSession` | Logged workout for a plan, date, week, exercises, and `splitId` |
| `Split` | An independent training workspace that owns plans and sessions |
| `SplitPreference` | The account's active split, keyed by user ID |

Splits, plans, and sessions also carry sync metadata. `SplitPreference` keeps
only `updatedAt` and `dirty`: it is keyed by `userId` and is never deleted.

| Field | Purpose |
| --- | --- |
| `id` | Stable local and remote record identity |
| `userId` | Supabase owner when synced |
| `updatedAt` | Last local or remote write timestamp |
| `deletedAt` | Tombstone for soft deletes |
| `dirty` | Marks local changes that still need to be pushed |

Hive adapters are generated in `*.g.dart`; those files are not edited by hand.

## Local Persistence

`HiveService` owns local persistence. It opens four boxes:

| Box | Records |
| --- | --- |
| `workout_plans` | `WorkoutPlan` |
| `workout_sessions` | `WorkoutSession` |
| `splits` | `Split` |
| `split_preferences` | `SplitPreference` |

UI-facing reads hide tombstoned records. Raw reads include tombstones so sync can
push deletes.

`HiveService` also runs one-shot migrations. The first re-keys records from old
integer Hive keys to stable IDs, after writing a JSON safety backup to
SharedPreferences. The second, `ensureSplitWorkspace`, creates a default split
when none exists and assigns any plan or session without a `splitId` to the
active split.

## Cloud Sync

`SyncService` implements a small last-write-wins sync loop between Hive and
Supabase Postgres.

```text
local mutation
  -> mark record dirty
  -> debounce sync
  -> pull splits + split preference   (best effort; may fail offline)
  -> ensure a local split workspace exists
  -> push live splits
  -> push dirty plans
  -> push dirty sessions
  -> push split preference
  -> push deleted splits
  -> pull splits, split preference, plans, sessions
```

Parents are pushed before children. Deleted splits are pushed last because a
server trigger tombstones their plans and sessions, and every child mutation
has to land first. Each table keeps its own pull cursor in SharedPreferences.

Sync uses whole aggregate rows: one plan or one session is stored as promoted
columns plus a JSON `data` payload. Deletes are represented by `deletedAt`, not
hard deletion.

Conflict resolution is timestamp based:

- Remote wins when the remote `updatedAt` is newer than or equal to local.
- Local wins when the local `updatedAt` is newer; the dirty push carries it to
  the server later.
- Sync errors are swallowed and retried on the next trigger.
- Concurrent sync calls share the same active future.
- Sync runs after local mutations and whenever the app returns to the
  foreground.

Supabase auth gates the app when online support is configured. The Supabase URL
and publishable key are compiled in as `--dart-define` defaults
(`SUPABASE_URL`, `SUPABASE_ANON_KEY`), and row-level security is the security
boundary. A build that overrides either one with an empty value is
offline-only: it skips auth and opens the app shell directly.

## Navigation

`AppShell` owns the main tab layout using an `IndexedStack` so tabs preserve
their state.

| Tab | Screen |
| --- | --- |
| Home | `HomeScreen` |
| History | `HistoryScreen` |
| Stats | `StatsScreen` |
| Settings | `SettingsScreen` |

Workout plan creation, editing, and active workout logging are separate screens
opened from the main flow.

## Bundled Workout Presets

The app compiles a read-only catalog of workout programs from the reviewed
preset research. Catalog metadata is never written to Hive or Supabase. Choosing
a program copies its workout days into ordinary user-owned plans, with explicit
positions so their schedule order survives synchronization. Installation is an
exclusive local mutation with compensating rollback across split, plan, and
active-preference boxes.

The Home split menu opens a responsive program browser. Its colored schedule
strip represents workout/rest rhythm using the existing solved plan colors;
details expose complete prescriptions, RIR, rest, substitutions, and shared
guidance before the user creates a copy.

## UI Design

OpenGym uses a clean, practical visual language with a restrained personal
signature:

- Clear type hierarchy keeps workout names, values, units, and supporting text
  distinct at a glance.
- Calm backgrounds and surfaces give dense training data room to breathe.
- Rounded corners follow a size-graduated scale, with borders and elevation used
  only when they clarify grouping.
- Dark and light themes share the same semantic color helpers.
- User-selectable accents, compact plan markers, and focused data highlights
  carry the app's character.
- The `> OpenGym` wordmark serves as the main brand signature. Keep it consistent
  and give it room instead of repeating the prompt symbol elsewhere.
- Familiar labels and icons make actions understandable outside a technical
  audience.
- Pressed, focused, disabled, loading, empty, and error states should feel like
  parts of the same system.

Broad monospaced typography, square-bracket labels, and all-uppercase copy are
not part of the product identity. A monospaced face may still serve a specific
data-alignment need. The `>` symbol is reserved for the OpenGym wordmark rather
than used as a general interface decoration.

UI code should use theme helpers from `lib/theme/app_theme.dart` instead of
hardcoded black or white colors, and corner radii from `lib/theme/radii.dart`
instead of literal `BorderRadius` values. Radii are graduated by element size:
cards and dialogs are the roundest, while badges use a smaller radius, so the
same roundness reads correctly on a 148px card and a 20px badge. Retuning the
whole app means editing the six scale constants in that one file.

## Backup And Import

`BackupService` exports all splits, plans, sessions, and settings into a
versioned JSON file (currently version 3). Imports validate JSON shape and
supported versions before replacing local data.

Version 1 backups without stable IDs are upgraded on import by assigning IDs and
marking records dirty so they can sync upward. Backups older than version 3
import into a single `My Split`.

## Development Constraints

- Keep Provider as the app-wide state pattern.
- Keep Hive as the local source of truth.
- Run `flutter analyze` after changes.
- Run build runner after editing Hive model fields or type adapters.
- Do not edit generated `*.g.dart` files manually.
- Prefer theme-aware colors from `app_theme.dart`.
- Keep repositories thin unless there is a concrete need for more logic.

## Non-Goals

- Real-time collaborative editing.
- Server-first workout logging.
- Complex conflict merging inside individual exercises or sets.
- A custom design system beyond the existing theme and its colour, spacing,
  breakpoint, and radius tokens.
