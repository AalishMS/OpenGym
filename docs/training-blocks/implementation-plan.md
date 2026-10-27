# Training blocks: implementation plan

Date: 2026-10-27

Branch: `feature/training-blocks`

Repository baseline: `6b0e27c` (`docs: keep unlogged workouts on their current week`)

Status: proposed implementation plan; no application implementation authorized

## Authority and scope

[initialization.md](initialization.md) is the product source of truth. This plan
also follows [AGENTS.md](../../AGENTS.md), [DESIGN.md](../../DESIGN.md),
[split workspaces](../splits.md), and the relevant Coach contract in
[docs/coach.md](../coach.md). Repository findings below describe this commit,
not a verified live database schema.

**Agreed** means confirmed behavior in initialization.md and the latest brief.
**Recommended** means an implementation or product default proposed here, still
subject to acceptance. **Unresolved** means a decision remains open. Phase 0
identifies which decisions actually block dependent implementation or rollout.

This deliverable is documentation only. No Flutter, analyzer, build, test,
adapter generation, database access, migration execution, deployment, PR, or push
is part of this session. All commands and application changes mentioned below
are future work. Do not change DESIGN.md or initialization.md in this session.

## Agreed product contract

- A split owns shared blocks and planned weeks. Every workout plan in the split
  sees the same structure; each workout progresses independently.
- Weeks restart at 1 in each new block. A week has durable identity independent
  of its label, number, or order. Preserve existing numbering, including gaps,
  when migrating the initial block.
- Creating a block accepts an upfront week count; Add week can extend it later.
  Empty planned weeks persist without manufacturing performed sessions.
- The horizontal bottom navigation expands weeks inline beside their block.
  At most one block is expanded. Entering a workout expands its active week's
  block and scrolls that week into view. Use a simple expansion animation.
- Long-pressing a block opens block management, including access to creation,
  naming, reordering, and archiving. Detailed presentation remains open.
- Logging/completing advances that workout through the supplied weeks. Opening,
  leaving, elapsed calendar time, and another workout's completion do not.
  An unlogged Week 2 returns as Week 2, with its saved values/draft intact,
  even the following calendar week. There is no missed-visit metadata,
  calendar/schedule detection, Skip week action, or dedicated skipping feature.
- Completing the final provided week leaves the decision until the **next
  visit**. Offer Add week / Move to next block when a next block exists;
  otherwise Add week / Create block. Do not append or cross automatically.
- Later-block values inherit from the same workout's matching week in the
  previous block: B2/W1 from B1/W1, B2/W2 from B1/W2. Existing destination
  sessions always win. First-block and missing-source rules are not agreed.
- Adding a workout lets the user choose its starting block and week.
- Archive completed blocks without losing History, records, or statistics.
  Archive eligibility and detailed deletion rules are not agreed.
- Upgrade existing data into one initial block per split, preserving session
  IDs, week numbers, dates, sets, completion, and timers, including orphaned
  and duplicate historical logs.
- V1 groups weeks. Plans remain split-wide prescription templates; do not add
  block-specific exercises, targets, plan copies, or prescription versions.

## Repository findings and change map

| Existing path | Relevant behavior and required integration |
| --- | --- |
| `lib/models/workout_session.dart` | Hive type 4; fields 0–14 include integer `weekNumber`, optional `planId`/`splitId`, stable session ID, draft/completion and timer data. Add links without repurposing fields. |
| `lib/models/workout_plan.dart` | Hive type 3; fields through 10, with field 3 deliberately unused. Stable plan ID, shared template and display order. Do not create one plan per block. |
| `lib/models/split.dart`, `lib/models/split_preference.dart` | Types 6 and 7; split ownership and account-level active selection. Existing registered model types occupy 0–7. |
| `lib/services/hive_service.dart` | Four boxes; ID-key migration, `ensureSplitWorkspace`, dirty/raw accessors, replacement and tombstone helpers. `getSessionsForPlan`, `getWeeksForPlan`, `getSessionForPlanAndWeek`, `renameSessionWeek`, and `deleteSessionForPlanAndWeek` still use names/numbers. The comment “now id-based” above week helpers does not make their lookup identity safe. |
| `lib/screens/workout_screen.dart` | `_loadWeeks` derives per-plan integer tabs and appends max+1 on opening without a draft. `_weekSessions` is keyed by integer; restoration, initializer, previous-set lookup, widget keys, rename/delete, and `initialWeekNumber` share that assumption. Save revisions and `_saveBeforeNavigation` already guard edits. |
| `lib/services/workout_session_initializer.dart` | Existing destination wins; Week 1 seeds plan targets; later weeks copy the previous session wholesale or use zeroed sets. Matching-week inheritance needs explicit source resolution. |
| `lib/services/workout_completion_service.dart` | Completes a started draft in one session upsert, stops its timer, and checks PRs against completed history excluding itself. Preserve retry behavior; add recoverable progression after the completion write. |
| `lib/providers/workout_session_provider.dart`, `lib/providers/workout_plan_provider.dart`, `lib/providers/split_provider.dart` | Provider/ChangeNotifier, split listeners, local writes then sync. Session provider exposes completed sessions; shared structure cannot be inferred from that list. Split provider listens to sync changes and triggers dependent reloads. |
| `lib/main.dart`, `lib/auth/auth_gate.dart` | Hive/Supabase startup, local account preparation, providers, account-specific Navigator replacement. New state must prepare before display and reset on handover. Offline-only builds also need block migration. |
| `lib/services/sync_service.dart` | Split/preference pull before bootstrap; live parents push before plans/sessions, deleted splits last; whole-row last-write-wins, per-table cursors and exclusive local mutation helper. Current pushes stamp the signed-in owner; do not extend that practice to arbitrary foreign rows. |
| `supabase/migrations/20260904060853_add_split_scoped_workspaces.sql` | Composite split/owner FKs, RLS, grants, sequence trigger, legacy split assignment and split tombstone cascade. Following `20260904061059_fix_split_tombstone_cascade.sql`, `20260904061229_complete_split_access_and_indexes.sql`, `20260904061315_tighten_workout_table_grants.sql` amend behavior. Initial base plan/session table creation is not in this migration set; audit it in a future isolated environment before asserting constraints. |
| `lib/services/backup_service.dart`, `lib/screens/settings_screen.dart` | Backup version 3; versions 1–2 collapse into My Split. Settings explicitly supplies exports and passes validated imports to `replaceAllWorkoutData`, then reloads providers. Updating JSON alone is insufficient. |
| `lib/services/adopt_local_data.dart` | First-account adoption; different-user cache clearing and four cursor resets. New boxes, journals, safety backups, and cursor keys must join this lifecycle. |
| `lib/services/workout_preset_installer.dart`, `lib/services/split_install_target.dart`, `lib/services/sample_data_seeder.dart` | Preset and Coach new-split installation share target preparation/rollback. Sample data creates historical numbered sessions; split clearing and all-data helpers currently operate on plans/sessions. |
| `lib/app_shell.dart`, `lib/navigation/app_navigation_observer.dart` | Timer opens and route reuse target exact session IDs, wait behind modals and autosaves, and recheck deferred destinations. Keep these guarantees. |
| `lib/services/workout_timer_notification_service.dart`, `android/app/src/main/kotlin/com/aalishms/opengym/WorkoutTimerNotification.kt` | Native persisted snapshot includes session ID, plan/split and integer week; title is plan + Week N. Add block display context compatibly, retaining session ID as routing authority. |
| `lib/screens/home_screen.dart`, `lib/screens/dashboard_screen.dart`, `lib/widgets/home/up_next_card.dart` | Plan entry versus exact draft resume must remain distinct. Dashboard already passes `initialSession`, including a fallback for a missing plan. |
| `lib/utils/set_history.dart`, `lib/utils/plan_stats.dart` | Previous-set sorting/filtering uses `beforeWeek`; plan stats has legacy name fallback. Raw week numbers cannot order repeated Week 1s. |
| `lib/screens/history_screen.dart`, `lib/widgets/history/history_journal_data.dart`, `lib/widgets/history/history_journal_widgets.dart`, `lib/widgets/history/workout_details_widgets.dart` | History details use session identity; labels need block context. Preserve orphan records and exact-session detail routing. |
| `lib/services/statistics_analytics_service.dart`, `lib/services/pr_tracking_service.dart`, `lib/screens/stats_screen.dart` | Completed sessions and logged dates drive analytics. Archiving structure must not filter those sessions out or collapse distinct logs by week. |
| `lib/services/coach/coach_context_builder.dart`, `lib/services/coach/coach_applier.dart`, `lib/screens/coach_review_screen.dart` | Coach summarizes completed sessions and edits shared plans. Its current apply rollback covers plans/splits/preferences, not structure/progress. New workouts need starting-week selection without inventing block prescriptions or expanding the model contract unnecessarily. |

