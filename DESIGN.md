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
  -> AdoptLocalData.prepareLocal()                 (owner handover + recovery/normalization)
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
| Repositories | `lib/repositories/` | Thin split and training-structure data access |
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
| `WorkoutSessionProvider` | Completed-session list and session mutations for the active split |
| `TrainingBlockProvider` | Split structure, per-plan progress and session indexes |
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
| `SetTemplate` | One target set in a plan: reps, weight, and optional RPE |
| `ExerciseTemplate` | Exercise entry with targets and optional workout guidance |
| `WorkoutPlan` | Named plan with exercises, optional color, explicit order, and `splitId` |
| `WorkoutSession` | Draft/log with stable ID, date, exercises, timer, `trainingWeekId`, retained week label and optional completion evidence |
| `TrainingBlock` | Split-wide named block with explicit order and intended week count |
| `TrainingWeek` | Durable slot allocated when needed; labels are not identity |
| `WorkoutProgress` | A plan’s active week, available week IDs, ready/boundary state and revision |
| `Split` | An independent training workspace that owns plans and sessions |
| `SplitPreference` | The account's active split, keyed by user ID |

Splits, plans, sessions, blocks, weeks and progress carry sync metadata. `SplitPreference` keeps
only `updatedAt` and `dirty`: it is keyed by `userId` and is never deleted.

| Field | Purpose |
| --- | --- |
| `id` | Stable local and remote record identity |
| `userId` | Supabase owner when synced |
| `updatedAt` | Last local or remote write timestamp |
| `deletedAt` | Tombstone for soft deletes |
| `dirty` | Marks local changes that still need to be pushed |

Hive adapters are generated in `*.g.dart`; those files are not edited by hand.
Plans are shared prescription templates across all blocks. A saved destination
always wins over initialization. The first week of the first block uses targets.
Week 1 of a later block copies Week 1 of the immediately preceding live block
for the same plan. Every later week copies the preceding supplied week's
completed values within its own block. Missing sources use current targets.
Exercises match by normalized name and occurrence; current order/guidance wins,
set values/RPE/count are deep-copied, and past set notes are not inherited.
Untouched previews never create logs. Previous-set references instead follow
earlier structural slots; plan-editor Last and analytics remain date-based.

## Training blocks and progress

Blocks and durable week IDs are shared within a split; available week tabs and
active progress belong to each workout. Creating a four-week block stores an
intended length of four but allocates only Week 1. Completing Push Week 1
allocates/reuses Week 2 and reveals it only for Push; Pull keeps its current
week and values. Available IDs persist across blocks, restarts and history
editing. Existing pre-created rows remain stored, while unused future tabs are
hidden separately for each plan.

Logging an active week advances automatically while its number is below the
intended length. Completing the intended final week records a pending boundary
without allocating another week. On the next ordinary entry, choose Add week,
Move to the next block, or Create block when none follows. The choices are
option cards in a sheet, each with a line saying what it does; the natural next
step (Add week, or a week that already exists) carries the accent. Dismissal
preserves the completed result, and a *Block complete* notice above the log
offers Choose next week. The strip's Add week control also gains an accent
ground at that point. Add week extends the shared
intended length by one and moves/reveals only the choosing workout. Browsing,
time, draft discard and another plan's completion never advance progress.

New and duplicated plans and Coach additions visibly choose a starting slot,
defaulting to Week 1 of the first block. The plan editor shows it as a
*Starting week* field under the name, and Coach as a one-line *Starts at* row.
Both open one bottom sheet: each block is a selectable row, and the chosen
block expands to show its weeks as chips, so block and week read as one
decision. Pickers include intended future week
numbers without allocating them; saving the new plan allocates/reuses only its
chosen slot. Existing plan edits retain progress. Create block accepts an
intended length of 1–52 weeks and a 1–40 character trimmed name; explicit
extensions can go beyond 52. Blocks can be renamed/reordered.
Holding a week tab opens a sheet with *Delete week*. It deletes that week for
the open workout only: its logs and drafts there are tombstoned and the tab is
no longer supplied, while the shared week row stays for the split's other
workouts. Logged or edited weeks confirm first; an empty one goes without a
dialog. A workout's only reached week can't be deleted. Deleting the active
week moves progress to the nearest earlier reached week (else the nearest
later one) at a fresh revision, so a completed slot shows *Continue* and
reaching the deleted number again reuses the same week ID. Block deletion,
week rename/reorder, Skip, Repeat, block prescriptions and block-based
analytics are outside V1.

