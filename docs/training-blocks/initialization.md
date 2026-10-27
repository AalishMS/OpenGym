# Training blocks: feature initialization

Started: 2026-10-27

Status: discovery and discussion; implementation has not started

Branch: `feature/training-blocks`

## Intent and session boundaries

Introduce training blocks that contain weeks, with expandable and collapsible
blocks in the workout screen's bottom week navigation. This is the starting
point for a larger feature, rather than an approved implementation specification.

This session is for brainstorming and inspecting the existing architecture.
Only the branch and this documentation are being created. App code, Hive
adapters, database migrations, builds, tests, and app execution are outside
the scope of this session.

## Decisions confirmed with the user

- Blocks belong to the **split**, shared across all its workout plans. Push,
  Pull, and Legs see the same blocks and weeks.
- The first version **organizes weeks**. Different exercises, sets, reps, and
  targets per block are outside this initial version; existing plan templates
  continue to apply. Normal logging and editing of performed sets remain.
- Week numbering **restarts at Week 1 in each block**.
- Block creation supports **both** choosing a week count upfront and adding
  more weeks later. A block's initial length is not necessarily a permanent cap.
- The bottom navigation contains expandable/collapsible blocks. Tapping a
  block reveals its weeks; selecting a week opens that workout's session.

A split could contain Block 1 with Weeks 1–4 and Block 2 with Weeks 1–3.
Push and Pull both use those same seven training-week slots. Their sessions
remain separate: Push in Block 2, Week 1 is different from Pull in that slot.

These are training-week labels. Calendar dates, automatic advancement, and
completion rules have not been decided.

## Initial UI direction

The current bottom strip is a flat list of weeks plus an Add week action.
Replace that mental model with named block groups that reveal their weeks.
Keep this navigation compact enough to leave the set logger usable.

Suggested interaction rules, still open to discussion:

- Tapping a block toggles its expansion. Tapping a week changes the selected
  block/week and loads the corresponding session for the current workout.
- Expanding or collapsing alone does not change the loaded session. Collapsing
  the selected block must still leave its selection recognizable.
- Start with the selected block expanded. Consider allowing only one expanded
  block at a time if several expanded groups make the bar hard to navigate.
- Keep block and week visually distinguishable. Repeated labels such as
  Week 1 need their block context in the workout heading and accessibility labels.
- Put Add week within a particular block and provide a separate New block
  action. Both affect the shared split structure, which their copy should explain.
- Changing workouts should retain the selected block/week where possible.
  Preserve the current save-before-navigation and timer behavior.
- Support many blocks, long names, small phones, large text, and a visible
  selection after scrolling. Follow existing theme, radius, and typography tokens.

The exact layout is undecided: weeks could expand inline inside the horizontal
strip or appear in a second row associated with the expanded block. No mockup
or final layout has been approved.

## What the app stores today

Findings below come from the repository at initialization, not a live database
inspection. See [DESIGN.md](../../DESIGN.md) and [split workspaces](../splits.md).

- [WorkoutPlan](../../lib/models/workout_plan.dart) has a stable ID, split ID,
  exercises and targets, color, and ordering. It has no blocks or week records.
- [WorkoutSession](../../lib/models/workout_session.dart) stores `weekNumber`,
  `planId`, `planName`, `splitId`, performed exercises, completion, and timer
  state. It has no block reference or separate training-week identity.
- [HiveService](../../lib/services/hive_service.dart) opens four boxes: plans,
  sessions, splits, and split preferences. There is no block or week box.
- `getWeeksForPlan` derives numbers from saved sessions for one plan. Week
  lookup, rename, and deletion helpers use plan name, split, and week number.
  Sessions already have IDs, but those helpers do not consistently use plan IDs.
- [WorkoutScreen](../../lib/screens/workout_screen.dart) keeps a list of integer
  weeks and a session cache keyed by integer week number. Empty tabs can exist
  only in screen state. On opening, it selects a draft or adds a next-week tab
  from that workout's saved weeks.