## Recommended schema and aggregate boundaries

Use **separate block and week records**, plus **one small progress record per
plan**. Keep Hive as runtime truth and Provider as the UI pattern. Use existing
UUID and timestamp/tombstone conventions; no event-sourcing system or generic
repository framework is needed.

### Proposed records

- `TrainingBlock`: `id`, `splitId`, `name`, `position`, `createdAt`, nullable
  `archivedAt`, and `userId/updatedAt/deletedAt/dirty`. Archive is reversible
  visibility state, distinct from deletion and from any workout's completion.
- `TrainingWeek`: `id`, `blockId`, `splitId`, `number`, `position`, `createdAt`,
  and normal sync metadata. `number` is a displayed label, never a lookup key.
  New blocks create 1…N; extension appends max(number)+1. Migration preserves
  labels/gaps, and sorts them numerically. No arbitrary week renumber/reorder
  UI is required in V1; retire the old per-plan rename-week action.
- `WorkoutProgress`: deterministic `id` per `(splitId, planId)`, `splitId`,
  `planId`, `activeWeekId`, `state` (`ready` or `awaitingBoundary`), optional
  `lastAppliedCompletionSessionId`, and normal sync metadata. This record is
  explicit training position, not the last week the user happened to view.
  A new workout's chosen start is its first `activeWeekId`; earlier slots do
  not acquire fictitious completion flags.
- `WorkoutSession`: append nullable `trainingWeekId` at Hive field 15; retain
  existing fields 0–14 unchanged. Derive block through the week, avoiding two
  independently writable structural references. Retain `weekNumber` as a
  legacy/display snapshot; new navigation and progression never query by it.
  Add a payload schema version for compatibility; do not equate it with backup
  format version. If stored locally, allocate field 17 or later, leaving field
  16 for transition evidence. JSON/copyWith/adapter round trips preserve links.
  Recommend one optional completion-transition value at appended Hive field 16,
  encoded as a primitive map locally and in JSON: either `nextWeekId` or an
  explicit boundary outcome. Its source is the session's `trainingWeekId`;
  session ID is the idempotency key. This is written only with a successful
  active-slot completion and travels with that session for crash/sync recovery.
  Legacy sessions have no transition; merely finding a completed log must not
  manufacture a new progression event.

Proposed paths: `lib/models/training_block.dart`,
`lib/models/training_week.dart`, `lib/models/workout_progress.dart`; boxes
`training_blocks`, `training_weeks`, `workout_progress`; Hive types 8, 9, 10
subject to a fresh collision check at implementation. Generated companions
would be produced later by build_runner, never handwritten. Mirror these as
`public.training_blocks`, `public.training_weeks`, `public.workout_progress`.

Keep progress separate from `WorkoutPlan`: Coach/plan edits and logging then do
not overwrite each other through the same whole-row conflict unit. Three new
small record types cost more wiring than embedding, but each has a distinct
mutation lifecycle. No separate persisted browser-selection model is needed.

### Identity, ordering, and relationship rules

1. New blocks/weeks use random UUIDs. Rename, reorder, archive and label changes
   retain IDs. Use `(position, id)` as a deterministic order, including tie
   breaking after concurrent reorder. Never use list index as identity.
2. Destination identity is `(owner/cache scope, splitId, planId, trainingWeekId)`;
   exact log identity is `sessionId`. Return a list of sessions for a destination,
   not an assumed unique row. Do **not** add a unique constraint on
   `(planId, trainingWeekId)`: legacy duplicates must survive.
3. Maintain unique live displayed week numbers within a block. For concurrent
   offline Add week collisions, retain both UUIDs and both sets of session data:
   the rejected append is rebased to the next available number and retried,
   updating its local display snapshot, rather than merging/deleting a week.
   Surface the renumbering when it affects an already viewed slot. Use bounded
   retries, keep it dirty on failure, and test the server constraint/retry path.
   This is an exceptional conflict rule, not a general renumbering feature.
4. Composite keys/FKs must enforce owner **and split** through the graph:
   block → `(splitId, userId)`; week → `(blockId, splitId, userId)`;
   linked session → `(trainingWeekId, splitId, userId)`; progress → both its
   plan and week in that same split/owner. Add supporting unique parent keys
   and child indexes. An ID-only FK or owner-only RLS is insufficient.
5. A non-null session plan reference must agree with its owner/split when the
   plan exists. Keep nullable/missing-plan history as history; do not require a
   live plan to display a migrated log. Audit any existing plan FK before
   deciding how to retain truly dangling legacy references. Locally retain the
   original value; if a server FK requires normalization, preserve it in a
   legacy-reference payload field rather than inventing a plan or dropping a log.
6. Validate graph relationships on local writes, import, and remote decode.
   Promoted remote columns are canonical; reject conflicting JSON links, never
   silently relink them to the active split. A legacy **missing** link follows
   migration; an invalid **present** link is a recoverable data error.
7. Keep tombstoned structural records for referencing history and stale-device
   reconciliation. Do not reuse their IDs/numbers to resurrect deleted content.
   Active progression cannot target a deleted or archived week/block.

### Material alternatives

