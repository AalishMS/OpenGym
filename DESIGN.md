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
| Typography | Manrope and JetBrains Mono, bundled in `assets/google_fonts/` and resolved by `google_fonts` with runtime fetching off |

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

Each surface the gate puts in place of another (login, password recovery,
the app once `AuthenticatedHome` has prepared its data, or the preparation
failure) fades in on the page colour from partial opacity over
`AppMotion.quick` (`SurfaceFade`). What it replaces is removed at once rather
than kept beside it, so a sign-out never leaves the previous account's
screens, routes or focus on show. The app is uncovered the same way when
password recovery finishes; arriving from login or the sign-in check, it fades
in once, through `AuthenticatedHome`. The sign-in check and data preparation
usually finish within a frame or two, so their spinners stay unpainted for
`AppMotion.patience` (300ms) and then fade in over `quick`, only for a wait
that is real (`PatientProgress`); screen readers hear the progress label from
the start.

The login screen has four modes (sign in, create account, reset email, new
password). Switching between them crosses the heading and its line, the
primary button's label and the mode link in place; fields and links that
come and go fold open and closed, and one on its way out gives up focus at
once. The error or confirmation line folds open beneath the fields and, when
a new attempt clears it, folds away still reading what it said. While
signing in, the button's label crosses to its progress indicator.

The app is split into small layers:

| Layer | Location | Responsibility |
| --- | --- | --- |
| Models | `lib/models/` | Hive objects and JSON serialization |
| Providers | `lib/providers/` | UI-facing state and `notifyListeners()` |
| Repositories | `lib/repositories/` | Thin split and training-structure data access |
| Services | `lib/services/` | Storage, sync, backup, statistics and personal records, seeding |
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
| `SettingsProvider` | Theme mode, accent color, units, week start, start from last week's sets |
| `UpdateProvider` | Self-update from GitHub Releases: checks at launch and on resume, Wi-Fi prefetch, snoozed prompt, session install |

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
| `ExerciseDefinition` | Account-wide movement identity, library name, search aliases and optional merge redirect |
| `Exercise` | One logged occurrence with an exercise ID, name snapshot and list of sets |
| `SetTemplate` | One target set in a plan: reps, weight, and optional RPE |
| `ExerciseTemplate` | Plan occurrence with an exercise ID, name snapshot, targets and optional guidance |
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
Exercises match by canonical exercise ID and occurrence; current order/guidance wins,
set values/RPE/count are deep-copied, and past set notes are not inherited.
Untouched previews never create logs. Previous-set references instead follow
earlier structural slots; plan-editor Last and analytics remain date-based.
The copying above is Settings → Workout → *Start from last week's sets*, on by
default (stored as `auto_fill_last`, backed up as `autoFillLast`). Off, a week
with no saved data opens with the plan's current targets instead; saved drafts
and logs are never changed, and the Previous column still shows the earlier
logged sets. Discarding a draft rebuilds the week exactly as a fresh open would,
under the same setting. The logger builds new weeks from the plan as currently
saved, not the copy it was opened with.

### Exercise identity

Occurrences are identified by their stable catalog `exerciseId`, never by the
name snapshot they carry (see [exercise identity](docs/exercises.md)). Plan
templates, workout initialization, Previous values, history, Stats, records and
timed measurement all resolve `ExerciseCatalog.identity(name, exerciseId)`, so
an occurrence keeps its history whatever it is called. The workout's exercise
menu is Exercise note, Rename exercise, Replace exercise (drafts only), Move
up/down, and Delete exercise last.

- *Rename exercise* changes the occurrence's label and keeps its ID, so
  history, Previous values, records and measurement stay together. It saves
  names without surrounding or repeated whitespace. *Also rename in plans and
  past workouts*, checked by default, shows how many plans and workouts in the
  split contain the same movement. Checked, `ExerciseRenameService` rewrites
  the label of every live plan and workout occurrence in the split that
  resolves to the same canonical ID. It keeps each `exerciseId`, filling a
  legacy null with the resolved identity, and leaves sets, notes and targets
  alone. Writes run under the sync gate, mark changed rows dirty with a fresh
  `updatedAt`, and schedule a sync; other splits and tombstones are untouched.
  An owned custom catalog movement is also relabelled through
  `ExerciseCatalog.rename`, so the picker and Stats agree. Bundled labels are
  permanent. Renaming never merges identities: when the new name already
  belongs to another movement, the dialog says the histories stay separate and
  points to Settings → Manage exercises, where merging is explicit.
- *Replace exercise* opens the library in single-choice mode and swaps the
  chosen movement, with its catalog ID, into this workout only. It keeps the
  set count. Weight and reps come from that movement's latest logged
  performance in the split, or weight 0 with the same reps when there is none.
  RPE, set notes and the exercise note are cleared. Movements already in the
  workout show as *Added* and can't be chosen.
- Built-in movements carry a kind in `ExerciseLibrary` (weighted, bodyweight
  or timed), keyed by their permanent ID. `ExerciseCatalog.kindOf`/`isTimed`
  resolve an occurrence's canonical ID, so a renamed hold still stores
  seconds, a merge into a hold follows the hold, and a custom movement is
  weighted whatever it is called.

### Personal records

Records are derived, never stored, and have one definition:
`StatisticsAnalyticsService.recordEvents`. Stats (Records and each block's
Records figure), the History PR pill, Workout details, live workout marks and
the summary after logging all read it, so they cannot disagree.

- Only completed, live workouts in the split count, in date order, and only
  sets with reps above zero. Lifts match by canonical catalog ID; a movement
  logged twice in one workout is one lift there.
- The first workout with performed sets of a lift sets its baselines and is
  never a record, not even between its own sets. Records start from the second
  workout with that lift.
- Each later workout is compared with the workouts before it, not with its own
  sets, so it breaks each record at most once. Its best set is a *heaviest
  weight*, *best set volume* (weight × reps) or *estimated 1RM* record when it
  beats the previous best. An estimated 1RM needs an earlier one to beat.
- A set of N reps at weight W is an *N-rep best* when W beats the heaviest
  weight previously lifted for N or more reps, and no other set in the workout
  matched it with as many reps and as much weight. 70 kg × 5 after 70 kg × 8 is
  not a record; 75 kg × 5 is. With no earlier set of N or more reps there is
  nothing to beat.
- Set volume, rep bests and estimated 1RM come only from weighted sets (weight
  above 0), so the first loaded set after bodyweight-only workouts sets their
  baseline. Heaviest weight treats earlier performed bodyweight sets as a
  baseline of 0, so the first added load after them is a record, as the live
  mark has always shown. A set at weight 0 with reps is a bodyweight set
  (decided by the data, for library and custom lifts alike); its best is *most
  reps*, against the most reps in an earlier bodyweight set.
- A timed lift (Plank, Side Plank) stores seconds in `reps`: it counts as sets
  but stays out of rep totals, volume load, estimated 1RM and block gains, and
  only earns *longest hold*. Volume load stays weight × reps, so bodyweight
  sets add 0.
- Each record carries the value it beat and the exercise and set index of the
  set that broke it. Workout details marks exactly that set; a set note that
  says "PR" is only a note.
- The logger's live PR mark is the heaviest-weight subset, judged with
  `StatisticsAnalyticsService.recordJudge` against the split's other logs (a
  logged workout being edited compares only with earlier ones). One set per
  lift is marked, never on the lift's first workout and never for a hold.
- `WorkoutCompletionService` judges the just-logged workout with the same rules
  and returns `records`; its `personalRecords` (`PRResult`) is the
  heaviest-weight subset that the workout summary lists.