The workout's bottom navigation always fills the available width. The selected
week's block name stays at the left and Add week (+) stays at the right; only
that block's week tabs scroll between them. The selected week keeps its accent
underline and scrolls into view. The block name sits on a quiet ground, since a
ground means tappable, and opens a compact menu above it, shaped like the
split switcher. It lists every block in saved order with its intended length,
marks the current one with a radio-style check, and then shows Create block,
Rename block and Reorder blocks under a rule. Reorder is disabled until there
are two blocks. The block list scrolls while the commands stay pinned, unless
the text is too large for both to fit; then the whole menu scrolls. It closes
on selection, outside tap or Back. There is no separate block overflow menu or
collapse state.
Switching blocks restores the last week viewed in that block during this screen
visit, or its first supplied week on the first visit. Navigation saves pending
edits before changing selection. The plus control is disabled until the active
workout's final week is completed and selected; it then opens the same boundary
sheet. Creating a block opens its first week for browsing without moving active
progress. Only an explicit boundary choice moves into another block.

A completed session carries revision-bound completion evidence with a fixed
commit time and resulting revision. Recovery applies it only to the exact
expected progress state, so interruption between the log and progress writes
cannot log twice or advance an unrelated later visit. An already-started
nonactive draft can finish by exact session ID without advancing progress.
Completed logs are read-only in the logger; History retains explicit editing.
Session writes resolve the current label from the durable week ID, so a
structural rebase cannot make an in-progress edit restore an obsolete label.

## Local Persistence

`HiveService` owns plans, sessions, splits and preferences plus typed
`training_blocks`, `training_weeks` and `workout_progress` boxes. A small
`training_operations` box holds fixed structural recovery intents. Browser-only
`training_recovery_snapshots` holds safety/replacement JSON artifacts in
IndexedDB; native targets retain flushed files with atomic pending-file rename.
These artifacts are separate from the live graph and operation intents. UI reads
hide tombstones; raw reads retain them for synchronization.

Normalization durably writes an owner-scoped safety artifact before changing links. Legacy
weeks use deterministic split/number IDs inside one Block 1, preserving gaps,
all session IDs/values/timers, and orphan history. Explicit new structure uses
UUID4. Empty splits receive Block 1 / Week 1. Bootstrap metadata has a neutral
edit timestamp and cannot overwrite real structure/progress edits. Late legacy
rows reserve their original labels; colliding new weeks rebase under the same
ID with a journaled label update to linked session snapshots.

Replacement operations validate the full graph before writing, save an
owner-scoped safety graph and fixed desired graph through the platform snapshot
store, then roll forward after
interruption. Caught installer failures restore the safety graph under the
exclusive mutation gate. Recovery failure hides the logger behind an export/
retry flow. Export reads the artifact as JSON bytes on either platform.
Account handover clears the previous owner's boxes, cursors,
intents, safety artifacts and route/native state before showing another cache.

## Cloud Sync

`SyncService` implements a small last-write-wins sync loop between Hive and
Supabase Postgres.

The capable client sends `x-opengym-training-schema: 1`. After a successful
local safety copy and preparation, the additive SQL RPC activates an irreversible
per-account schema boundary. Activated accounts reject old reads and writes
through the API pre-request guard; unactivated accounts retain legacy access.
RLS and grants remain separate required deployment checks. Local tests do not
certify production configuration or authorize activation/deployment.