Embedding weeks in a block reduces boxes/tables and makes a create-block write
simple, but whole-row last-write-wins can lose another device's appended week
and leave sessions referencing its removed child. Making that safe requires
merging or compare-and-retry logic for the entire array. Embedding all structure
in Split increases that contention further. Separate rows contain independent
week edits and make parent validation explicit; they still require append
conflict handling and do not solve concurrent reorder globally.

Deriving progress only from completed logs avoids a record, but cannot represent
an explicitly chosen starting slot or a deliberate boundary transition cleanly,
and historical deletion/editing would change the inferred position. Embedding
progress in a plan saves one table but couples unrelated Coach/template edits
to logging. Recommend the explicit small progress aggregate, with completed
sessions as recovery evidence, not a full event log.

## Recommended runtime rules and proposed product defaults

These defaults are proposals, not additional confirmed user decisions.

### Progress versus browsing

Implement a focused `lib/services/workout_progression_service.dart`, with
split-scoped access through `lib/repositories/training_block_repository.dart`
and `lib/providers/training_block_provider.dart`. Keep the repository thin;
pure progression/source-resolution decisions belong in services. The provider
owns shared structure and per-plan progress; the screen owns only selected
week/session and `expandedBlockId`.

- Ordinary workout entry resolves that plan's active week. Switching workouts
  saves first and opens the new workout's own active week, rather than carrying
  the browsed week across. Exact-session entry overrides browser selection only.
- Expanding/collapsing a block does not load a week or modify progress. Tapping
  a week changes browser selection after save succeeds. Closing the selected
  block leaves its selection recognizable in the label/heading.
- Proposed V1 logging rule: edit drafts while browsing, but enable Log workout
  only for the active slot; completed historical sessions remain read-only in
  the workout screen. This avoids turning future-week browsing into an implicit
  skipping mechanism. Confirm this restriction before wiring completion UI.
- Completion persists the finished session first. Only after success, if it is
  the active slot, advance its progress to the next supplied week in that block,
  or keep the final week with `awaitingBoundary`. The screen may keep showing
  the just-logged result; it need not immediately navigate to another session.
- Use `lastAppliedCompletionSessionId` and expected active-week checks to make
  retries harmless. Crash between session and progress writes is repaired from
  that completed active session on restart/pull before resolving entry. A
  completion-transition value is part of the same session aggregate write as
  completion. It records the intended successor ID (or boundary), so a later
  reorder cannot alter recovery on this device or another device. A separate
  completion journal is unnecessary. Apply only this committed evidence against
  its expected active source; a normal open does not invent a transition from
  an arbitrary historical completed session. Sync it before dependent progress.
- Normal open/leave, autosave, pause/resume, discard, draft deletion, and changes
  in calendar time have no progression transition. No visit timestamps or
  “missed” flags are introduced. Historical edits/deletes never rewind progress.
- Existing completed destinations can arise from legacy duplicates or sync.
  Do not create replacement logs or recursively walk to a later block. Resolve
  completion evidence for the active slot idempotently; ambiguous conflicting
  drafts/completions require an explicit selection/recovery notice, not data loss.
- A final completion marks the pending boundary without opening a prompt in the
  current visit. On the next ordinary plan entry, offer the required choices.
  Exact historical/detail/notification navigation does not trigger that prompt.
  “Next visit” is route entry, not foreground resume or a provider rebuild.
- Proposed dismissal: keep the completed final session visible/read-only and
  retain `awaitingBoundary`; expose a Choose next week action and offer the
  choices again on the next ordinary entry. Dismissal adds no week and does
  not cross the boundary.
- Boundary Add week persists a shared appended week and moves only the choosing
  workout into it. If another device already extended the block, offer/use the
  existing next supplied week instead of accidentally appending twice; recheck
  at confirmation. Other ready workouts progress into it through completion.
  A workout still awaiting a boundary may explicitly continue into that existing
  extension. A workout already in a later block stays there.
- Move to next block chooses the first week of the next unarchived block in
  shared order. Create block collects name/count, commits shared structure,
  then moves only this workout. Merely creating/reordering a block in management
  does not activate it for every workout. Revalidate after asynchronous dialogs.

Use existing exclusive-local-mutation gating and a small journal/compensating
rollback for multi-box writes; Hive has no cross-box transaction here. Do not
hold a successful completion hostage to a transient progress-write failure:
show the completed log accurately, retain recovery work, and retry progression
without logging again or restarting its timer.

Per-plan progress uses the existing last-write-wins policy, not a split-wide
maximum. Document that simultaneous choices for the **same workout** resolve
by that record's timestamp; sessions remain intact. Never merge cursors by
week number, since blocks can be reordered. Reject replayed completion events
whose expected source is no longer active. A winning explicit boundary choice
must not be undone by recovery of an older completed week. Test reordered
push/pull and same-session completion on two devices.

### Destination selection and value initialization

Add a focused source resolver (proposed
`lib/services/training_week_session_resolver.dart`) and pass resolved records
to `WorkoutSessionInitializer`; do not make the initializer query global Hive.

1. An explicitly requested live session ID wins, including a particular duplicate
   log/draft. For ordinary slot entry, prefer its running draft, then most recent
   incomplete draft, then most recent completed log. Use updated/date and ID
   tie breakers consistently, never Hive insertion order. If several drafts are
   running, retain the existing account-wide timer conflict resolution.
2. Any saved destination wins over all inheritance/template changes. Reopening
   an unlogged draft restores it exactly. Save initialized values as a genuine
   **incomplete** destination draft when first edited/started or explicitly
   saved, not as completed sessions for every planned slot. Do not persist
   untouched previews just because plan-shaped sets exist.
3. For block N > 1, resolve the immediately preceding block in shared order,
   including archived predecessors; match its week by displayed number and
   the same stable plan ID. Prefer the latest completed source log using the
   deterministic tie breaker. Proposed fallback: do not inherit unfinished
   source drafts; use plan targets when no completed matching source exists.
   Never substitute that preceding block's final week for every destination.
4. Proposed first-block behavior: Week 1 uses current plan targets; subsequent
   weeks copy the same workout's previous provided completed week when present,
   preserving familiar carry-forward. If absent, use current plan targets.
   For any later-block missing matching week/session, use current plan targets
   directly, rather than chaining through unrelated earlier weeks/blocks.
5. Match source exercises by trimmed, whitespace-normalized, case-insensitive
   name and occurrence index for duplicate names. No fuzzy matching or new
   exercise-ID migration is needed in V1. Keep current plan exercise order and
   guidance; for matched exercises copy ordered source reps/weight/RPE and set
   count. New/unmatched exercises use their plan targets; removed source
   exercises are not reintroduced. Do not copy past set notes as instructions.
   Confirm this mapping rule; stable exercise identities can be a later feature.
6. Copy once into a deep, editable draft with its own session identity, current
   date and `isCompleted: false`; reset start/timer/duration. Subsequent source
   edits, block reorder or template changes do not overwrite saved destinations.
   An untouched preview can reflect the source until it becomes a saved draft.
   Discard resets the same active slot using these rules; it does not advance it.
   Never copy completion-transition evidence into the new draft.