- [WorkoutSessionInitializer](../../lib/services/workout_session_initializer.dart)
  seeds Week 1 from plan targets; later weeks copy the previous session when
  available. The screen finds that previous session using `weekNumber - 1`.
- [Previous-set lookup](../../lib/utils/set_history.dart) can filter and sort
  by week number. Repeated numbers across blocks would make this ambiguous.
- [SyncService](../../lib/services/sync_service.dart) syncs splits, preferences,
  plans, and sessions using timestamps, dirty flags, tombstones, and per-table
  cursors. Sessions have a promoted `week_number` column plus a JSON payload.
- [BackupService](../../lib/services/backup_service.dart) currently exports
  format version 3 with splits, plans, sessions, active split, and settings.

Consequently, this needs persisted structure as well as UI work. A block with
four planned but unlogged weeks must survive restart, backup, and sync without
creating four fake workout sessions for every plan.

## Proposed data direction — not a finalized schema

Keep Hive as the source of truth and preserve the split as the workspace
boundary. Model shared blocks and their weeks separately from performed logs.

1. A training block has a stable ID, its split ID, a display name, explicit
   order, and the usual ownership/sync metadata.
2. A training week has a stable ID, its owning block, explicit order, and a
   displayed number within that block. Whether it is a standalone record or
   embedded in the block is a design decision still to make.
3. A workout session references its training week while retaining its session
   ID, plan ID, split ID, dates, logged sets, and timer/completion information.
   Its block may be derived through the week or stored with consistency checks.
4. A plan remains owned by the split in this first version. There is no need
   to duplicate every plan for every block merely to group its sessions.

Record IDs must not depend on names, displayed week numbers, or list positions.
Renaming/reordering should not disconnect a log. The navigation destination is
the plan plus its training-week identity; the log itself retains its session ID.
Do not assume a database uniqueness rule until repeat-workout behavior is decided.

For example, Block 1's Week 1 and Block 2's Week 1 have different week IDs.
Changing a block's name does not change either identity. A week may exist with
no logs, one workout logged, or several different workouts logged.

Storage alternatives to evaluate:

- **Separate block and week records:** independent sync/edit units and clearer
  relationships, with more boxes/tables, ordering, and migration work.
- **Weeks embedded in block records:** fewer records and simpler reads, but
  concurrent edits to different weeks can overwrite each other under the current
  whole-row last-write-wins strategy. Session references still need validation.

Do not choose the aggregate boundary solely to minimize table count. Both
approaches must preserve stable week identity, offline edits, and deletion rules.

## Changes to assess before implementation

- **Local storage and models:** new persisted block/week structure, adapters,
  serialization, split-scoped CRUD, stable ordering, session references, and
  migration flags. Preserve existing Hive field indices and type IDs; allocate
  new ones without collisions and regenerate adapters when implementation begins.
- **Workout navigation and providers:** stop deriving the shared week structure
  from one plan's sessions. Replace integer-only caches and route arguments with
  unambiguous selection. Revisit automatic next-week creation so opening Push
  does not silently add a week to every workout in the split.
- **Session lookup and edits:** use plan IDs and training-week identity for new
  paths. Keep deliberate legacy fallbacks for unresolved old records. Shared
  week rename/delete operations have a wider effect than today's per-plan actions.
- **Initialization and previous sets:** define a new block's first-week source,
  within-block previous-week lookup, skipped-week behavior, and whether references
  may cross block boundaries. Do not let raw week-number sorting compare unrelated
  Week 1s. Existing saved sessions must take priority over initialization rules.
- **Cloud sync and Supabase:** extend the aggregate payloads or add tables as
  chosen; review promoted columns, owner/split consistency, foreign keys, RLS,
  indexes, update sequencing, and cursors. Push parents before dependent sessions;
  define tombstone propagation for block/week/split deletion. JSON support alone
  does not settle relationship integrity or older-client compatibility.
- **Backup/import:** introduce a new format version when the schema is settled,
  export empty structure as well as logs, validate references, and upgrade older
  backups without losing sessions. Update the restore callers as well as serializers.