Sync pulls/normalizes before migrated uploads, pushes parents before children,
then pulls again and replays completion evidence. Deleted splits normally upload
last; capacity/name reuse may require uploading a pending parent tombstone first.
Schema 2 activation backfills intended duration and per-plan availability
without rewinding progress, then rejects schema 1 clients for that account.
Installing the migration alone does not activate an account. Session JSON
remains schema 1 because its representation has not changed.
Blocks, weeks, plans, sessions, progress and the active preference sync as rows.
Sessions retain duplicate slot logs under distinct IDs. Conflict resolution is
whole-row LWW, with durable tombstone precedence and live-progress revision
ordering on equal timestamps. Intended block length takes the greater value
because creation/extension can only grow it; concurrent renames and partially
uploaded legacy structure cannot shorten it. There is no set-level merge.

Pulls paginate in explicit ascending timestamp/ID order. Server timestamps are
not commit order, so startup/manual/account recovery and periodic full sweeps
repair late commits; absence from a partial pull never implies deletion.
New lazy slots use a block/number UUIDv5 identity, so independent offline
allocations reuse one Week 2. Legacy random-ID append collisions preserve both
IDs, rebasing the conflicting week and session labels, with three push attempts. Retry exhaustion leaves local
data dirty. Errors remain visible as retryable/upgrade-required sync state,
while Hive remains available for local training after successful preparation.
Concurrent sync calls share an active future; account-generation checks reject
old-account results, and structural mutations serialize with sync.

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
opened from the main flow. The Coach is the exception: it opens over Home
inside the Home tab, so the tab bar or rail stays visible (see `docs/coach.md`).

Back dismisses the nearest active layer before leaving its parent. Manage is a
Home mode: Back restores normal Home, and leaving or reselecting Home clears
Manage. Back from the History, Stats, or Settings root selects normal Home;
Back from normal Home retains the platform's exit behavior. Pushed details
return to their entry point, including details opened from Home's trained-day
shortcut. The weekly-training shortcut selects Stats, whose Back returns Home.

The exercise picker and preset browser have internal pages. System Back steps
from a category or selected-exercises list to muscle groups, or from preset
details to the catalog; another Back closes the flow. Picker Done intentionally
steps back in the same way, while Close, outside taps, and dragging the picker
down close it directly. Preset browsing retains the goal and catalog position.
Saving, deleting, or installing blocks dismissal until success or failure.

`WorkoutDestination.active(planId)`, `.week(planId, weekId)` and
`.session(sessionId)` carry route intent. Delivery re-fetches the exact current
records and rejects account changes, deleted sessions and missing explicit
slots. Exact IDs win over same-number weeks and duplicate logs. Orphan sessions
keep the detail route and retained display labels. History, resume and native
timer text includes block context when resolvable; optional notification text
never becomes identity.

`AppNavigationObserver` owns account-scoped route tracking. Workout and editor
states register their normal asynchronous leave flows with it. Timer intents
reuse the route displaying the exact session, rather than stacking another
copy. Returning through an editor honors save/discard prompts. A cancelled
leave keeps the current screen in place. Dialogs and sheets retain their input
and confirmations; both new workout pushes and route reuse wait until those
layers close. A pending notification finish confirmation waits for an autosave
or timer action to finish, even when no route changes. Deferred opens recheck
that the session is still live. The observer is replaced along with the
Navigator when the account changes.

## Bundled Workout Presets

The app compiles a read-only catalog of workout programs from the reviewed
preset research. Catalog metadata is never written to Hive or Supabase. Choosing
a program copies its workout days into ordinary user-owned plans, with explicit
positions so their schedule order survives synchronization. Every preset starts
in Block 1 with an intended length of four weeks, allocating only Week 1 at
installation. This also applies when reusing the untouched default split.
Each workout advances independently through Week 4, then uses the block boundary
prompt on its next ordinary entry to add a week or create a new block.
Installation is an
exclusive local mutation with compensating rollback across split, plan, and
active-preference boxes.