Keep “Previous” set references separate from initialization. Replace `beforeWeek`
with a structural cutoff `(block position/id, week position/id)` for workout
references; use completed same-plan, same-split earlier slots, ordered by that
cutoff and then log date/ID. A B2/W1 reference can use B1's final performed week
while its **initial values** still come from B1/W1. Plan-editor Last values
remain date-based and split-scoped. Never include the selected session itself,
future slots, foreign splits, or inherited draft values as performed history.

### Management, archive, and creation defaults

- Propose name “Block 1” and one persisted Week 1 for a brand-new empty split or
  preset, avoiding an invented program duration. A creation sheet allows any
  supported positive upfront count, prefilled with 1; choose a modest validated
  cap during UI work, not an unbounded allocation. Use ordinary split-wide plans.
- Add a starting block/week picker to `lib/screens/plan_editor_screen.dart` for
  new plans, defaulting to first week of first unarchived block and clearly
  showing the shared split. Save plan and progress together with rollback.
  Duplication and Coach-created plans need the same selection rule; existing
  plan edits do not reset progress.
- Management sheet: Create block, Rename, Reorder blocks, Archive, and access to
  Archived blocks / Restore. Add week belongs to the specified expanded block.
  Explain once that structure changes affect every workout in this split.
  Duplication, block prescriptions, arbitrary week relabeling and bulk log
  deletion are deferred recommendations, not confirmed omissions.
- Proposed safe archive eligibility: at least one completed log, no live plan
  progress pointing into the block (including a boundary-pending workout), and
  no incomplete/running session there. Report which workouts prevent archive.
  Completion is evaluated per workout; one workout finishing is insufficient.
  Workouts starting in later blocks do not owe fictitious earlier completions.
- Archived blocks disappear from ordinary progression but remain reachable in
  management and History. Restore retains all IDs and does not rewind progress.
  Reordering changes future “previous/next block” resolution only; pointers,
  historical links and saved initialized values stay attached to their IDs.
- Enforce archive eligibility in the server mutation as well as the client,
  serializing it with progress/child writes for that block. A stale offline
  draft arriving after archive must remain recoverable; report the conflict and
  offer restoring the block rather than dropping the draft or silently moving
  that workout. Never interpret archive as evidence that all workouts completed.
- Proposed deletion limit: allow removal only of empty weeks/blocks with no live
  sessions, progress references or running timers; preserve at least one usable
  week/block. Never cascade-delete shared logged weeks from the old per-plan
  menu. Use archive for blocks containing logs. Keep tombstones and identity
  records; a later permanent-delete feature needs separate agreement.

## Migration and compatibility design

### Deterministic local and server upgrade

Implement one reusable legacy-normalization algorithm, used at startup,
post-pull, and import, with matching UUID test vectors for Dart and SQL.
Proposed paths: `lib/utils/training_block_identity.dart` and
`lib/services/training_block_migration.dart`.

1. Finish existing stable-ID and split assignment first, in the correct
   account/cache scope. Do not migrate account A's cached records as B's data.
   Run before workout UI exposure; in offline-only mode use the existing local
   split convention without requiring auth/network.
2. Derive the initial block UUID v5 from a frozen namespace string containing
   the immutable split UUID and migration version, e.g.
   `https://opengym.app/splits/<splitId>/training-blocks/legacy-v1`. Derive its
   legacy week UUIDs from that block ID plus the original integer label. This
   deliberate migration-only use of old numbers gives two devices identical
   identities. Normal new IDs never depend on labels. A late migration must
   not depend on the user's current name, block order, migration date or owner
   stamping; adoption of the same split preserves these IDs.
3. Use the **union** of persisted legacy session numbers across all workouts in
   that split, including orphan history and tombstoned sessions needing links.
   Create one initial block, one week per distinct number, preserve gaps, and
   link every existing session while retaining its ID and all historical fields.
   Do not deduplicate logs or identify a plan by ambiguous name. An empty split
   gets one Week 1. Existing in-memory-only tabs cannot be recovered; state that
   limitation rather than manufacturing guessed historical weeks.
4. Assign missing plan IDs only if one unambiguous plan exists in the same
   owner/split with the legacy name. Otherwise retain orphan/ambiguous history
   with its plan-name snapshot and week link. Same-name plans never share new
   sessions. Malformed labels/relationships are preserved in the safety backup
   and surfaced for recovery; never silently discard/renumber historical data.
5. Initialize progress per extant plan once: most recent unfinished draft's
   mapped week (deterministic tie breakers), otherwise the next **existing**
   supplied week after its highest completed legacy number, or
   `awaitingBoundary` on its highest completed final slot. A plan without logs
   starts at the first existing week. Do not fill historical gaps or append a
   new week from elapsed time. Where contradictory drafts/logs prevent a safe
   choice, retain all records and offer recovery selection rather than guessing
   completion. Old unfinished drafts remain unfinished.
6. Before changing links, write a complete, owner-scoped safety snapshot to an
   on-device file and durably record its path plus a migration journal. Include
   raw tombstones and existing migration inputs. Avoid a large new JSON blob
   in SharedPreferences. Journal phases: snapshot, parents, links, progress,
   verification, complete. Upsert missing deterministic parents, then links;
   each phase must safely resume after process termination. Mark complete only
   after verifying all expected links/counts and flushing storage.
7. Do not bump performance dates/timers, or use “now” to overwrite migrated
   historical fields. Keep new-link sync metadata explicit. For deterministic
   parent bootstrap, insert-if-absent on server, then pull the existing parent;
   never let a late upgrader rename/unarchive/reorder it with a newer bootstrap
   timestamp. Tombstones win over recreation. Unchanged records are not dirtied
   on every scan; no backup/journal reruns when already valid.
   Bootstrap progress is also provisional/insert-if-absent: a late upgrader
   must pull and adopt existing server progress instead of pushing a fresh
   inferred cursor over a workout that already entered a later block.
8. Protect startup failure: do not let main.dart's broad startup catch expose a
   partially migrated mutable workout screen. Offer retry/recovery/export while
   keeping the original data recoverable. Providers see a coherent graph only.

A one-shot flag is an optimization, not the entire compatibility mechanism.
Every future legacy pull/import missing `trainingWeekId` repeats the same
mapping for only those records and ensures missing legacy weeks. It never
re-initializes existing progress or creates a second initial block. Reject a
late record that would revive a deleted split/week; retain a recoverable copy
rather than moving it to a different block. Late rows belonging to a legitimately
archived initial block remain historical; they do not automatically reactivate
it. Tombstone suppression and account preparation happen before normalization.

If a previously unseen legacy Week N collides with a newer planned Week N in
the initial block, reserve the original label/deterministic ID for legacy data.
Rebase the newer random-ID week to an available label using the append-conflict
path, preserving its ID, sessions and progress references. Do not merge slots
by label or change old session IDs. Show the label correction when relevant;
saved destination values remain untouched. Include this partial-replica case
in migration tests, not just collisions between two new appends.