Exercise definitions are shared across splits within one account. Bundled IDs
are permanent; custom entries are reusable offline. Names and reviewed aliases
support search, while statistics, records, initialization and previous sets use
IDs. Legacy names migrate conservatively with the same recoverable graph flow.
Settings → Manage exercises offers custom renaming and confirmed merging.
Merges retain original logs and resolve redirects instead of deleting sets.
See [exercise identity](docs/exercises.md) for migration, conflict, and backup
behavior.

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
*Starting week* pill under the name, and Coach as a one-line *Starts at* row.
Both open one bottom sheet: each block is a selectable row on the sheet (not a
tile in it), and the chosen block expands to show its weeks as pills, so block
and week read as one decision. Pickers include intended future week
numbers without allocating them; saving the new plan allocates/reuses only its
chosen slot. Existing plan edits retain progress. Create block accepts an
intended length of 1–52 weeks (four by default, the same default presets use for
Block 1) and a 1–40 character trimmed name; explicit extensions can go beyond
52. Blocks can be renamed, extended, shortened, deleted and reordered. Edit
block can shorten a block to the highest week anything has reached (an
allocated week row, a plan's active or available week, or a session's week) and
never allocates week rows; weeks and logged workouts always stay in the block.
When every week has been reached the minus is disabled with an explanation.
*Delete block* sits apart from Cancel and Save in the error colour: it is
disabled, with the reason beneath it, for a split's last block, a block with
logged workouts, or a block a plan is positioned in, and otherwise confirms
(*Delete {name}?*, Cancel / Delete) before tombstoning the block and its weeks.
Failures after confirming show in the form's error line and keep it open. For
a signed-in account both shortening and deleting appear only after the server
accepts training schema 4 (`TrainingBlockRepository.lifecycleAvailable`);
without it the old grow-only rule holds and Delete block is absent. Delete needs
a connection. When the sheet's starting week no longer exists after a shorten or
delete, the selection moves to the block's last remaining week, or to the first
remaining block's first week.

Blocks are managed in the plan editor as well as the workout screen. In a new
plan, the starting-week sheet has *Create block* and a per-block *Edit block*
button (Home's *Duplicate plan* sheet offers the same through
`TrainingBlockActions`, shared by both screens); a block created there is selected at Week 1 so a later planned week can
still be chosen before *Use this week*. Editing an existing plan shows a
*Training block* pill under the name (e.g. `Strength · Week 2 of 4`) that opens
the same sheet in a management mode: blocks with their lengths, the plan's
current block marked with a check, Edit block and Create block, and a Done
button. Nothing is picked there, so the other rows carry no empty radio ring,
and tapping a row edits that block.
Create block and Edit block open inside that sheet, replacing the block list
until Cancel or Back returns to it, so only one layer is ever open: the two
trade places in a quick cross while the sheet eases to the new height, and
while picking, the chosen block's weeks fold open beneath it as the last
block's fold away. From the
workout's block menu they, and Reorder blocks, open as a bottom sheet of their
own. The form sets the length with one stepper (minus, the week count, plus)
on a control fill; a key that can't be pressed sinks into the fill. A week
track beneath it shows the weeks already reached, which can't be removed, in
the accent and the planned ones in its quiet wash. It cannot
move the plan to another block or week. Block changes save immediately and are
shared by every workout in the split, so they are outside the editor's
Save/Discard. Extending a block while a workout waits at its boundary needs no
repair: progress stays *awaiting boundary*, the sheet then offers *Continue to
Week N* in place of Add week, and that allocates the next week of the same
block.
Holding a week tab opens a sheet with *Delete week*. It deletes that week for
the open workout only: its logs and drafts there are tombstoned and the tab is
no longer supplied, while the shared week row stays for the split's other
workouts. Logged or edited weeks confirm first; an empty one goes without a
dialog. A workout's only reached week can't be deleted. Deleting the active
week moves progress to the nearest earlier reached week (else the nearest
later one) at a fresh revision, so a completed slot shows *Continue* and
reaching the deleted number again reuses the same week ID. Deleting a block
the workout is viewing (not the one its progress is in, which is protected)
returns the screen to the workout's active week. Week rename/reorder, Skip, Repeat, block prescriptions and block-based
analytics are outside V1.

The workout's bottom navigation always fills the available width. The selected
week's block name stays at the left and Add week (+) stays at the right; only
that block's week tabs scroll between them. The selected week keeps its accent
underline and scrolls into view; a reload that brings the same weeks leaves the
row where it was scrolled. The week the workout is training now carries a small
accent dot before its label, so it reads apart from a week that is only being
browsed. The block name sits on a quiet ground, since a
ground means tappable, and opens a compact menu above it, shaped like the
split switcher. It lists every block in saved order with its intended length,
marks the current one with a radio-style check, and then shows Create block,
Edit block (rename and add weeks) and Reorder blocks under a rule. Reorder is
disabled until there are two blocks. The block list scrolls while the commands
stay pinned, unless
the text is too large for both to fit; then the whole menu scrolls. It closes
on selection, outside tap or Back. There is no separate block overflow menu or
collapse state.
Switching blocks restores the last week viewed in that block during this screen
visit, or its first supplied week on the first visit. Navigation saves pending
edits before changing selection. The plus control always responds. Before the
active block's final week is logged it adds nothing and says what unlocks the
next week (*Week 2 of 4 in Build. Log Week 2 to unlock Week 3.*), with a
*Go to Week n* action when another week is on screen. Once the final week is
logged it carries the accent and opens the same boundary sheet, first moving to
that finished week if another one is selected. Deleting the selected week
follows progress to the active week, since a block left with no reached weeks
still lists its first week as a browsing entry. Creating a block opens its first week for browsing without moving active
progress. Only an explicit boundary choice moves into another block.

A completed session carries revision-bound completion evidence with a fixed
commit time and resulting revision. Recovery applies it only to the exact
expected progress state, so interruption between the log and progress writes
cannot log twice or advance an unrelated later visit. An already-started
nonactive draft can finish by exact session ID without advancing progress.
Completed logs stay editable in place in the logger, the same way a draft is:
sets, RPE, notes, exercises and their order autosave, and the workout menu
corrects the start date/time and duration. Edits keep the log completed, its
plan, week and completion evidence, and never move progress; History's Edit
workout remains for logs whose plan or week is gone. Live record marks on a
log compare only against workouts logged before it, and edits never buzz.
Session writes resolve the current label from the durable week ID, so a
structural rebase cannot make an in-progress edit restore an obsolete label.

## Local Persistence

`HiveService` owns plans, sessions, splits and preferences plus typed
`training_blocks`, `training_weeks` and `workout_progress` boxes. A small
`training_operations` box holds fixed structural recovery intents. The dynamic
`exercise_definitions` box stores account-wide custom movements and redirects. Browser-only
`training_recovery_snapshots` holds safety/replacement JSON artifacts in
IndexedDB; native targets retain flushed files with atomic pending-file rename.
These artifacts are separate from the live graph and operation intents. UI reads
hide tombstones; raw reads retain them for synchronization.

Normalization durably writes an owner-scoped safety artifact before changing links. Legacy
weeks use deterministic split/number IDs inside one Block 1, preserving gaps,
all session IDs/values/timers, and orphan history. Explicit new structure uses
UUID4. Empty splits receive Block 1 / Week 1; a new split's Block 1 has an
intended length of four weeks (`kDefaultBlockWeeks`), whether it comes from a
custom split, a first plan, or the Coach. A default split bootstrapped before
that keeps its one-week Block 1, and both count as untouched for reuse (the
check looks at ids, names, position and edit stamps, not at the length).
New-structure blocks get random ids, so two devices' bootstraps never merge;
a legacy block's deterministic id merges by maximum length. Bootstrap metadata has a neutral
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

