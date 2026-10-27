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
- Weeks expand **inline beside their block** in the horizontal bottom bar.
- Opening the workout screen automatically expands the block containing that
  workout's active week.
- Opening and closing blocks uses a **simple animation**.
- Only **one block can stay expanded** at a time. Opening another block
  automatically collapses the previously expanded block.
- Progress through the **user-provided weeks** in the current block. After
  completing the last provided week, **on the next opening** ask the user to
  add a week to the current block or move to the next block. Do not automatically
  create an extra week or move across the block boundary.
- Progression is **independent per workout**. Missing one workout must not stop
  another from advancing through its provided weeks. Blocks and weeks remain
  shared structure; workouts can have different active weeks or active blocks.
- New blocks inherit workout values from the **matching week of the previous
  block**: Week 1 from Week 1, Week 2 from Week 2, and so on, for the same workout.
- At the block boundary, offer **Add week** and **Move to next block** when a
  next block exists, or **Add week** and **Create block** when none exists.
- Archive completed blocks to preserve their logs in History, records, and
  statistics. Detailed deletion and archive eligibility rules remain open.
- Migrate all existing weeks/logs into **one initial block per split**, preserving
  their week numbers and data.
- Expose block management through **long-pressing a block** in the workout
  screen's bottom navigation.
- A missed or unlogged workout **stays on the same week with its values intact**.
  If Week 2 is missed, the next workout visit still opens Week 2, even if another
  calendar week has passed. Advance only when the workout is logged/completed.
- When a workout is added midway through training, let the user **choose its
  starting block and week**.
- Do **not** add a Skip week action or a dedicated skipping feature.

A split could contain Block 1 with Weeks 1–4 and Block 2 with Weeks 1–3.
Push and Pull both use those same seven training-week slots. Their sessions
remain separate: Push in Block 2, Week 1 is different from Pull in that slot.

These are training-week labels. Within-block progression follows the provided
weeks independently for each workout and advances on logging/completion.
Crossing a block boundary requires a user choice for that workout. Calendar
time, opening the screen, and leaving it unlogged do not advance a week.

## Initial UI direction

The current bottom strip is a flat list of weeks plus an Add week action.
Replace that mental model with named block groups that reveal their weeks.
Keep this navigation compact enough to leave the set logger usable.

Confirmed layout and opening behavior:

- Each block reveals its weeks inline beside its label in the same horizontal
  bar. The next block follows the revealed weeks.
- On opening the workout screen, resolve the workout's active week and expand
  its containing block. Make that active week visible in the scrollable strip.
- Opening a different block collapses the previously expanded block as the new
  block expands. Multiple blocks cannot remain expanded together.
- Animate expansion and collapse simply, revealing or hiding the weeks while
  adjacent items move smoothly. Exact timing and easing remain design details;
  respect the platform's reduced-motion preference.
- Long-pressing a block opens its management actions, including access to
  creating, renaming, reordering, and archiving blocks. Exact labels and the
  presentation of these actions are still to be designed.

Suggested interaction rules, still open to discussion:

- Tapping a block toggles its expansion. Tapping a week changes the selected
  block/week and loads the corresponding session for the current workout.
- Expanding or collapsing alone does not change the loaded session. Collapsing
  the selected block must still leave its selection recognizable.
- Keep block and week visually distinguishable. Repeated labels such as
  Week 1 need their block context in the workout heading and accessibility labels.
- Put Add week within a particular block. Block management is reached through
  the confirmed long-press menu; the boundary prompt also exposes Create block
  when appropriate. Explain that structural changes affect the shared split.
- Changing workouts must respect their independent progress. The treatment of
  a manually browsed week during a workout switch remains open. Preserve the
  current save-before-navigation and timer behavior.
- Support many blocks, long names, small phones, large text, and a visible
  selection after scrolling. Follow existing theme, radius, and typography tokens.

The inline arrangement is confirmed. Detailed styling and animation have not
been mocked up or approved. Opening a block for browsing must not implicitly
advance training. The progression behavior below guides active-week selection;
manual browsing behavior during workout switches still needs to be settled.

## Week progression and the end of a block

Confirmed behavior:

- Use the weeks the user has already supplied, in order. Finishing a week
  advances to the next provided week while one remains in the current block.
- Completion and advancement are tracked for each workout independently.
  Finishing Push Week 1 can advance Push to Week 2 while Pull and Legs remain
  on Week 1. No workout has to wait for the others to catch up.
- A missed or unlogged workout stays on its current week. Week 2 left unlogged
  opens as Week 2 again on the next visit, preserving its saved values and draft.
  This also applies to the final provided week: keep it active until completed,
  then offer the boundary choices on the following visit.
- There is no separate Skip week button or skipping workflow. Missing a day or
  leaving the screen does not advance progress or require missed-visit tracking.
- Adding a new workout lets the user choose its starting block and week within
  the shared structure, rather than forcing it to match another workout's place.
- Finishing the final provided week does not silently append another week or
  enter another block. On the next opening of the workout, ask the user to
  choose **Add week** or **Move to next block** if a next block exists. If none
  exists, offer **Add week** or **Create block** instead.
- Add week extends the current block's shared week structure. Move to next
  block advances only the workout making that choice; other workouts keep their
  own place. This is an explicit progression choice, rather than merely
  expanding a different block to browse its weeks.
- The boundary prompt is for the next visit; completing the final workout
  should not force an immediate decision about what comes next.