The Home split menu opens a responsive program browser. A segmented goal
track filters the catalog, and each program card shows its workout/rest rhythm
as accent squares beside its days and session length. Details lead with the
program's name, a figure sheet (days, minutes per session, exercises, who it
suits) and a labelled schedule whose training cells use the same solved plan
tints and numbers as the foldable workout-day list and Home's plan markers.
Folded days expose complete prescriptions, RIR, rest and substitutions; shared
guidance closes the page before the user creates a copy.

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
- The eight accent families are Blue, Amber, Coral, Rose, Teal, Violet, Slate,
  and Green. They are clearly coloured without going neon. Saved accent indices
  keep their original color family. Text and fills are solved separately for
  readability in each mode, and each role keeps the seed's *vividness* (its
  share of the sRGB chroma available at that hue and lightness) under an
  absolute chroma cap. Darkened tones therefore don't turn dusty or brown. The wordmark uses a dedicated, more saturated `brandAccent`
  tone of the selected color; ordinary controls retain the softer accent.
- The `> OpenGym` wordmark serves as the main brand signature. Keep it consistent
  and give it room instead of repeating the prompt symbol elsewhere.
- Every screen except Home shares one header (`AppHeader`): flat on the page
  colour, with a permanent hairline underneath and no tint on scroll, so in
  dark mode it reads as black. Home keeps its `> OpenGym` brand header, followed
  by a slash and a borderless active-split selector. An icon-only Coach action
  sits at the trailing edge on a quiet accent circle when available.
- Back is always the same neutral arrow (`AppBackButton`) with a *Back*
  tooltip, including the steps back inside the exercise picker and preset
  browser. Header actions keep the accent. Plan colours stay on Home, so the
  plan editor's Save and Add exercise use the accent too.
- Individual value grounds mean editable controls. Read-only values, such as
  saved sets in Workout details, use `ReadOnlyValue`: a bold `figures` value
  with no ground or border of its own. Exercise records may share a bounded
  surface to establish grouping; their set rows use single-edge hairlines
  and plain figures so they read as a record. Only the live set table draws
  individually boxed cells.
- Unknown data is left out rather than given a placeholder. A session
  duration that is null or under a minute counts as unknown
  (`knownDurationSeconds`), so History and Workout details never show "0m".
- History uses a date rail beside quiet session cards, with dates moving above
  cards at narrow widths or large text sizes. Workout names lead, followed by
  training context and compact metrics; a small trophy badge marks records.
  Sessions with no performed sets say *No sets logged* instead of emphasizing
  a zero volume. The card is the tap target, and search stays available while
  browsing.
- Workout details separates the workout title/date, a grouped session readout,
  and an *Exercise breakdown*. Numbered exercise panels contain their own
  headings, notes, ruled set tables and volume totals. Saved zero-rep sets
  remain visible, and an empty workout explicitly says it has no performed
  sets. Tables scroll horizontally when needed to preserve large text.
- A plan's menu (long press, or *Plan actions* in Manage) is a modal bottom
  sheet with a drag handle, not a dialog. *Delete plan* is always the last
  row, set apart by a rule and the error colour. In Manage, the drag grip
  leads each card and *Plan actions* trails it, so the two targets sit at
  opposite ends.
- Create and Edit plan share the workout log's open exercise sections, hairline
  dividers, filled weight/rep cells, and optional RPE controls. Exercises start
  expanded and can be collapsed or reordered using the trailing grip. Add set
  uses the app accent; Delete exercise stays separate in the error role. Holding
  a set opens its delete action, as in the workout. The shared keypad validates
  RPE from 1 to 10 and supports clearing it. Wide editor tables scroll at large
  text sizes. The plan colour palette opens from Change color to leave more room
  for training targets; Add exercise stays pinned at the bottom.
- A collapsed plan-editor row previews its sets in `figures`: the target
  (*3 × 12 · 70 kg*, or up to four mixed sets and then *+N*) and, only when
  the exercise has been trained in this split, *Last:* with the best set from
  that session. Optional RPE is included in the target preview.