- **Data lifecycle:** include new records in account adoption, account switching,
  cache clearing, split deletion, Clear All Data, sample-data replacement, and
  preset installation/rollback. Decide which actions preserve empty block profiles.
- **Other screens and integrations:** add block context where repeated week labels
  would confuse History, workout details, Home resume, and timer notifications.
  Keep exact-session notification routing. Review previous-set suggestions,
  records, statistics, preset defaults, and Coach context/apply behavior.

Calendar-based analytics can continue to use logged dates and completed sessions.
Grouping by blocks would be an additional view, not a replacement for those dates.
Plan-level Coach edits need an explicit scope so users understand that the shared
template can affect future workouts in multiple blocks.

## Migration and compatibility principles

Proposed default: put existing training weeks into one initial block per split,
preserving their numbers. Use the union of known session week numbers across
that split; Push Week 3 and Pull Week 3 would map to the same shared week.
This is a migration assumption to confirm: old per-plan week counters may have
been used independently and may not represent the same training period.

- Preserve every session's ID, date, exercise data, completion state, and timers.
  Keep orphaned history whose original plan no longer exists.
- Preserve numbering gaps initially. Do not silently renumber old Week 12 as
  Week 1 or guess historical block boundaries from dates.
- Define a usable initial block/week for empty splits. Empty tabs held only in
  current screen memory cannot be recovered from old persisted data.
- Make upgrades resumable and idempotent, with a safety backup before rewriting
  links. Two offline devices upgrading the same split must converge on the same
  initial block/week identities, or use a server-coordinated equivalent.
- Cover legacy sessions pulled after local migration and backups imported later.
  Missing new fields need an explicit compatibility path.
- Prevent an old app version from overwriting or dropping new structure during
  sync. Decide on version gating, a compatibility bridge, or a supported upgrade
  boundary before rollout; nullable fields alone are insufficient protection.
- Keep historical logs reachable when a block/week is archived or removed.
  Archiving is a suggested default for used blocks; exact deletion semantics
  remain a product decision and must align locally and on the server.

## Questions still open

1. Do weeks expand inline in the bottom strip or in a separate row? Can several
   blocks stay expanded at once?
2. How are block names, ordering, duplication, and archiving managed? Where does
   New block live, and does it open immediately or remain planned for later?
3. Are training weeks freely selected, manually advanced, or advanced after a
   completion rule? What happens when a workout is skipped or a plan is added?
4. Does switching workouts retain the viewed week even when another week has an
   unfinished session? How should browsing differ from the active training slot?
5. At a block boundary, should Week 1 use plan targets, the previous block's
   final workout, or a user choice? This need not introduce block-specific targets.
6. What happens when deleting a shared week containing logs from several workouts?
   Can a block be archived without affecting History, records, or statistics?
7. Can the same workout be performed twice in one training week? Existing data
   can contain multiple sessions, while the workout screen normally selects one.
8. Is the proposed mapping of existing per-plan weeks into one shared initial
   block acceptable, or should users choose how to organize their old training?
9. What should a brand-new split or newly installed preset start with, and how
   should its initial block be named?

## Suggested next steps and future acceptance criteria

Continue the product discussion, then agree on navigation behavior and lifecycle
rules before choosing a schema. A later implementation plan should sequence
storage/compatibility, shared state, navigation, and secondary surfaces.

Future verification should cover empty planned weeks surviving restart and sync;
identical block/week structure across all plans; distinct sessions for repeated
Week 1s; safe autosave/timer navigation; previous-set behavior at block boundaries;
old-backup upgrades; interrupted and multi-device migration; account isolation;
and archive/delete behavior without accidental history loss.

When implementation begins, update [DESIGN.md](../../DESIGN.md) and
[split documentation](../splits.md) to describe the resulting shipped behavior,
regenerate any changed Hive adapters, run `flutter analyze`, and run relevant
storage, sync, backup, lifecycle, and navigation tests. Those steps are not being
executed during this discussion session.