The capable client sends `x-opengym-training-schema: 3`. After a successful
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
Installing the migration alone does not activate an account. Schema 3 adds the exercise catalog and protects exercise IDs from older clients.
Session JSON remains training schema 1 because its slot representation has not
changed.
Exercise definitions, blocks, weeks, plans, sessions, progress and the active
preference sync as rows. Exercise definitions are pulled before workouts and
pushed before plan/session references; explicit merges dominate unmerged copies.
A missing custom merge target is deferred metadata: the last known movement
remains usable offline, and later target delivery completes resolution. Missing
metadata never blocks local preparation; definition shape and account ownership
remain validated.
Sessions retain duplicate slot logs under distinct IDs. Conflict resolution is
whole-row LWW, with durable tombstone precedence and live-progress revision
ordering on equal timestamps. Intended block length resolves on its own clock at schema 4: the newer
duration change wins and a tie (including every pre-4 writer, which sends no
clock) keeps the larger count, so a rename never undoes a shorten or an
extension. Before schema 4 the count only grows. The client negotiates schema 4
and falls back to 3 against a server without
`20261116120000_block_lifecycle.sql`, where shortening and deleting stay
unavailable. Deleting a block goes through a guarded RPC that refuses a split's
last block and a block in use. A block deleted on another device while this one
still has a workout in it or a plan positioned in it is rescued: that live work
moves to a successor block with an ID derived from the deleted one. Rescue
applies to local-only data and to an account whose negotiated schema is 4; below
that (including an account whose level is not known yet) the older cascade
applies, because a server without the migration refuses a relinked session on
every sync. A completed workout whose progress write was interrupted is applied
to its progress row before the rescue changes that row's revision. A block
shorter than its highest allocated week is healed up to that week. Known limits:
rescue keeps every live workout in the deleted block, including history of
deleted plans, so a rescued block cannot be deleted while it holds them. Each
block is rescued on its own, and one which cannot be rescued cleanly (the graph
would stop validating, or its weeks cannot be mapped) follows the older cascade,
which tombstones the live workouts in it; every such skip is logged with the
block ID and the reason. A block-length change made offline by an app version
older than schema 4 carries no clock, so it loses to a length another device has
since set at schema 4 (weeks already reached are still kept by the heal step),
and device clocks decide which length edit is newest. Once an
account is at schema 4, older app versions are fenced off and stop syncing
until updated. There is no set-level merge.

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
their state. In the phone layout, horizontal swipes across the screen select
the adjacent destination in Home, History, Statistics Overview, Strength,
Blocks, Records, Settings order and update the bottom navigation. Statistics
consumes swipes between its sections before leaving for History or Settings;
swiping in from either side opens the nearest section. Without logged workouts,
Statistics has a single empty screen. The first and last tabs do not wrap.
Vertical scrolling stays within the current screen, and short accidental drags
do not switch destinations. Charts keep their own horizontal browsing gestures.
Main-tab changes use the same selection behavior as navigation taps. The Coach
overlay keeps its own gestures; main-tab swiping resumes when it closes.

Android's predictive back gesture is enabled
(`enableOnBackInvokedCallback`), so a back swipe previews the page underneath
on Android 13+; screens that guard unsaved work still intercept it through
`PopScope`. Starting a workout from Home's Next up card flies the plan name
into the workout header (`PlanTitleHero`); other entry points open normally.

The selected bottom tab is marked by a short accent rule on the top hairline as
well as by colour and weight, so selection never rests on colour alone. When the
selection moves, the rule slides while both destinations' icon and label ease
their colour over the same time (`NavSelection`), and the update dot fades in
and out rather than popping (`NavBadge`); the desktop rail settles its labels
and icons the same way. The label's weight changes at once: the bundled
Manrope files are static weights, so a weight eased through them would re-lay
the label out in steps and shift it. Moving to another tab gives a selection
haptic and a brief fade-in from partial opacity (`SurfaceFade`), so its first
frame already shows the new tab rather than the bare page (none under reduced
motion). The weekly-training shortcut's switch
to Stats fades the same way. Tapping the tab that is already showing scrolls it back to the top;
on Home it also closes the Coach and Manage.

While a workout is in progress, a resume strip sits directly above the bottom
navigation (below the content beside the desktop rail). It shows the plan's
colour, the plan name, and the live session clock, and opens that workout in
one tap, switching split if needed. It shows the running timer, or else a paused
workout started within the last 12 hours (`HiveService.getLiveSession`). It
listens to the sessions box directly, so finishing, deleting, or a sync pull
removes it. Pushed routes such as the workout screen cover it. When it appears
or goes while the shell is in view, it folds open or closed above the
navigation (`Collapsible`), and a strip on its way out takes no taps or
semantics; a change
made while a route covers the shell or the app is in the background lands at
rest, so returning never replays it. Inside the strip, running and paused
change together at once, and the clock ticks without animating.

| Tab | Screen |
| --- | --- |
| Home | `HomeScreen` |
| History | `HistoryScreen` |
| Stats | `StatsScreen` |
| Settings | `SettingsScreen` |

Workout plan creation, editing, and active workout logging are separate screens
opened from the main flow. The Coach is the exception: it opens over Home
inside the Home tab, so the tab bar or rail stays visible (see `docs/coach.md`).
It arrives as a page one level deeper does in the exercise picker, fading in
while it travels the last 24px from the end side, and leaves the same way back
over `AppMotion.standard`. Home keeps its state beneath, stops taking taps the
moment the Coach starts to arrive, and takes them again the moment it starts
to leave; the leaving Coach gives up focus, closing the keyboard. A Coach
closed out of view (behind another tab, for the tour, or on sign-out) simply
goes.

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

Android workout notifications use a system chronometer for elapsed time and
retain Pause/Resume and Stop controls in the notification panel. While running,
they request Live Update promotion on Android 16+ so supported devices can also
show the timer in a status-bar chip. Pausing withdraws that request; resuming
restores it. Promotion depends on the Android release, manufacturer and user
notification settings. Other devices keep the regular timer notification.

## Bundled Workout Presets

The app compiles a read-only catalog of workout programs from the reviewed
preset research. Catalog metadata is never written to Hive or Supabase. Choosing
a program copies its workout days into ordinary user-owned plans, with explicit
positions so their schedule order survives synchronization. Every preset starts
in Block 1 with an intended length of its `blockWeeks` (four for every bundled
preset; the length lives with the preset data), allocating only Week 1 at
installation. A new split's Block 1 is created at that length. When the
untouched default split is reused, its existing block grows to the preset's
length but never shrinks, so a longer existing block keeps its length. The
preset detail shows it as *Starts with* a *N-week block* before installing.
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
guidance closes the page before the user creates a copy. The catalog and a
program's details trade places along a horizontal axis, as the exercise
picker's pages do (`PageSwitchTransition`); the install bar belongs to the
details and travels with them. Both pages stay alive throughout, each on its
own scroll position, so the catalog keeps its goal and place, and the page
that isn't showing is offstage. Each page is built once per change, not on
every frame of it. Workout days fold open and away (`Collapsible`).

## UI Design

OpenGym uses a clean, practical visual language with a restrained personal
signature:

- Clear type hierarchy keeps workout names, values, units, and supporting text
  distinct at a glance.
- Calm backgrounds and surfaces give dense training data room to breathe.
- Rounded corners follow a size-graduated scale: badges are the tightest,
  controls and cards rounder, and sheets and dialogs — whatever floats over a
  scrim — the roundest. Pills are fully round.
- Elevation reads as light. Pages sit on the background; the few things that
  stand forward (the workout launcher, preset cards,
  the Workout details readout and exercises, dashboard panels) are *raised*:
  white with a soft two-layer shadow in light mode, and in dark mode a lifted
  fill with a hairline edge, since a shadow has nothing to fall on
  (`RaisedCard`, `raisedDecoration`). Sheets, dialogs and menus are raised too,
  and the scrim separates them. Nothing sits darker than the page except a
  control's own fill, and a card is never nested in another ground.