Server backfill must apply the same split union and ID algorithm. Client and
server can each know only part of that union; separate week rows let the union
converge without one device replacing another's complete list. Match seed
numbers, null links, tombstones and partial backfill in cross-language fixtures.
Do not regenerate stable session IDs even when the destination has duplicates.

### Supported old-client boundary: release blocker

**Recommend a server-enforced upgrade boundary**, with a preparatory compatible
release, instead of pretending old binaries can safely edit repeated Week 1s.
An older client's whole JSON write strips unknown fields; older navigation can
also combine unrelated weeks. Preserving nullable columns alone does not help.

Concrete proposal to prove in Phase 0, then implement in the compatibility phase:

- Supported clients send an explicit training-schema capability on every data
  request, configured in `lib/services/supabase_service.dart`; use a request
  header with a versioned value. This is a protocol gate, not authentication.
  RLS/ownership still provide authorization.
- Persist server-controlled per-account activation/minimum schema state in a
  small capability record, separate from workout aggregates. Clients cannot
  lower it or clear it through backup restore or Clear split data. Activation
  and backfill are a serialized server operation, not a local feature flag.
- Before activation, a preparatory release can reconcile legacy data and report
  upgrade-required sync errors. After activation, database guards reject writes
  from missing/old capabilities across **all** affected mutation paths: plans,
  sessions, progress, structure, splits/preferences as applicable, including
  direct DELETE and legacy upsert paths. Gate reads of incompatible workout
  data too; simply hiding the new tables leaves old clients seeing misleading
  flattened logs. Document and test privileged migration exceptions narrowly.
- New clients include versioned payloads and structural links and recognize the
  server's upgrade-required result; do not clear dirty queues or advertise a
  successful sync. An old binary cannot be made to show new explanatory copy
  remotely: it may only see a sync failure until updated. Communicate that
  limitation in release guidance. Offline old clients can still edit their own
  stale cache; retain those records for normalization when they upgrade.
- Activate only after compatibility guards and late-legacy upgrade paths are
  verified. Do not grant service credentials to the app or trust user-editable
  JWT metadata. Verify request-header availability for the installed SDK/API
  in an isolated environment before settling the exact gate implementation.

A compatibility bridge that preserves links on old writes is an alternative if
requiring upgrades is rejected, but it must also prevent ambiguous old week
navigation and destructive writes. That is materially larger scope. A UI-only
update prompt or a `schemaVersion` stored only in JSON is not an acceptable gate.
Do not activate blocks for synced accounts without an enforceable choice.

### Sync graph and deletion ordering

Extend `lib/services/sync_service.dart` status, dirty enumeration, cursor
management, row codecs and change notifications for all three new tables.
Use normal promoted columns for links/order/archive and metadata; retain
versioned session payloads. Follow the Supabase skills for future implementation
and confirm current APIs then; this plan makes no live schema assumptions.

- Before pushing, pull split/structure tombstones and reconcile parent state;
  reject stale local children of deleted parents. Push live splits → live
  blocks → live weeks → plans → sessions → progress → preference. Progress must
  not reference an unpushed completion/session or destination. Parent failure
  defers its children without losing local edits or blocking offline logging.
- During the upgrade's first reconciliation, pull existing sessions/progress
  before uploading migrated aggregates. Adding a link must not give a stale
  cached log a new timestamp that overwrites a newer remote log. Backfill links
  additively against the current server row, and condition migrated writes on
  the revision read; if it changed, pull/normalize again. This targeted upgrade
  path is distinct from ordinary user edits under the existing LWW policy.
- Push empty-child tombstones before their deleted block, and deleted splits
  last, after preference replacement. Split tombstone cascade covers blocks,
  weeks, progress and existing plans/sessions on both client and server.
  Archive never invokes a session tombstone cascade. Empty-week/block deletion
  retains history references and rejects live child writes after deletion.
- Pull in parent order, then plans/sessions, then progress; publish a coherent
  provider refresh after reconciliation. Retain or refetch unresolved children
  durably. Do not advance a table's cursor past an unapplied child unless it is
  in a durable retry/quarantine queue. Reject foreign-owner/split edges; do not
  “repair” them by assigning the current owner. A remote deleted parent wins
  over a newer stale live child, including when the child was dirtied offline.
- Add `(user_id, server_seq)` cursor indexes and relationship indexes. RLS must
  cover SELECT/INSERT/UPDATE with ownership `USING` and `WITH CHECK`; grant only
  the necessary operations, revoke anonymous access and public execution of
  internal helpers. Composite FKs additionally prevent cross-split ownership
  mistakes. Test authenticated users with another owner's UUID and own UUIDs
  from another split. Keep account-erasure cascades distinct from product archive.
- Reuse timestamp last-write-wins for independent records and tombstone priority.
  Dirty flags clear only for the exact revision acknowledged, not a row edited
  while its upload was in flight. Ensure cursor pagination does not lose rows
  sharing a server sequence timestamp (use a stable sequence+ID continuation or
  inclusive replay with idempotent application). Current tests primarily cover
  cursor parsing, so add transport/relationship tests rather than assuming them.
- A sync cycle captures account identity/generation and rechecks it after awaited
  operations. Handover drains/cancels old work before clearing and displaying
  the next cache. No response/journal/provider from A can repopulate B's boxes.

## Dependency-ordered implementation phases

Paths marked “new” are proposed; migration filenames must be generated later by
the Supabase CLI, not invented here. Each phase is a reviewable commit group,
not a request to execute it during this documentation task.

### Phase 0 — settle contracts and compatibility proof

Dependencies: none.

1. Accept or replace the genuinely blocking choices below; record decisions in
   a follow-up product specification. Accept the aggregate direction and freeze
   legacy UUID namespace/test vectors before writing persistent data.
2. In a later authorized isolated development environment, inventory existing
   plan/session constraints, update triggers, sequence types and grants. Prove
   old-client insert/upsert/update/delete/read rejection and upgraded-client
   reconciliation using the proposed capability gate. Check SDK header support.
3. Define a fixture matrix: mixed plan numbering/gaps, no data, duplicate names,
   duplicate sessions, deleted plans, orphan history, drafts/running timers,
   two partial offline replicas, and foreign relationships. Define a bound and
   user feedback for concurrent week-number append retries.

Exit: the team can state which clients may write, how conflicting slots are
resolved, and which operations can advance/archive. No cloud activation before
this gate passes. Storage work can proceed after schema contracts are accepted;
UI polish need not block it.

### Phase 1 — local structure, identities, and resumable migration

Dependencies: Phase 0 schema/identity agreement.

1. Add the three models/boxes and deterministic legacy/progress identity helpers.
   Extend `lib/models/workout_session.dart` serialization/copy and appended
   fields. Preserve all adapter IDs/indices/default legacy completion behavior.
2. Extend `lib/services/hive_service.dart` registration, raw/live reads, scoped
   CRUD, dirty/tombstone handling and relationship checks. Add the thin
   `lib/repositories/training_block_repository.dart` and migration service.