For a block configured with Weeks 1–4, progression uses those four weeks. After
Week 4 is finished, the next visit offers adding Week 5 to that block or moving
to the next block. It does not generate Week 5 merely because the screen opens.

The reason for independent progression is to accommodate missed workouts without
blocking the rest of the split. An unperformed workout must not be treated as
completed merely because another workout advanced. Block completion is therefore
relative to the workout, rather than one global completion flag for the split.

Suggested edge-case behavior, not yet approved: extending an earlier block
should not automatically pull workouts that already moved on back into it.
Likewise, viewing or editing an old log should not rewind training progress.

Still to decide: what dismissing the boundary prompt does and how manually
browsing a different week interacts with workout switching. Unfinished workouts
remain on the same active week with their saved values; existing timer and
draft-restoration behavior should be preserved.
The storage design must distinguish the shared block/week structure, training
progress, and the block/week currently being browsed. No opened/left-unlogged
visit metadata is needed for progression. Whether progress is derived from
completed logs or persisted explicitly has not been chosen.

## Starting values in later blocks

The confirmed source is the same workout's matching week in the previous block.
For example, Push in Block 2 Week 1 starts with Push's Block 1 Week 1 values;
Push in Block 2 Week 2 starts with Push's Block 1 Week 2 values. It does not use
Block 1's final week as the source for every new week.

This is initialization of editable workout values, rather than a separate
block-specific prescription system. Existing saved destination sessions must
not be overwritten by reapplying inheritance. The destination remains a fresh
workout with its own identity, completion, date, and timer lifecycle; copying
training values does not copy a historical workout's completed status.

Missing a workout does not copy values into a different week. Resume the same
week and preserve its saved values and draft instead.

Still to decide: the fallback when the previous block has no matching week or
no saved session for that workout, how changed exercises are matched, and when
values are captured if the source log is later edited. The first block has no
previous block and needs its own initialization rule.

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
  unambiguous selection. Replace automatic next-week creation with progression
  through provided weeks and the next-visit block-boundary prompt. Opening Push
  must not silently add a week to every workout in the split.
- **Session lookup and edits:** use plan IDs and training-week identity for new
  paths. Keep deliberate legacy fallbacks for unresolved old records. Shared
  week rename/delete operations have a wider effect than today's per-plan actions.
- **Initialization and previous sets:** initialize later-block workout values
  from the previous block's matching week for the same workout. Define missing
  source fallbacks, exercise matching, and first-block behavior. Distinguish
  these starting values from any most-recent-set reference shown in the UI.
  Do not let raw week-number sorting compare unrelated Week 1s. Existing saved
  sessions must take priority over initialization rules.
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

Confirmed migration: put existing training weeks into one initial block per split,
preserving their numbers. Use the union of known session week numbers across
that split; Push Week 3 and Pull Week 3 would map to the same shared week.
Old per-plan week counters may have been used independently and may not represent
the same calendar period; independent workout progression remains intact.

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
  Archiving completed blocks while preserving History, records, and statistics
  is confirmed. Exact deletion semantics and archive eligibility remain product
  decisions and must align locally and on the server. In particular, one workout
  finishing a block does not mean every workout has finished that shared block.

## Questions still open

1. What are the details of the long-press management menu: naming, reordering,
   optional duplication, and whether a newly created block remains planned or
   becomes active immediately? A dedicated Skip week action is excluded.
2. If a week is added to a block after some workouts have moved on, should those
   workouts simply retain their current progress as suggested above?
3. How do manually viewed weeks interact with the progression-selected active
   week? Does switching workouts resume that
   workout's active week or retain the week being browsed? At the boundary
   prompt, what happens if the user dismisses it?
4. What initializes the first block or a week with no matching previous-block
   session? How are changed exercises matched, and when are source values copied?
5. What happens when deleting a shared week containing logs from several workouts?
   When can a shared block be archived if some workouts still have active weeks
   in it, and how can archived blocks be accessed or restored?
6. Can the same workout be performed twice in one training week? Existing data
   can contain multiple sessions, while the workout screen normally selects one.
7. What should a brand-new split or newly installed preset start with, and how
   should its initial block be named?

## Suggested next steps and future acceptance criteria

Continue the product discussion, then agree on navigation behavior and lifecycle
rules before choosing a schema. A later implementation plan should sequence
storage/compatibility, shared state, navigation, and secondary surfaces.

Future verification should cover empty planned weeks surviving restart and sync;
identical block/week structure across all plans; distinct sessions for repeated
Week 1s; automatic expansion of the active week's block on screen entry; inline
expand/collapse animation with at most one block expanded; safe autosave/timer
navigation; independent progression through only the supplied weeks without
requiring other workouts to finish; an end-of-block choice on the next visit
without automatically adding a week or changing blocks; a Create block option
when no next block exists; matching-week value inheritance across blocks;
keeping missed/unlogged workouts on the same week with their saved values and
drafts intact across visits and restarts; advancing only on logging/completion;
user-selected starting block/week for a newly added workout;
no dedicated skipping feature;
previous-set behavior at block boundaries;
old-backup upgrades into one initial block per split; interrupted and multi-device
migration; account isolation; long-press block management; and archive/delete
behavior without accidental history loss.

When implementation begins, update [DESIGN.md](../../DESIGN.md) and
[split documentation](../splits.md) to describe the resulting shipped behavior,
regenerate any changed Hive adapters, run `flutter analyze`, and run relevant
storage, sync, backup, lifecycle, and navigation tests. Those steps are not being
executed during this discussion session.