- Controls are fills, not outlines. Text fields, steppers, chips, segment
  tracks, secondary buttons and keypad keys sit on the control fill. A segment
  track (`SegmentTrack`, Settings' theme and weight unit) marks the choice with
  a rounded accent thumb inset in the track, not a square-edged segment; a field
  rings only for focus or an error (`RingInputBorder`). Secondary buttons are
  filled neutrals, and frequent-but-not-primary actions such as Add exercise
  use the tonal accent: the accent's quiet wash with accent ink.
- Lines are hairlines: dividers, ledger rows, the header and tab rules, and
  card edges in dark mode. The 3:1 border is kept for the edge of an unfilled
  control — an unselected radio, an off switch, an empty week bar.
- In menus and lists, the chosen row is marked by a check and a heavier
  weight, not a coloured wash behind it.
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
  Settings offers them as bare swatches; the chosen one gets a ring and a
  check, which settle in together, rather than a tile behind it.
- The `> OpenGym` wordmark serves as the main brand signature. Keep it consistent
  and give it room instead of repeating the prompt symbol elsewhere.
- Every screen except Home shares one header (`AppHeader`): flat on the page
  colour, with a permanent hairline underneath and no tint on scroll, so in
  dark mode it reads as black. Screen and dialog titles are set a size up from
  section titles (20px, extra bold, tightly tracked). Home keeps its `> OpenGym` brand header, followed
  by a slash and a borderless active-split selector. An icon-only Coach action
  sits at the trailing edge on a quiet accent circle when available. The
  split menu settles out of the selector as it opens and closes at once.
  Choosing another split crosses the selector's name to the new one while its
  width eases, and fades Home's content in from partial opacity over `quick`
  (`SurfaceFade`). The last split's plans go at once rather than crossing, so
  nothing from them is read or tapped on its way out. The same fade marks plans arriving on an empty Home, or the last
  one deleted, while Home is in view; a change made under a page or on
  another tab is simply there on the way back.
- Back is always the same neutral arrow (`AppBackButton`) with a *Back*
  tooltip, including the steps back inside the exercise picker and preset
  browser. Header actions keep the accent. Plan colours stay on Home, so the
  plan editor's Save and Add exercise use the accent too.
- A ground means tappable. Read-only values, such as the saved sets in Workout
  details, use `ReadOnlyValue`: a bold `figures` value in the primary text
  colour with no ground and no border. The table rows are separated by square
  single-edge hairlines, so the values read as a record and not as editable
  cells. Only the live set table draws boxed cells.
- Unknown data is left out rather than given a placeholder. A session
  duration that is null or under a minute counts as unknown
  (`knownDurationSeconds`), so History and Workout details never show "0m".
- Don't nest a ground inside a card. History is a ruled ledger, not a stack
  of cards: each month heads its workouts with a count and volume tally over a
  strong rule, and each workout is a row on the page ground separated by
  hairlines. The date sits on a rail at the left (above the row at narrow
  widths or large text); a second workout on the same day leaves the date out
  and the rule between the two starts after the rail. A row leads with the
  workout name and PR flag, then its block, week and known duration; volume
  and set count sit right-aligned in `figures` so a month compares down the
  page (they join the context line at large text), and the exercise names run
  full width beneath. A session with no performed sets says *No sets logged*
  instead of zeros. The ledger appears with the tab, without an arrival.
  Searching folds a match count open under the field, and the results and
  *No matching workouts* cross in place; typing more only changes what is
  shown, and replays nothing.
- Workout details opens with the long date, the workout name, its block and
  week, and how many exercises set a record (accent ink). A bounded readout
  puts Volume load and Duration large, over Exercises / Sets / Reps. Each
  exercise is its own numbered card: the accent number sits in the set-number
  gutter, volume trails the name (or joins the summary line when narrow), the
  note hangs off an accent rule, and sets below in the ruled table. Sets saved
  at zero reps stay on the record in the secondary ink. The set that broke a
  personal record (see Personal records) carries a *PR* badge beside its
  weight, and its weight is read aloud with ", Personal record". A timed
  exercise heads its count column *Time* and shows holds as `45 s`, or `1:30`
  from 90 seconds up; its summary gives the longest hold. Set notes,
  including ones that say "PR", always show as notes.
- A plan's menu (long press, *…* on a row, or *Plan actions* in Manage) is a
  modal bottom sheet with a drag handle, not a dialog. *Edit plan* leads,
  then *Duplicate plan* and *Change color*, and *Delete plan* is always the
  last row, set apart by a rule and the error colour. *Change color* opens a
  dialog holding the plan editor's own palette (`PlanColorPicker`), each
  swatch named for its colour to screen readers; it closes on Save with no
  snackbar, since the marker's new colour is the confirmation. In Manage, the
  drag grip leads each card and *Plan actions* trails it, so the two targets
  sit at opposite ends, and a tap on a card opens its menu rather than a
  workout: Manage arranges plans, and a grab that misses the grip changes
  nothing. Entering Manage folds the next workout and the week away so
  the plans rise to the top, while the rows cross to cards and *Manage* to
  *Done*; leaving unfolds them. Manage cleared by the app (another tab,
  reselecting Home, the tour) settles at once. Grid cards slide to their new
  places when one is dropped, moved from its menu, or deleted. They take ink
  but don't give under the finger: each carries a grip, and a give would pull
  against the card being lifted.
- The workout marks records while you lift. The set that would be the
  workout's heaviest-weight record if logged as entered (see Personal
  records: one set per lift, judged against earlier logs, never on a lift's
  first workout or for a hold) gets the PR badge, which pops in as it is
  earned, and a heavy haptic when the entry closes. A badge the log opens
  with, or one on a card scrolled back into view, is simply there, and so is
  one that moves up a row when a set above it is deleted. A set that goes
  past its Previous set (more weight, or
  more reps at the same weight) shows an accent arrow beside Previous.
  Exercises with no history are never marked.
- Finish in the workout header is labelled, not a bare check; large text on a
  narrow phone falls back to the icon. Finish and the compact timer controls
  expose their enabled state and tap action to screen readers. Logging opens
  an open summary on the page ground, without a card or enclosing border. The
  date and weekly workout count lead into the plan name and block/week. Volume
  lifted is the main figure, followed by comparison with the most recent
  earlier session of the same plan; Duration, Sets and Reps sit below a rule
  and wrap according to the measured text width. Compact spacing keeps a
  typical summary on one phone screen; accessibility text and long record
  lists remain scrollable. Personal records show the exercise, new
  weight/reps and the weight replaced. First-time exercises are counted
  separately. The wordmark signs the summary at the bottom. Figures show final
  values immediately, so Share always exports accurate totals. The header's
  Share action captures the complete summary as an opaque PNG after pending
  paint finishes, crossing to its progress in place while it works; that
  cross sits in the header, outside the image. Done returns to the log.
- The workout moves sparingly, because it is used mid-set in glances. The
  exception is changing plan, which is swiping between pages and should feel
  like it. During a swipe the log follows the finger one to one and fades as
  it goes, to half by 40% of the width; at the first and last plan, with
  nothing to go to, it gives only a twentieth of the travel and doesn't fade,
  so the edge reads as an edge. Let go short of a switch, it springs back
  with its opacity, carrying the flick, without overshoot. A switch, by swipe
  or tab, trades the logs: the old one carries on out and the chosen plan's
  comes in over it from the other side (see Pages, dialogs and sheets), while
  the header, the plan tabs and the week bar hold still and change in place.
  Once the new workout has landed it leaves like any page, so Back,
  Android's predictive back and iOS's edge swipe work after a switch. A
  set deleted from its hold menu folds away so the rows below rise into its
  place, in the workout and the plan editor. Work in flight (saving, starting
  or pausing the clock, logging, changing blocks) shows its progress line
  only once it has lasted 300ms, and the line folds open and away rather
  than shoving the log down and back; its label is in the tree from the
  start but is announced only once shown. A failed save's message and Retry
  fold open the same way. Holding an exercise's name or its note picks it
  up to move: the log folds to one short row per exercise, each travelling
  from its card's title, and the held row rises onto the raised ground from
  the name. Each row is numbered by its place, the numbers opening a column
  before the names as the log folds; a row that changes place rolls its
  number to the new one (`RollingFigure`). Rows of one height step aside one
  place at a time as it passes,
  and pushing it against the top or bottom scrolls them at a pace that grows
  with the push; a row picked up near an edge scrolls nothing until it is
  pushed further that way. Let go, the log is scrolled so the exercise sits
  where it was dropped, and every row travels back onto its title as the
  cards return, the numbers folding away. There is no handle on the cards: a
  tap on a name or note says *Hold and drag to reorder*, and the first *Move up* or *Move down* from an
  exercise's menu mentions the drag once in a snackbar. Changing week, the
  header's timer controls and the clock change in place without motion.
  Under reduced motion every change is immediate: the log doesn't follow a
  swipe, and a switch lands at once.