3. Add ID-based `sessionsForPlanWeek(planId, weekId, splitId)` and exact-session
   access. Isolate any legacy name fallback inside normalization; deprecate
   number/name mutation helpers so no new UI can call them accidentally.
4. Run resumable migration after stable-ID/split/account setup, before normal
   entry; cover offline-only startup in `lib/main.dart`, account preparation in
   `lib/services/adopt_local_data.dart`, and failure presentation through
   `lib/auth/auth_gate.dart` as needed. Do not migrate a previous account first.
5. Update `test/support/hive_test_harness.dart`,
   `test/support/pump_with_storage.dart`, and storage-opening fixtures to include
   new adapters/boxes. Add `test/training_block_migration_test.dart` and
   `test/training_block_repository_test.dart` (new).

Exit: empty planned weeks, split scoping, duplicate/orphan logs and crash-resume
migration work locally without navigation changes or fake completed sessions.
Do not ship a temporary old workout UI against new repeated-number data.

### Phase 2 — server compatibility and graph sync

Dependencies: Phase 1 model contracts; Phase 0 compatibility proof.

1. Generate additive migrations under `supabase/migrations/` for tables,
   indexes, composite ownership FKs, nullable session link, payload agreement,
   capability state/guards, deterministic backfill and lifecycle protections.
   Stage constraint validation/backfill so historical inconsistencies can be
   retained/repaired deliberately. Do not edit old migration files.
2. Extend `lib/services/supabase_service.dart` capability transport and
   `lib/services/sync_service.dart` dependency ordering/codecs/cursors,
   bootstrap insert-if-absent behavior, tombstones and conflict retries. Include
   activation/upgrade-required state in sync status surfaced by Settings.
3. Extend `lib/services/adopt_local_data.dart` to adopt only unowned rows or
   already-owned same-account data, include new cursors/boxes/journals and
   account-generation guards. Audit existing broad owner stamping as part of
   the touched paths; a wrong-owner record is never a successful adoption.
4. Add `test/training_block_sync_test.dart` (new) with a fake transport; extend
   `test/sync_sequence_test.dart`, `test/sync_data_flow_test.dart`,
   `test/split_data_layer_test.dart`. Plan isolated authenticated database
   integration checks in `docs/online_support_verification.md` later.

Exit: partial-replica migration converges; parent failure/retry, old-client
rejection, deleted-parent suppression, account handover and late legacy pulls
are proven. No production activation yet.

### Phase 3 — backup and complete data lifecycle

Dependencies: Phase 1 local graph; Phase 2 compatibility contract.

1. Bump `lib/services/backup_service.dart` to format **4**. Export blocks, weeks
   (including empty/archived ones), progress and linked sessions in addition to
   splits/plans/settings. Extend `ImportResult`; retain supported versions 1–3
   through the shared deterministic upgrade algorithm, not a second migration.
2. Validate the entire graph before writes: duplicate IDs, conflicting links,
   unknown blocks/weeks, cross-split plan references, progress targets and active
   split. Preserve distinct session IDs at the same slot. Do not let the current
   importer's plan-derived split assignment mask a conflicting supplied split.
   Reject malformed v4 graphs with actionable errors and no partial replacement.
3. Update `lib/screens/settings_screen.dart` export arguments, import preview,
   confirmation copy and provider reloads, plus
   `HiveService.replaceAllWorkoutData`. Gate replacement from sync; safety
   snapshot/journal and rollback/recovery must include every new box. Preserve
   archive state and destination IDs. Tombstone absent replaced records, not
   just plans/sessions, so another device cannot restore the discarded structure.
4. Ownership: backups carry source-account provenance separately from row
   ownership. Same-account restore preserves IDs; confirmed foreign-account
   copy remaps the **whole graph**, including sessions and progress IDs, before
   assigning the new owner. Unknown-provenance legacy restores need an explicit
   same-account assertion or graph-copy mode, not blind reassignment of UUIDs
   that may belong to someone else. Remapping is an import mode, not the normal
   same-account migration. Never copy account capability state between users.
5. Extend account clearing, split deletion, `softDeleteAllWorkoutData`,
   `softDeleteWorkoutDataForSplit`, physical cache resets and raw rollback APIs.
   Recommended Clear split/all workout data behavior: retain split profiles,
   tombstone blocks/weeks/progress with workout data, then create one fresh
   usable default block/week with new IDs. Sample replacement affects only the
   selected split. Do not rerun legacy bootstrap into tombstoned IDs.
6. Update `lib/services/workout_preset_installer.dart`,
   `lib/services/split_install_target.dart`, `lib/services/sample_data_seeder.dart`
   and their rollback stages. Install default structure and plan progress with
   no fake sessions; sample logs map their existing 1–5 labels through the
   normal migration/fixture builder. “Untouched default split” reuse must
   distinguish an automatically created Block 1/Week 1 from intentional user
   structure, so preset reuse never destroys a custom empty block profile.
7. Add `test/training_block_backup_test.dart` (new); extend
   `test/split_data_layer_test.dart`, `test/workout_presets_test.dart`,
   `test/auth_recovery_test.dart`, and account/lifecycle fixtures where relevant.

Exit: v4 round trip, v1–3 upgrades, replacement failure recovery, preset rollback,
account switching and clearing cover every new record type. Backups remain a
usable recovery path before feature activation.

### Phase 4 — progression and initialization services

Dependencies: Phases 1–3; completion/browsing decision accepted.

1. Add progression and source-resolution services described above. Implement
   pure transitions for completion, boundary choices, new-plan start, draft
   preservation, and no-op browsing. Integrate committed transition evidence and
   `lib/services/workout_completion_service.dart` without weakening failed-write
   or PR semantics. Normalize pulled completion/progress in dependency order.
2. Refactor `lib/services/workout_session_initializer.dart` to take explicit
   destination and source. Replace raw previous-number resolution in
   `lib/utils/set_history.dart`; update plan-editor lookup callers separately.
3. Add `lib/providers/training_block_provider.dart`, wire it in `lib/main.dart`,
   and reload/dispose with split/account changes. Keep completed history in
   `WorkoutSessionProvider`; expose durable structure even with zero sessions.
4. Add `test/workout_progression_test.dart` (new). Extend
   `test/workout_session_initializer_test.dart`, `test/set_history_test.dart`,
   `test/workout_lifecycle_test.dart`, `test/coach_applier_test.dart` as needed.
   Existing “later weeks without prior data ignore targets” expectations must
   be deliberately updated if the proposed fallback is approved.

Exit: completing Push W1 advances only Push; unlogged W2 survives a week of
calendar time/restarts unchanged; final completion leaves a pending choice;
matching-week inheritance and crash recovery preserve destination sessions.

### Phase 5 — inline navigation, boundary choices, and management

Dependencies: Phase 4; archive/delete eligibility accepted before those actions.

1. Replace integer state/caches/routes and widget keys in
   `lib/screens/workout_screen.dart` with week/session IDs and local browser
   selection. Remove `_loadWeeks` automatic max+1 creation and per-plan
   rename/delete operations. Reuse save revision/navigation locks; failed saves
   leave selection and expanded target unchanged.
