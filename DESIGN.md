# OpenGym Design

## Purpose

OpenGym is an offline-first workout tracking app. It lets users create workout
plans, log sets, reps, weights, RPE, and notes, review workout history, track
personal records, and sync data across devices when signed in.

The app favors fast local use in the gym over server-first workflows. Local Hive
storage is the primary runtime data source; Supabase is used for account-based
backup and cross-device sync.

## Product Principles

- Offline use must remain reliable.
- Logging a workout should require minimal navigation and minimal typing.
- Data ownership stays local first, with explicit export/import support.
- The UI should feel terminal-inspired without sacrificing readability.
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
| Charts | `fl_chart` |
| Auth and cloud sync | Supabase |
| Typography | JetBrains Mono via `google_fonts` |

## Runtime Architecture

```text
main.dart
  -> HiveService.init()
  -> SupabaseService.init()
  -> MultiProvider
  -> AuthGate
  -> AppShell
  -> Home / History / Stats / Settings
```

The app is split into small layers:

| Layer | Location | Responsibility |
| --- | --- | --- |
| Models | `lib/models/` | Hive objects and JSON serialization |
| Providers | `lib/providers/` | UI-facing state and `notifyListeners()` |
| Repositories | `lib/repositories/` | Thin data-access wrappers around services |
| Services | `lib/services/` | Storage, sync, backup, PR tracking, seeding |
| Screens | `lib/screens/` | Page-level UI |
| Widgets | `lib/widgets/` | Reusable UI components |
| Theme | `lib/theme/` | Colors, typography, spacing, breakpoints, corner radii, theme helpers |

## State Management

Provider is the only app-wide state pattern.

| Provider | State |
| --- | --- |
| `WorkoutPlanProvider` | Workout plan list and plan CRUD |
| `WorkoutSessionProvider` | Session list, current week, session mutations |
| `ProgressionProvider` | Last-session based progression suggestions |
| `SettingsProvider` | Theme mode, accent color, units, auto-fill, refresh rate |

Providers mutate data through repositories, reload local state, notify listeners,
and schedule sync where needed.

## Data Model

The core model is intentionally small.

| Model | Purpose |
| --- | --- |
| `Set` | One performed set: reps, weight, optional RPE, optional note |
| `Exercise` | One logged exercise with a list of sets |
| `ExerciseTemplate` | Exercise entry in a plan with target set count |
| `WorkoutPlan` | Named plan with exercises and optional plan color |
| `WorkoutSession` | Logged workout for a plan, date, week, and exercises |

Plans and sessions also carry sync metadata:

| Field | Purpose |
| --- | --- |
| `id` | Stable local and remote record identity |
| `userId` | Supabase owner when synced |
| `updatedAt` | Last local or remote write timestamp |
| `deletedAt` | Tombstone for soft deletes |
| `dirty` | Marks local changes that still need to be pushed |

Hive adapters are generated in `*.g.dart`; those files are not edited by hand.

## Local Persistence

`HiveService` owns local persistence. It opens two boxes:

| Box | Records |
| --- | --- |
| `workout_plans` | `WorkoutPlan` |
| `workout_sessions` | `WorkoutSession` |

UI-facing reads hide tombstoned records. Raw reads include tombstones so sync can
push deletes.

`HiveService` also runs a one-shot migration from old integer Hive keys to stable
ID keys. Before re-keying records, it writes a JSON safety backup to
SharedPreferences.

## Cloud Sync

`SyncService` implements a small last-write-wins sync loop between Hive and
Supabase Postgres.

```text
local mutation
  -> mark record dirty
  -> debounce sync
  -> push dirty plans
  -> push dirty sessions
  -> pull changed plans
  -> pull changed sessions
```

Sync uses whole aggregate rows: one plan or one session is stored as promoted
columns plus a JSON `data` payload. Deletes are represented by `deletedAt`, not
hard deletion.

Conflict resolution is timestamp based:

- Remote wins when the remote `updatedAt` is newer than or equal to local.
- Local wins when the local `updatedAt` is newer; the dirty push carries it to
  the server later.
- Sync errors are swallowed and retried on the next trigger.
- Concurrent sync calls share the same active future.

Supabase auth gates the app when online support is configured. Offline-only
builds skip auth and open the app shell directly.

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

## UI Design

The visual language is terminal-inspired:

- JetBrains Mono typography.
- Rounded corners on a size-graduated scale, and one-pixel borders.
- Dark and light themes backed by the same semantic color helpers.
- User-selectable accent colors.
- Minimal elevation.
- Clear pressed and splash states for interactive elements.

UI code should use theme helpers from `lib/theme/app_theme.dart` instead of
hardcoded black or white colors, and corner radii from `lib/theme/radii.dart`
instead of literal `BorderRadius` values. Radii are graduated by element size —
cards and dialogs are the roundest, badges barely — so the same roundness reads
correctly on a 148px card and a 20px badge. Retuning the whole app means editing
the six scale constants in that one file.

## Backup And Import

`BackupService` exports all plans, sessions, and settings into a versioned JSON
file. Imports validate JSON shape and supported versions before replacing local
data.

Version 1 backups without stable IDs are upgraded on import by assigning IDs and
marking records dirty so they can sync upward.

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