- Haptics are named for the moment (`lib/utils/haptics.dart`): a selection
  tick when the main tab changes or a plan or exercise is dropped into a new
  place, a light impact when a plan card or exercise is picked up to drag, a
  medium impact when
  the workout clock starts, a heavy one for a new record or a logged workout.
  Keypad keys keep their own selection clicks.
- Create and Edit plan share the workout log's open exercise sections, hairline
  dividers, filled weight/rep cells, and optional RPE controls. Exercises start
  expanded and can be collapsed or reordered using the trailing grip; with two
  or more, *Collapse all* (or *Expand all* once every one is folded) sits at
  the end of the Exercises heading, so a long plan can be reviewed and
  reordered folded. Add set uses the app accent; Delete exercise stays separate
  in the error role. Holding a set opens its delete action, as in the workout.
  The shared keypad validates RPE from 1 to 10 and supports clearing it. Wide
  editor tables scroll at large text sizes. The plan colour palette opens from
  a compact colour pill (the swatch and a chevron, labelled *Change color* for
  screen readers and as its tooltip) to leave more room for training targets;
  Add exercise stays pinned at the bottom as a tonal button. The plan name is
  the page's title: a large field led by the plan's colour bar and underlined
  by a hairline, the accent while typing. The starting week (or, when editing,
  the training block) and the colour pill share one row beneath it at phone
  width, and Save in the header is a pill. The line under the Exercises heading
  follows the cards: how to change targets while any card is open, and how to
  open one while all are folded.
- The editor moves with the app's motion tokens (`lib/theme/motion.dart`):
  exercise cards fold and unfold by growing and fading from the top while the
  folded summary gives way, chevrons turn, the palette and the missing-exercise
  message open the same way, the exercise count rolls, and the colour bar and
  swatch ease to a new colour. Exercises that arrive (from a starter or the
  picker) fade and lift into place, a starter's in quick sequence, and the
  line under the Exercises heading arrives with the first of them; exercises
  loaded with a plan don't. Under reduced motion every change is immediate.
- Creating a plan starts at its name: the field takes focus on a new plan (not
  on an edit), and the plan's colour defaults to the first palette colour no
  other plan in the split wears, repeating in order once all ten are taken.
  Until the first exercise is added, the list's place holds one line of
  guidance and a *Start from* card of rows (*Push day*, *Pull day*, *Leg day*,
  *Upper body*, *Lower body*, *Full body*; `lib/data/plan_starters.dart`). Each
  row names what it holds and trains (*6 exercises · Chest, shoulders, arms*,
  the busiest three muscle groups) beside a tonal plus. Each copies one day of
  a bundled hypertrophy preset (exercises, set and rep targets, and the
  preset's note) into the draft, folded so the whole workout shows at once,
  names the plan only when the name is still blank, and puts the keyboard
  away. A snackbar offers *Undo* for six seconds; it is withdrawn by any edit
  to the exercises (Undo would discard the edit too), by opening the exercise
  picker, by Save, and by leaving the editor, and it ignores a tap while it
  fades. It clears any snackbars queued before it, so it is always the one a
  withdrawal hides. The guidance has no ground of its own;
  only the tappable starters are raised.
- Save is a quiet pill until the plan has a name and an exercise, and the
  accent once it has both. Quiet, it is the app's secondary button (the
  control fill with primary ink, so it still reads as pressable), and it stays
  flat in every state. It never disables (except while
  saving): a tap on an incomplete plan names each gap where it is, *Name this
  plan to save it* under the name (which takes focus) and *Add at least one
  exercise to save* in the empty list, and each message clears as soon as its
  gap is filled. Screen readers hear what is missing as the button's hint.
- An exercise added to a plan starts with three sets (eight reps, or 30 seconds
  for a hold) at no target weight. In the plan's exercise picker, exercises
  already in the plan read *Added*, as in the workout, so a stray tap can't
  drop one along with its targets; removing stays with the card's Delete. When
  the picker closes on a plan that already had exercises, the editor scrolls
  the new ones into view, as many as fit and never past the first.
- The exercise picker (`lib/widgets/exercise_picker_sheet.dart`, shared by
  the plan editor and the workout) is a tall sheet with a drag handle, a
  search field, and pages that trade places along a horizontal axis: a fade
  and a 24px shift, arriving from the end side when going deeper (a group,
  the selected list, then search results) and from the start side going back.
  Typing more into a search does not replay it, and under reduced motion the
  page simply changes. Muscle groups open as two columns of illustrated
  cards on the control fill: the front and back body map
  (`MuscleGroupIllustration`) leads, then the name and *13 exercises*. The
  three rows grow to fill the sheet (an open keyboard doesn't shrink them; the
  grid scrolls instead), and two cards in a row always match in height. A group
  with selections takes the selected ground and an accent edge, reads
  *2 of 13 selected* in the accent, and ends its text with an accent count
  badge, kept off the figures. Under 360dp or at large text each group becomes
  a full-width row led by its primary figure, with the badge and a chevron at
  the end. Cards give slightly under the finger, except under reduced motion. A
  group's page keeps its small figure beside the name in the header. The footer
  says *Changes apply as you select.* above *Selected (N)* and *Done* (stacked
  at narrow widths and large text). Selected is the quiet secondary button at
  zero and turns tonal once anything is chosen, and its number rolls.