2. Add `lib/widgets/workout/training_block_strip.dart` (new). Model the strip as
   block label, that block's revealed week children, then following block.
   Animate simple width/size reveal for one block; use no animation under
   `MediaQuery.disableAnimationsOf`. On ordinary entry expand/scroll active
   week after layout; on exact resume show its target even when it differs from
   the progression cursor. Use a dedicated controller, not a week-number offset.
3. Add management and boundary sheets in
   `lib/widgets/workout/workout_dialogs.dart` or focused new
   `lib/widgets/workout/training_block_dialogs.dart`. Boundary prompts run once
   per ordinary route entry, after pending saves/dialogs settle. Actions verify
   current parent/progress state again before writing, show split-wide effects,
   disable during persistence and preserve input on failure.
4. Update `lib/screens/plan_editor_screen.dart` new-plan/duplicate flow with
   starting-slot selection and rollback. Keep existing plans' progression when
   renaming/reordering/editing exercises. No “set current week” shortcut that
   becomes a skipping feature.
5. Show “Block name · Week N” in the workout heading and semantic labels.
   A selected collapsed block retains a marker/summary; long names can truncate
   visually with full semantics. Keep 48px targets, horizontal scrolling, large
   text, and logger space. Provide an accessible Block actions button/semantic
   action in addition to long press. Use AppHeader/AppBackButton, theme color
   roles, AppRadius and AppTypography.figures; accent actions stay independent
   of plan color. No new visual system is needed.
6. Add `test/training_block_navigation_test.dart` (new) and extend
   `test/workout_plan_navigation_test.dart`, `test/workout_entry_test.dart`,
   `test/workout_log_test.dart`, `test/navigation_mutation_guards_test.dart`,
   `test/plan_editor_test.dart`, `test/screen_layout_test.dart`,
   `test/ui_hierarchy_accessibility_test.dart`. Replace legacy empty-tab/delete
   expectations in `test/workout_lifecycle_test.dart` with shared-structure rules;
   do not simply delete autosave/timer coverage.

Exit: shared inline structure, independent active positions, next-visit boundary
choices, stable saved drafts, upfront block length/extension, starting picker,
long-press management and accessible reduced-motion behavior are usable.

### Phase 6 — exact routes and secondary surfaces

Dependencies: Phase 4 APIs; Phase 5 entry behavior.

1. Replace `initialWeekNumber` with a typed identity destination (proposed
   `lib/navigation/workout_destination.dart`) across
   `lib/app_shell.dart`, `lib/screens/home_screen.dart`,
   `lib/screens/dashboard_screen.dart`, and `lib/screens/workout_screen.dart`.
   Preserve explicit `sessionId` priority and re-fetch at actual route delivery.
   `lib/navigation/app_navigation_observer.dart` must continue reusing a route
   by exact displayed session, not by plan/week label.
2. Extend `lib/services/workout_timer_notification_service.dart` and
   `android/app/src/main/kotlin/com/aalishms/opengym/WorkoutTimerNotification.kt`
   with optional block/week identity and display context. Old saved snapshots
   still parse; resolve missing context from the session's new link. Keep Stop
   confirmation, accumulation, account-wide running-timer conflict resolution,
   native state revision and deferred-modal behavior unchanged. Invalidate
   foreign/deleted session intents on account handover. Cover the native mapping
   in `android/app/src/test/kotlin/com/aalishms/opengym/WorkoutTimerStateTest.kt`.
3. Add block context to History rows/details and recent/resume widgets in the
   paths listed above. Archive lookup must include archived parents. Prefer a
   retained label/legacy fallback when a parent is unresolved, never an empty
   History row or accidental relink. Keep raw weekNumber only for that fallback.
4. Audit `lib/utils/plan_stats.dart`, `lib/services/statistics_analytics_service.dart`,
   `lib/services/pr_tracking_service.dart`, `lib/screens/stats_screen.dart` and
   dashboard/heatmap callers: include completed logs across archived blocks,
   keep date-based calendar analytics, count every distinct historical session
   once, exclude drafts and tombstones. Block analytics filters are deferred.
5. Coach: keep summary eligibility date-based across archived history and shared
   template scope explicit in `lib/screens/coach_review_screen.dart`. Extend
   `lib/services/coach/coach_applier.dart` rollback to new-plan progress/default
   structure. Resolve each added plan's starting slot in the review UI before
   applying; default visibly and require the user can change it. Updated
   existing plans retain progress and saved sessions. Inheritance uses current
   template only for unsaved destinations/fallbacks. No Edge Function deployment
   or new block proposal contract is required unless context fields are later
   approved; if added, version both app and `supabase/functions/coach/contracts/`.
6. Extend `test/workout_notification_navigation_test.dart`,
   `test/home_screen_test.dart`, `test/history_redesign_test.dart`,
   `test/statistics_analytics_test.dart`, `test/coach_context_builder_test.dart`,
   `test/coach_applier_test.dart`, `test/coach_ui_test.dart` with repeated week
   labels, duplicates/orphans, archives and exact-session targets.

Exit: nothing outside the logger interprets raw Week 1 as a globally unique
training destination, and archived history remains visible and counted.

### Phase 7 — validation, documentation, and controlled release

Dependencies: all preceding phase exits.

Update DESIGN.md, docs/splits.md, docs/coach.md and
`docs/online_support_verification.md` **when implementation is authorized and
behavior is settled**, not in this session. Document compatibility minimum,
archive/clear/import semantics and recovery. Keep initialization.md as discovery
history unless the owner explicitly requests an edit.

Use a manageable rollout:

1. Additive server schema/guards and a preparatory client release, with blocks
   disabled for normal users. It understands upgrade-required status, backup v4
   and migration recovery. Verify no changed behavior for unactivated accounts.
2. Internal/offline fixture validation and two-device isolated account trials;
   then a small opted-in account cohort. Back up before local/server activation;
   activate per account only when its compatibility boundary can be enforced.
3. Release the feature-capable client; expand account activation after observing
   migration failures, relationship quarantines, sync retry/conflict behavior
   and native resume. No sensitive workout payloads in diagnostics.
4. Leave additive schema and migrated data in place on rollback. Disable further
   activation/structure mutations and ship a forward fix; never downgrade an
   activated account to an old writer or flatten repeated week identities.
   Old clients' queued offline edits must survive until a capable client upgrades
   and normalizes them. Offline-only builds can migrate locally without network
   activation, but must negotiate the boundary before their first later sync.

When a future release is approved, follow AGENTS.md: increment both version name
and globally increasing +build in pubspec.yaml, preserve signing identity, and
use the exact version tag and universal APK. Release mechanics are out of scope
for this documentation commit.

## Future validation commands and acceptance checks — do not run now