- Settings runs Appearance, Workout, Artificial intelligence, Data, Account,
  Updates, About, and Danger zone, in that order. Account holds the sync
  status, then *Sign out* as an ordinary row. It shows when a user is signed
  in. Danger zone is always last. *Load sample data* replaces the active
  split's workouts, so it is a development tool. It only appears in debug
  builds (`SettingsScreen.showSampleData`, which defaults to `kDebugMode`).
- Stats runs Training blocks, Weekly training, Activity, Exercise progress,
  and Recent records. Training blocks opens on the block of the latest
  workout. It shows workouts, sets, volume, and records for that block. Its
  arrows compare an average trained week with the previous block that has
  workouts. Below them are sets for each week of the block (unreached planned
  weeks are empty outlines) and the three biggest estimated-1RM gains. With
  two or more trained blocks, a scrolling pill row switches blocks and
  *Compare blocks* ranks them per trained week. Sessions reach a block only
  through their training week. Stats selectors come in two shapes
  (`statistics_controls.dart`). A short, fixed set, such as the time range
  (`4W`, `12W`, `6M`, `1Y`, `All`, read aloud in full) or the compare
  measure, is a `SegmentedPills` track of equal-width segments. A longer or
  open-ended set, such as blocks or the exercise measures, is a
  `ScrollingPills` row that fades at whichever edge hides more pills. Both
  keep a 48px tap target around compact pills. Exercise progress gives each
  measure a one-line plain explanation and lists every lift with its latest
  value, sparkline, and change. Tapping a lift opens it in the detailed
  chart. Weekly charts label weeks by date, never by ISO week number. The
  weekly-training shortcut lands on Weekly training, below the blocks.
- Home labels the rotation bar with “Workout N of M”. The same workout
  numbers appear in the plan list's coloured markers. Muscle groups sit on
  their own line in the launcher; exercise, set, and duration values wrap as
  whole phrases. The weekly summary keeps its “This week” label and Stats
  navigation affordance even before the first workout is logged.
- Familiar labels and icons make actions understandable outside a technical
  audience.
- Pressed, focused, disabled, loading, empty, and error states should feel like
  parts of the same system.

Broad monospaced typography, square-bracket labels, and all-uppercase copy are
not part of the product identity. Figures that need to line up or hold their
width (Stats numbers and chart axes, record rows, the update status, the app
version, plan-editor rows) use `AppTypography.figures`: Manrope with tabular figures, so digits
align without a change of typeface. JetBrains Mono (`trainingData`) remains
only in a few compact training-data spots outside Stats and Settings. The `>` symbol is reserved for the OpenGym wordmark rather
than used as a general interface decoration.

UI code should use theme helpers from `lib/theme/app_theme.dart` instead of
hardcoded black or white colors, and corner radii from `lib/theme/radii.dart`
instead of literal `BorderRadius` values. Radii are graduated by element size:
cards and dialogs are the roundest, while badges use a smaller radius, so the
same roundness reads correctly on a 148px card and a 20px badge. Retuning the
whole app means editing the six scale constants in that one file.

## Backup And Import

`BackupService` exports format v5: all splits/plans/sessions, intended block
lengths, allocated weeks, each plan's available/active weeks, settings and
source-account provenance. Imports validate the complete graph before replacing
local data. Versions 1–4 reuse normalization; unsupported future versions and v5
backups missing duration/availability fail explicitly.

Same-account restore preserves identities unless live restored rows would
resurrect known tombstones. Foreign/unknown-provenance backups and those
resurrection cases copy the full graph to new identities, including progress
and completion references. Restoring a shorter schedule or removing a lazy
slot from a retained block also uses new identities, so its next deterministic
week ID cannot be stranded behind a deletion marker. Activation state is never copied. Restores tombstone
omitted records and use the same recoverable replacement writer as installers.

Deleting a plan tombstones progress and retains history. Split deletion cascades
the entire graph after saving the replacement preference. Clear All Data retains
split profiles and gives each a fresh Block 1 / Week 1. Sample replacement affects
only the active split. A pristine default split can be reused by installers;
renamed/extended/reordered empty structure counts as user content.

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