- Timed exercises use *Seconds* in editable set tables and the shared keypad,
  including History and set dialogs. Counts remain integer seconds in the
  existing reps field. Ordinary and custom exercises retain *Reps*. RPE uses
  the same editable cell treatment as weight and count, with an accessible
  label and optional value.
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
- Settings stays still while it saves: the progress banner waits
  `AppMotion.patience` and only then fades in over the top of the page, and
  out again (`PatientProgress`), so work that finishes at once never flashes
  it, and nothing under it moves. A switch whose description changes with it
  (the Coach's) crosses to the new line and eases the row to its new height,
  and the sync status, its *Retry*, and the update check's line cross to
  their next state. Under reduced motion each simply changes.
- Settings → Workout → *Weight unit* (Kilograms / Pounds, styled like the theme
  selector) sets `SettingsProvider.weightUnit` (`kg` or `lbs`, stored as
  `weight_unit`, backed up as `weightUnit`). **Storage is always kilograms**:
  Hive, sync rows, backups and the Coach's request and response never change.
  The unit only converts at the interface edge, and every conversion goes
  through `lib/utils/weight_units.dart`. The set table and keypad, the edit-set
  and add-set dialogs, the History edit screen, the plan editor previews, the
  desktop dashboard tiles and the Coach diff card show and accept the chosen
  unit; Stats, History, Workout details and the workout summary convert through
  `statistics_format.dart`. The keypad steps by ±2.5/±1 in kilograms and
  ±5/±2.5 in pounds (reps keep ±1). Values keep full precision in storage and
  are rounded only for display; retyping the figure a cell showed keeps the
  stored kilograms exactly, so opening a pounds cell never drifts a value.
- Settings → Workout → *Week starts on* (Monday / Sunday / Saturday, Monday by
  default) sets `SettingsProvider.weekStartsOn` (a `DateTime` weekday, stored
  as `week_starts_on`, backed up as `weekStartsOn`, optional so older backups
  still import). It decides every calendar week the app shows: Home's week
  strip (its letters start on that day), its totals and the plans' *Done*
  marks, the workout summary's weekly count, Stats' periods, weekly bars and
  heatmap rows, and the desktop dashboard. Every week goes through
  `startOfWeek(date, firstDay:)` in `lib/utils/format.dart`, whose `firstDay`
  has no default, and widgets read the day with `SettingsProvider.weekStartOf`.
  It does not touch the rotation: *Next up* is always the plan after the last
  one trained, so rest days need no setting.
- Appearance defaults to *System* on a new installation. An installation from
  before that default whose user never picked a theme keeps *Light*, so an
  update never changes how the app looks. `main` settles this before the first
  frame (`SettingsProvider.resolveStoredThemeMode`), using the first-run intro
  flag as the sign of an earlier install, and stores the answer.
  The sample is six weeks of a four-day upper/lower week (Upper A, Lower A,
  Upper B, Lower B): a finished four-week Hypertrophy block ending in a
  deload, then two weeks of a five-week Strength block. Today is the start of
  Strength week 3, lazily allocated, so every plan has Previous sets.
- Stats uses four persistent views: Overview, Strength, Blocks, and Records.
  Charts and figures sit directly on the page, without a vertical feed of
  panels. Overview pairs a weekly volume timeline with the selected week's
  workout, performed-set and rep totals, then a compact training-day calendar.
  It opens on the last complete week; the Home weekly shortcut selects the
  week in progress. Partial weeks are explicitly named and never compared with
  completed weeks. Exercise filtering applies to the plot and its totals; the
  calendar always shows all training in the active split. History browses
  horizontally, with an exact readout and accessible selection for every week.
  Strength shows one lift at a time, with a period selector, a measure picker,
  a selectable trend plot, change, and best in period. Its exercise picker
  opens the lift directory with sparklines in a sheet. The fixed time ranges
  (`4W`, `12W`, `6M`, `1Y`, `All`, spoken in full) use `SegmentedPills`;
  measure descriptions explain the calculation. Blocks opens on the block of
  the latest workout. A horizontally scrollable line chart compares Volume,
  Sets, Workouts, or Records across logged blocks in saved block order.
  Selection updates the readout and all detail below. The chart defaults to
  averages per trained week, with Block total available from the calculation
  control. A two-column totals layout replaces compressed metrics and repeated
  rate subtitles. Weekly bars reveal exact values on selection; strength gains
  expand to show their estimated-1RM endpoints. The page scrolls naturally so
  its chart, totals, weekly workload, and gains have room to breathe.
  Sessions belong to blocks through their training week. Records keeps the
  chronological, expandable achievements and reveals older entries on demand.
  Headline figures roll to a new value (`RollingFigure`): up when it grew,
  down when it fell, and plain under reduced motion. A view chosen with its
  tab or a swipe trades places with the last along the tabs' order, a fade
  and a 24px shift in the direction of travel; entering Stats from another
  tab or the Home shortcut shows the view without one. Charts appear with
  their screen and never grow in. The weekly bars ease to new heights when
  the exercise filter changes, and a week new to the plot grows from the
  baseline; the Strength and Blocks lines cross to a new lift, period, measure
  or basis rather than morphing between two different lines, while their
  readouts and figures land at once. Picking a block or a point moves the
  selection in place, and a selected week's bar eases its emphasis. Expanding
  gains, lifts and record tags folds open, and records revealed on demand
  arrive once. Signed changes use a true
  minus sign (`formatSignedChange`), and a change that rounds to zero has none.
  The four view controls remain visible while content scrolls; text can grow
  and scroll naturally on small screens. Returning to Stats resets its vertical
  offset. A lift whose sets in range are all at weight 0 falls back to its
  best reps in one set under the weight-based measures, and a timed lift
  shows its longest hold under every measure but sets; the measure label and
  values say so (`ProgressFallback`, helpers in `statistics_format.dart`).
  Derived values (eligible workouts, lift directory, records, weekly volume,
  lift summaries, blocks) are memoised on their inputs, so a rebuild of the
  hidden tab recomputes nothing, and records are worked out once and handed to
  `blockStatistics`. See [statistics design](docs/statistics-design.md) for
  references.
- Home's weekly strip gives each day a full 48dp target without gaps, so all
  seven fit a 390dp phone; each bar is a 16dp capsule centred in its target,
  so the strip reads as a chart rather than a row of tiles. A bar first
  appears at its height and grows or shrinks over `long` only when its day
  changes while Home is in view: a workout finished on the workout page, or
  another split's week, is simply there. Today is marked by its bold letter and a small accent
  dot under it, the same dot the workout uses for the week being trained now.
  The seven days are always drawn. An empty week is only the letters and
  today's dot, with the bars' slot closed so four of five plans still fit a
  phone; it opens as the first day is trained.
- Home's launcher is the one raised card on the page. A tap anywhere on it
  does what *Start workout* (or *Resume workout*) does, but only for a
  pointer: the button stays its single target for a screen reader or a
  keyboard, so the action is met once. It opens with the plan's own marker
  (`PlanMarker`, the mark its row in the list below carries) beside *Next
  up* (or *In progress*) and the rotation bar, the status on the marker's
  top edge and the bar on its bottom, so the three read as one mark. The bar draws one segment per plan in that plan's
  colour, and the plan on offer stands taller (6dp against 2dp, thin enough
  that five colours stay quieter than the name); height is its only
  emphasis, so it holds when plans share a colour or have none. The bar
  shows place in the rotation, not what was trained this week: the list's
  *Done* marks say that. The marker speaks “Workout N of M”, so the place
  is not also written out. The plan's name has the card's full width
  beneath, over the muscle groups it trains, in the picker's order (a plan
  of only custom exercises has no such line). Exercise and set counts are
  not repeated here: each plan's row in the list carries its own. Counts
  anywhere are dot-separated phrases (`PhraseLine`) that wrap only between
  phrases, so a count never parts from its unit. Each phrase is measured
  against the whole line before its dot; the dot follows only when both
  fit, so it never squeezes a phrase into breaking mid-word. The weekly summary keeps its
  “This week” label (set like *Your plans*) and Stats navigation affordance
  even before the first workout is logged.
- Plans on Home are flat rows on the page, ruled by hairlines; none rises
  into a second card. Each leads with its marker (`PlanMarker`): the plan's
  own resolved colour holding its number in `figures`, the same mark Manage's
  cards and the colour picker show, so the colour picked is the colour seen.
  The details line starts with where the plan stands: *Next* in accent ink,
  *In progress* while its workout is under way (the launcher then offers to
  resume that plan, and no other row claims to be next), or a success check
  and *Done* for a plan trained since the week began (Monday unless Settings
  says otherwise), so the list reads as the week's
  to-do list. A play glyph before *…* says what a tap on the row does: it
  opens that plan's workout, or for the row *In progress*, the live session
  itself, as *Resume workout* does, even when that session sits in an
  earlier week than the plan would open now. Past 150% text the glyph gives
  its width to the name and details. Screen readers hear the marker as “Workout N of
  M” and the plan's name once.
- Home's column stops at 680dp. Header, launcher, week and plans share that
  measure, each padded inside the cap, and so one left edge, so a tablet or the desktop rail centres a phone-
  and-a-half column instead of stretching Start the width of the screen. At
  large text on a phone the wordmark scales down to its 40% share of the
  header rather than being clipped.
- Plan names are shown with the first letter of each word raised
  (`titleCase`) and everything else as typed, so `PPL`, `RDL focus` and
  `(heavy week)` read `PPL`, `RDL Focus` and `(Heavy Week)`.
- Familiar labels and icons make actions understandable outside a technical
  audience.
- Pressed, focused, disabled, loading, empty, and error states should feel like
  parts of the same system.

Broad monospaced typography, square-bracket labels, and all-uppercase copy are
not part of the product identity. Figures that need to line up or hold their
width (Stats numbers and chart axes, record rows, the update status, the app
version, plan-editor rows) use `AppTypography.figures`: Manrope with tabular figures, so digits
align without a change of typeface. JetBrains Mono (`trainingData`) remains
only in a few compact training-data spots outside Stats, Settings and the
workout dialogs. The `>` symbol is reserved for the OpenGym wordmark rather
than used as a general interface decoration.

UI code should use theme helpers from `lib/theme/app_theme.dart` instead of
hardcoded black or white colors, and corner radii from `lib/theme/radii.dart`
instead of literal `BorderRadius` values. Radii are graduated by element size:
cards and dialogs are the roundest, while badges use a smaller radius, so the
same roundness reads correctly on a 148px card and a 20px badge. Retuning the
whole app means editing the six scale constants in that one file.

## Motion

Motion in OpenGym has four jobs, and nothing moves for any other reason:

- **Continuity**: where something came from or went. A page pushed or popped,
  a sheet rising, a region folding open, a card reordered.
- **Feedback**: a touch acknowledged. Ink on rows and buttons, a raised card
  giving under the finger.
- **Change**: a value that changed in place. A figure rolling, a segment thumb
  sliding, a loading state crossing to its content.
- **Arrival**: content appearing for the first time, once.