During implementation, follow the project's required analyzer workflow after
changes and regenerate adapters after Hive model changes, followed by a full
restart for manual verification. These examples are recorded only:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/training_block_migration_test.dart test/training_block_repository_test.dart test/training_block_backup_test.dart
flutter test test/training_block_sync_test.dart test/workout_progression_test.dart test/training_block_navigation_test.dart
flutter test test/workout_session_initializer_test.dart test/set_history_test.dart test/workout_lifecycle_test.dart
flutter test test/workout_notification_navigation_test.dart test/workout_plan_navigation_test.dart test/navigation_mutation_guards_test.dart
flutter test test/split_data_layer_test.dart test/workout_presets_test.dart test/statistics_analytics_test.dart
flutter test test/coach_applier_test.dart test/coach_context_builder_test.dart test/coach_ui_test.dart
flutter test
```

New test paths above are planned files, not existing passing tests. Discover
Supabase CLI commands with `--help` when later authorized; generate migrations
with `supabase migration new <descriptive-name>`. Run migration/backfill, RLS,
foreign-key, downgrade-client and tombstone integration checks only in an
explicitly isolated development/test database. Inspect Android Gradle task names
before running the existing native timer unit tests. No live Coach/model call is
needed for this feature's normal regression checks.

Acceptance matrix:

- **Shared empty structure:** Create B1/W1–4; Push/Pull/Legs show identical IDs
  before any logs. Restart, v4 round trip and another device preserve all four
  weeks; History/PR/workout counts remain empty.
- **Independent progression:** Complete Push W1; Push advances to supplied W2,
  Pull stays W1. Edit/leave Push W2 without completing; reopening tomorrow or
  seven days later retains W2 and every saved value, with no metadata tracking
  a missed visit. Discard does not advance. No Skip week UI exists.
- **Boundary:** Finish final week without an immediate prompt. Next ordinary
  visit offers exactly the appropriate pair. Cancel/dismiss creates nothing;
  Add week extends shared structure but advances only the choosing workout;
  Move/Create never moves another workout. Another device extending while the
  sheet is open is revalidated. A completed session is not logged twice.
- **Inheritance:** B2/W1 copies B1/W1, B2/W2 copies B1/W2. Missing/short previous
  blocks, no completed source, changed/duplicate exercise names, different set
  counts, plan-target fallback and first-block carry-forward match the accepted
  rules. Saved destination drafts/completions survive source edits and reorder.
  No completion/date/timer history is copied to a fresh destination.
- **Identity/navigation:** Two blocks' Week 1s, same-name plans, two logs in one
  slot, renamed plans and orphan history remain distinct. Notification body/
  Stop opens the exact running session behind modals/autosave, reuses its route,
  and never substitutes the ordinary active slot. Failed saves block navigation.
- **Migration:** Sparse weeks 1/3/12 across workouts become one shared initial
  block preserving labels and session IDs/bytes for exercise/timer data. Kill
  after each journal phase; retry is idempotent. Two devices with disjoint week
  subsets converge to one block and the union of weeks. Late legacy pull/import
  adds only missing mappings and never resets migrated progress. Parent
  tombstones, duplicates, ambiguous names and malformed references are covered.
- **Sync/ownership:** Empty structures sync. Reordered parent/child delivery,
  parent push failure, completion before progress, concurrent append/reorder,
  same-plan progress conflict, cursor page ties and in-flight local edits lose
  no records. Wrong-owner and same-owner/wrong-split graphs fail. Old binaries
  cannot mutate or delete an activated graph. A→B account handover during sync,
  migration or native intent delivery never leaks/cache-restores A's data.
- **Lifecycle:** Archive retains History, records and date-based stats; unfinished
  plans/timers prevent archive under the proposed rule. Restore does not rewind.
  Split deletion cascades durable tombstones; a stale offline child cannot
  revive them. Clear split, all-workout-data helper, sample replacement, preset
  install/rollback, Coach new/removed plans, and failed import touch only the
  intended owner/split and include all new records.
- **Interaction/accessibility:** Inline reveal places weeks beside their block,
  at most one expanded; entering scrolls the correct target into view. Selection
  remains understandable when collapsed. Long names, many blocks, small phone,
  large text, screen-reader Block/Week labels, reduced motion, action sheets,
  theme contrast and a running timer remain usable.

## Unresolved choices and implementation gates

### Genuinely blocking decisions

1. **Supported upgrade boundary (blocks synced rollout):** Accept requiring
   capable clients after account activation, including older binaries showing
   a sync error and retaining offline edits until upgrade, or fund a full
   compatibility bridge. Recommended: enforced boundary with preparatory release.
2. **Repeat sessions and nonactive-slot logging (blocks completion/UI contract):**
   Can users explicitly perform a workout twice in a slot, and can they log a
   manually browsed future/older slot? Recommended V1: preserve all legacy and
   concurrently created sessions, exact-session resume, no new Repeat action,
   and logging only at the progression-selected active slot. Never impose a
   destructive uniqueness constraint while this is unresolved.
3. **Archive/delete eligibility (blocks shipping management actions):** Decide
   what happens with lagging workouts/drafts and whether logged shared weeks
   may ever be deleted. Recommended V1: manual archive only when no progress or
   draft points inside; no deletion of logged slots; restore via management.
   Storage must support archive/history retention regardless of the UI decision.

These do not require a long questionnaire now. Resolve each before its dependent
phase; independent model/migration work can be planned against the recommendations.

### Reasonable defaults to confirm, not reasons to stall discovery

- Boundary dismissal retains the completed final session/pending choice;
  switching workouts resumes each workout's active week.
- Extending an earlier block never pulls a workout back from a later block;
  creating a block in management does not activate every workout.
- First block and missing-source initialization, completed-source preference,
  exercise name/occurrence matching and copy-on-save follow the rules above.
- Empty split/preset starts with Block 1 / Week 1; new plans and Coach additions
  expose a start picker. Block names need not be globally unique; IDs disambiguate.
- Reorder affects future resolution, not saved destinations; archive preserves
  chronological History/records/stats. No V1 block analytics or prescription UI.
- Empty-only structural deletion, Clear split reset behavior, preset “untouched”
  detection, cross-account backup copy mode and concurrent append feedback
  follow the conservative proposals above.

## Main risks and scope controls

The largest risk is silent identity loss from old writers or late bootstrap,
followed by inconsistent migration across offline replicas. Address those before
UI activation. Next are cross-box interruption, account handover races and
shared archive actions affecting a lagging workout. Journals, relationship
validation, exact-session routing and phase-specific failure tests are required
work, not polish.

Separate records still inherit existing timestamp conflict limitations. Do not
claim collaborative ordering or merge guarantees that this plan does not build.
Prefer explicit, recoverable conflicts to overwriting sessions. Keep duplication,
calendar scheduling, skip logic, historical block reconstruction, permanent
logged-week deletion, block analytics, prescription templates and Coach block
editing out of V1 unless separately agreed. The feature should add durable week
groups and deliberate independent progression, not a new training-program engine.

## Documentation-session verification

Repository inspection and documentation review only. The author checks the
Markdown diff, repository path references, consistency with the latest unlogged
week correction, and `git diff --check`, then stages this file explicitly and
commits documentation on the existing branch. Application/database validation
above is deferred and must not be reported as executed or passing.