A motion that can't be justified in one sentence by one of these does not
exist. The rules that follow from that:

- Nothing waits on an animation. Content the user came for is laid out,
  tappable, findable and announced to screen readers from its first frame;
  only its opacity and transform move, and every animation can be
  interrupted. Leaving content stops taking taps as soon as it starts to go,
  and a dialog or sheet on its way out lets taps through to the page. Logging
  a set is the extreme case: it must feel instant.
- Arrivals decelerate on `AppMotion.curve`. Departures pass `AppMotion.exit`
  as the reverse curve of the animation that brought the thing in. Flutter
  evaluates a reverse curve against the same 0–1 value, so the leaving thing
  gives way at once and is mostly gone in the first half of its time: a
  departure reads shorter than its arrival, and leaves the way it came.
- Distances are small: lifts and shifts of 8 to 24px, and scale stays within
  about 0.96 to 1 (a press and a dialog use 0.97). The one longer travel
  follows a swipe: the workout's log is carried by the finger one to one, so
  when it switches plan the logs trade over a quarter of the width
  (`AppMotion.swipeShift`), the distance the hand began. A plan card picked up to
  drag, or an exercise held to be moved, lifts to 1.025 under a deepening
  shadow, the one scale above full size. A record badge earned just now is the one mark that pops in from
  nothing: it pops only as it is earned, never when the log opens with it or
  a card scrolls back into view. Staggering is rare: first
  appearance only, a handful of items at most, 40ms apart, and never replayed
  on a rebuild, on returning to a tab, or on coming back from a pushed route.
- Reduced motion (`MediaQuery.disableAnimationsOf`) makes every change
  immediate, page pushes included. Each primitive applies it itself; motion
  written directly wraps its duration in `AppMotion.of`. The exception is
  `AnimatedSize`, which asserts when a size change is given no time: under
  reduced motion leave it out of the tree, as `StateSwitcher` does, rather
  than passing it a zero duration.
- Work that finishes within `AppMotion.patience` shows no progress
  indicator (`PatientProgress`). The sign-in check, loading local data,
  Settings' saves and the workout's saves usually take a frame or two, and a
  spinner, banner or progress line that appeared and vanished that fast
  would only flicker, or shove the page. Its label is in the tree from the
  start. Shown in place, it is in the semantics tree from the start too, so
  only the painting waits; folded open as a region, it takes no room until it
  opens, and is announced as it does. Under reduced motion it still waits,
  then appears without motion.
- A change made while the screen is covered lands at rest. A covered
  screen's tickers are muted but its animations' clocks keep running, so a
  change made under a pushed page or on another tab would otherwise jump, or
  play part of the way, as the page leaves. Check
  `TickerMode.valuesOf(context).enabled` and skip the animation.
- Large subtrees move by opacity and transform through the `*Transition`
  widgets; layout animates only for a region's own size (`Collapsible`,
  `StateSwitcher(animateSize: true)`, `PatientProgress(fold: true)`). Nothing
  loops: no pulsing, breathing or shimmering, which would hang
  `pumpAndSettle` in tests and cost battery mid-workout. The two things that
  repeat do so only while they mean something: a progress indicator spins
  while work is actually in flight, and the keypad's caret blinks in the
  empty cell being typed into. Controllers are disposed.
- Platform conventions win over novelty. Android keeps its predictive back
  preview, iOS its edge swipe, and Material ink stays the touch response for
  rows, buttons and icon buttons.

### Tokens

`lib/theme/motion.dart` holds the whole vocabulary:

| Token | Value | For |
| --- | --- | --- |
| `AppMotion.quick` | 150ms | A state flip, a press, one state crossing to another |
| `AppMotion.standard` | 220ms | A region opening or closing, a track moving, a dialog arriving, a sheet leaving |
| `AppMotion.enter` | 280ms | An arrival, a sheet rising, a scroll the reader should follow |
| `AppMotion.long` | 400ms | A large move across much of the screen: chart bars growing to a new week, intro pages |
| `AppMotion.stagger` | 40ms | The gap between arrivals in one batch |
| `AppMotion.patience` | 300ms | How long work may run before a progress indicator shows |
| `AppMotion.curve` | ease out cubic | Arriving, settling at a new value |
| `AppMotion.move` | ease in-out cubic | Something already on screen travelling to another place on screen: an intro page turning, the tour spotlight, a plan card sliding to a new slot, a plan title flying into the workout header |
| `AppMotion.exit` | ease in cubic | The reverse curve for leaving |
| `AppMotion.lift` | 8px | How far an arrival rises into place |
| `AppMotion.shift` | 24px | How far a page travels sideways when it trades places with another (`PageSwitcher`) |
| `AppMotion.swipeShift(width)` | a quarter of the width, 72 to 144px | How far a page travels when a swipe trades it for another: the workout's plan switch |
| `AppMotion.scale` | 0.97 | A card giving under the finger, a dialog arriving |
| `AppMotion.settle` | critically damped spring | Content that tracked a gesture springing back to rest, or carrying on out at the hand's speed |

`AppMotion.of(context, duration)` returns the duration, or zero under reduced
motion.

`long` is the longest any one of the app's own motions runs; a staggered
batch only delays its later items, by a few `stagger` steps at most. The
platform's page transitions are exempt (Android's fade-forwards slide runs
450ms): they carry the back gestures, so the app keeps them as the platform
has them. An arrival on `curve` comes from nowhere and settles; a move on
`move` starts from rest as well, because what moves was already being looked
at.

### Primitives

`lib/widgets/motion/` holds the few widgets screens build motion from. Each one
handles reduced motion itself.

- `PressScale` (feedback) eases a tappable *object* to 0.97 while it is
  pressed. It follows the object's own `InkWell` through `onHighlightChanged`,
  so it waits out a scroll's touch slop as the ink does, adds no gesture
  recognizer, and can't swallow a tap, long press or drag. For raised cards and
  large tiles; `RaisedCard` applies it to every raised card with an action.
  Not for list rows, text buttons or icon buttons, whose response is ink.
- `Entrance` (arrival) fades a child in and lifts it 8px into place on its
  first build, with an optional `index` to stagger a batch (at most six steps).
  It plays once per `State`, so a rebuild, a tab return or a popped route never
  replays it. For content new to the screen, such as exercises added to a plan.
  Not for content that was already there, and not for items of a lazily built
  list, which are rebuilt when they scroll back.
- `Collapsible` (continuity) grows and fades a region open from the top, and
  folds it away and out of the tree when closed, so hidden controls hold no
  semantics. From the moment it starts to close it takes no taps, gives up
  keyboard focus and leaves the semantics tree, so a folding button can't be
  pressed and a folding field lets go of the keyboard; callers don't wrap it
  by hand. It starts at rest, so a region open on arrival is simply there,
  and it clips only while it moves (`FoldTransition`): a settled region lets a
  raised card's shadow fall outside it, where a `SizeTransition` would cut the
  shadow square.
  For expandable details, inline palettes and messages. Started open with
  `initiallyOpen` and closed, it folds a thing that has just gone out of its
  place and reports `onClosed` (a deleted set row).
- `StateSwitcher` (change) crosses one keyed state to the next in the same
  place over `quick`, stacking both so nothing jumps, and optionally easing
  the space they take to its new size (the size simply changes under reduced
  motion). The leaving state stops taking taps, gives up keyboard focus and
  leaves the semantics tree at once. For loading to content, empty to list,
  one label for another. Not for figures (use `RollingFigure`) or regions that
  open and close.
- `RollingFigure` (`lib/widgets/rolling_figure.dart`, change) rolls a
  headline figure up when it grew and down when it fell. It crosses over
  `enter`, not `quick` as `StateSwitcher` does, on purpose: the roll travels
  a line's height, and the eye has to follow it.
- `PageSwitcher` (continuity) trades one keyed page for another along a
  horizontal axis over `standard`: the arriving page slides the last `shift`
  into place from the end side going deeper and from the start side going
  back (mirrored under right-to-left), fading in from 30% of the way, while
  the leaving page clears out the other way in the first 35%. The arriving
  page is tappable and announced from its first frame; the leaving one takes
  no taps, focus or semantics. For the exercise picker's pages and Stats'
  views. `PageSwitchTransition` is the same trade driven by an animation of
  the caller's, for two pages that must both stay alive (the preset
  browser's catalog and details); its fade intervals are public, so the
  workout's plan switch, which trades two routes' logs and starts the leaving
  one from a swipe, keeps the same shape. Each page owns its scroll position: pages
  don't inherit the route's primary scroll controller, and a caller never
  hands both pages one controller; `OwnScrollController`
  (`lib/widgets/own_scroll_controller.dart`) gives each copy its own and
  hands the screen the newest, which History and the Coach use for lists
  that cross in a `StateSwitcher` too. Each page is built once per change.
- `SurfaceFade` (change) fades a whole surface in where it has replaced
  another, when its identity changes: from `SurfaceFade.floor` (0.4) to full
  over `quick`. What it replaced is gone at once, and the first frame already
  shows the new surface rather than the bare page, which a fade from zero
  would blink to (black, in dark mode). It plays only for a change the
  reader sees: not when disabled, under muted tickers (another tab, a pushed
  page), under reduced motion, or from or to a null identity (a first load).
  For the main tabs, Home's content changing split, and the auth gate's
  surfaces.
- `PatientProgress` (feedback) shows a progress indicator only for work
  still going after `patience`: fading it in place over `quick`, or with
  `fold` opening it as a region over `standard`. Done sooner, it leaves no
  trace; leaving, it keeps its last label and takes no taps or semantics.
  For the auth gate's spinners, Settings' banner and the workout's progress
  line.
- `showAppDialog` and `showAppSheet` (`app_modals.dart`) open every dialog
  and modal sheet; see below. `test/motion_test.dart` fails if `lib/` calls
  `showDialog` or `showModalBottomSheet` directly.

### Pages, dialogs and sheets

- Every push is a `MaterialPageRoute`, and `buildTheme` names each platform's
  transition rather than inheriting Material's defaults. Android uses the
  predictive back transition: a back swipe on Android 13+ previews the page
  underneath and can be cancelled, while a push or a tapped Back plays
  Android's fade-forwards slide. iOS and macOS use the Cupertino slide with
  edge-swipe back. Windows and Linux use Material's zoom, which suits a wide
  window better than a long slide. These transitions carry the back gestures,
  which is why the app keeps them instead of drawing its own; `PopScope`
  guards and the `PlanTitleHero` flight work under all three. Material paints
  the gap between two fading pages in the raised surface colour, which flashes
  grey in dark mode, so the app passes the page colour. Under reduced motion a
  push or pop lands at once, and a back swipe still follows the finger.
- There is no second route style for task flows. On iOS a full-screen-dialog
  route would lose edge-swipe back. The workout's plan switch is the one
  bespoke page route, and it trades only the log, as two pages of one book:
  the header, the plan tabs and the week bar hold still. The moment a plan
  is chosen (a swipe or a tab), the current log carries on out the way it
  was going, from wherever the finger left it and at the hand's speed (the
  `settle` spring, a `swipeShift` further), and clears out in the first 35%
  of the trade, before the save that must come first has finished. The
  chosen plan's workout is then pushed over it: opaque where it holds still,
  with a body that lets the replaced page show through until it has landed,
  so its log comes in over the old one from the other side, travelling
  `swipeShift` over `enter` on `curve` and fading in from 30% of the way,
  the shape of `PageSwitchTransition`. The two logs are never joined, so a
  save that takes a fifth of a second only delays the new log; work still
  going after `patience` shows the progress line, which stays in place. The
  title, plan marker and timer controls change in place on the new page, and
  the plan tabs' underline slides from the tab left to the one chosen over
  `standard` on `move`, the strip starting where the old one stood. A
  failed save pushes nothing, and the log springs back. Once the switch has
  landed it is an ordinary page, so its pop transition and back gestures are
  the platform's, and it lets go of the route it replaced.
- A dialog fades in while it settles from 0.97 to full size over `standard`,
  and leaves with a plain fade on `exit`. `showDialog` takes one duration for
  both directions, so the exit is shorter in effect rather than in time. The
  date and time pickers open Material's own dialogs and keep its 150ms fade.
- A modal sheet keeps the platform's slide from the bottom edge: it rises over
  `enter` and drops away over `standard`, and dragging it follows the finger.
  The exercise picker, pushed as its own sheet route, takes the same timing
  through `appSheetAnimationStyle`.
- Popup menus keep Material's reveal from their anchor, which is continuity
  already and can't be retimed from the theme. Snackbars keep Material's
  motion. The floating notice keeps its own shape, a short drop from above
  while it settles from 0.97, on the app's timing: in over `enter` and out
  over `standard` on `exit`, and a notice on its way out takes no taps.
- The workout's block menu is a small popup route anchored above the block
  button, so Back and an outside tap close it like any menu. It moves as a
  dialog does: it fades in while it settles from 0.97 to full size out of the
  button's start edge over `standard`, and leaves with a plain fade at full
  size on `exit`.
- The split menu is a `MenuAnchor` overlay with no transition that can be put
  on the tokens. It settles out of the split name like a dialog (a fade and
  0.97 to full size over `standard`) and closes at once.

### What does not animate

- The workout's set entry. Values land as they are typed, and a logged or
  added set is simply there. The keypad slides in once when entry starts, the
  active cell's wash eases across, and the table keeps the active row in
  view, but nothing moves between keystrokes except the record badge's pop,
  which never delays the next entry. A set deleted from its hold menu is the
  one row that moves: it folds away so the rows below rise into its place.
  Ink and haptics carry the feedback.
- Changing week in the workout. The log swaps as tab content does while the
  tab underline eases, and the header's timer controls and clock change in
  place.
- Content that was already there. A plan's own exercises when its editor
  opens, a list loaded with its screen and the History ledger appear without
  an arrival: staggering a screen's content on every visit is decoration.
- Returning to anything. Coming back to a tab or from a pushed route replays
  no arrival, roll or chart growth, and entering Stats shows its view without
  the sideways swap that changing views inside it uses. The resume strip, and
  Home's week bars, are simply as they now are if they changed out of view.
- Charts on first appearance. Bars ease only to new values for the same
  weeks; a line shown for another lift, period or measure crosses to the new
  one rather than morphing through values nobody logged, and its readouts
  land at once.
- Surfaces the auth gate replaces. Login, recovery and the app fade in on the
  page colour, but what they replace is removed at once and never crosses
  beneath them, so the previous account's screens never linger.
- Search results. Typing into a search filters the list in place; rows don't
  arrive or leave, and a merged or renamed exercise simply takes its new
  place in Manage exercises.
- Main tabs. They change with a brief fade and no slide: they are peers, not a
  stack, and swiping between them is navigation, not a carousel.
- Rows, text buttons and icon buttons do not scale; ink is their response.
- Figures below the headline. Only headline figures roll; the rest change in
  place, and the workout summary shows final values at once so Share always
  exports the right totals.
- Scroll jumps under reduced motion, and everything else in this section.

## Backup And Import

`BackupService` exports format v6: exercise definitions and merge redirects, all splits/plans/sessions, intended block
lengths, allocated weeks, each plan's available/active weeks, settings and
source-account provenance. Imports validate the complete graph before replacing
local data. Versions 1–5 reuse exercise identity migration; versions 1–4 also normalize
training structure. Unsupported future versions and v6 backups missing exercise
IDs/definitions fail explicitly, as do v5+ backups missing duration/availability.

Same-account restore preserves training identities unless live restored rows
would resurrect known tombstones. Resurrection cases copy the training graph to
new identities, including progress and completion references. Restoring a
shorter schedule or removing a lazy slot also uses new training identities, so
its next deterministic week ID cannot be stranded behind a deletion marker.
Account-wide exercise identities remain stable in all of these same-account
structural copies, preserving saved merges. Foreign/unknown-provenance imports
copy the training graph and explicitly remap custom definitions, occurrences,
and all redirect target IDs together, including targets whose metadata has not
arrived. Activation state is never copied. Restores tombstone omitted records
and use the same recoverable replacement writer as installers.

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
