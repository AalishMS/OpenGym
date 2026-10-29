# Training blocks: implementation plan

Date: 2026-10-28

Branch: `feature/training-blocks`

Reviewed against: `b675c01`

Status: Tasks 1–7 and the independent whole-branch review against base
`358894a` are complete locally. The review continued on GPT-6.1 Sol after a usage
limit interrupted the earlier reviewer. All three Important findings are fixed
with RED→GREEN regressions and a passing full suite; no Critical/Minor findings
remain. Deployment/release is unauthorized. Android/device checks and full
browser workout interaction remain pending as recorded in
[implementation-status.md](implementation-status.md).

> For implementation, use `superpowers:executing-plans` task by task. Each task
> ends with its focused tests, `flutter analyze`, and an explicitly staged commit.
> Do not ship an intermediate client that exposes the old week UI to new data.

**Goal:** Split-wide blocks of durable weeks, with independent workout progress,
matching-week starting values, and unchanged access to historical logs.

**Architecture:** Keep Hive as runtime truth and Provider for UI state. Add three
small records: block, week, and per-plan progress. Sessions reference weeks;
plans remain shared prescription templates. Reuse existing sync, navigation,
timer, backup, and mutation infrastructure.

**Stack:** Existing Flutter/Dart, Hive, Provider, UUID, and Supabase dependencies.
No new package, state-management system, event bus, or generic sync framework.

**Product source:** [initialization.md](initialization.md). Its confirmed
requirements remain authoritative. This revision resolves its open implementation
choices with the explicit V1 defaults below; these are review recommendations,
not claims of previously obtained user approval. [DESIGN.md](../../DESIGN.md),
[split workspaces](../splits.md), [Coach](../coach.md), and
[AGENTS.md](../../AGENTS.md) continue to apply.

## Review findings and resulting decisions

The previous plan had the right aggregate boundaries and integration coverage,
but was not yet executable without further product and recovery design.

| Finding | Resolution in this plan |
| --- | --- |
| Active-week checks alone cannot distinguish a stale completion from a new visit to the same slot after reorder. Replaying with a fresh timestamp can overwrite a later choice. | Revision-bound completion evidence with a fixed resulting revision and timestamp; replay checks the full expected progress state. |
| Migration's “most recent draft” can select a browsed future draft and appear to skip unfinished weeks. The rule was mixed with an undefined recovery picker. | A deterministic, migration-only selection rule; preserve all other drafts and make them reachable by exact ID. No new general recovery-selection workflow. |
| Week `position` duplicates `number` while week reorder is excluded. | Store only the week number; order weeks numerically. Only blocks have `position`. |
| Empty-week/block deletion adds distributed reference checks and tombstone races to an unrequested feature. | Defer individual structural deletion. Retain tombstones for existing split deletion, data clearing, and restore. |
| Concurrent append rebasing lacked a retry bound and stable precedence for late legacy data. | Specify three attempts, local-ID preservation, and legacy-number reservation. |
| Cursor handling assumed timestamp pagination would guarantee delivery. Existing `server_seq` is `timestamptz` set by `now()`, and `_selectSince` uses strict `gt` without pagination. | Paginate explicitly and add full reconciliation for late commits. Do not describe timestamps or a plain sequence as commit order. |
| The rollout required a preparatory release, cohort machinery, and another feature release. | One capable client plus additive server deployment and an irreversible per-account compatibility boundary. Test with isolated accounts before release; no cohort platform. |
| Many defaults and limits remained “to confirm” or “choose during UI work.” | Fix the V1 contract below and give each implementation task concrete interfaces and acceptance tests. |

## V1 contract and scope limits

- Blocks and planned weeks belong to a split. Every workout sees identical
  structure, including empty weeks and blocks other workouts have completed.
- New blocks start at Week 1. Migration preserves existing numbers and gaps.
  All navigation and writes use IDs; labels are never session identity.
- Each workout has its own active week. Logging/completing advances through
  supplied weeks in that block. Opening, leaving, calendar time, browsing,
  discarding a draft, and another workout's completion never advance it.
- Completing the last supplied week records a pending boundary. On the next
  ordinary route entry, offer Add week / Move to next block if a next block
  exists, otherwise Add week / Create block. No prompt immediately on completion.
  Dismissal leaves the completed result visible and a Choose next week action.
- A block extension is shared; only the workout choosing its boundary action
  moves. Workouts already in a later block never move backward automatically.
  Creating a block in management never activates it for other workouts.
- Ordinary entry and workout switching open that workout's active week.
  Exact-session entry opens the requested log/draft, without moving progress or
  triggering a boundary prompt. Save-before-navigation remains mandatory.
- Browsing may edit/save incomplete drafts, but a new timer and Log workout are
  enabled only for the active slot. Completed logs are read-only in the logger.
  An already-started nonactive draft from migration or another device can resume,
  stop, and finish by exact ID; finishing it saves history without advancing
  progress. This exception prevents stranded timers and does not enable Skip.
- No new Repeat workout action. Preserve all existing/concurrent session IDs,
  including several in the same slot; do not impose session-slot uniqueness.
- New/duplicated plans and Coach additions choose a starting block/week, visibly
  defaulted to the first week of the first block. Existing plan edits keep progress.
- A new split starts with Block 1 / Week 1. Create block accepts a trimmed name
  of 1–40 characters and 1–52 initial weeks, default 1. Names need not be unique.
  The creation limit bounds one allocation, not migration or lifetime length;
  Add week may extend beyond 52. Do not impose a new limit on migrated numbers.
- Block actions: Create block, Rename, Reorder. Add week belongs to a specific
  block. No individual block/week deletion, week renaming/reordering, archiving,
  skipping, calendar scheduling, block prescriptions, block duplication, block
  analytics, or Coach block-editing contract in V1.
- Existing split deletion, plan deletion, session deletion, Clear All Data,
  sample replacement and backup restore remain supported. Deleting a historical
  log does not rewind progress. All completed logs remain eligible for existing
  date-based History, records, and statistics.

## Data contracts

### Records and identity

All new records use existing `userId`, `updatedAt`, `deletedAt`, `dirty`
conventions. New IDs are UUID v4 except the explicitly deterministic cases below.

| Record | Fields beyond sync metadata | Storage |
| --- | --- | --- |
| `TrainingBlock` | `id`, `splitId`, `name`, integer `position`, `createdAt` | Hive `training_blocks`, type 8; SQL `training_blocks` |
| `TrainingWeek` | `id`, `splitId`, `blockId`, positive integer `number`, `createdAt` | Hive `training_weeks`, type 9; SQL `training_weeks` |
| `WorkoutProgress` | `id`, `splitId`, `planId`, `activeWeekId`, `state` (`ready`, `awaitingBoundary`), `revision` | Hive `workout_progress`, type 10; SQL `workout_progress` |
| `WorkoutSession` additions | nullable `trainingWeekId` at Hive field 15; nullable primitive-map `completionTransition` at field 16 | Existing box/table; preserve fields 0–14 |

Check type collisions before implementation. Generate adapters; never hand-edit
them. Use a typed Dart value for transition validation/serialization, stored as
a map so it does not require another Hive type. Session JSON emits
`trainingSchemaVersion: 1`; no extra Hive schema-version field is needed. Missing
JSON version means legacy; unsupported future versions fail explicitly.

Retain `weekNumber` as a legacy/display snapshot. Derive the block through the
week; do not add another writable block link to sessions or timer destinations.
`copyWith` must distinguish keeping a nullable field from explicitly clearing it.

Freeze deterministic identities with Dart/SQL fixture vectors:

- Legacy block = UUID v5, URL namespace,
  `https://opengym.app/splits/<lowercase-split-uuid>/training-blocks/legacy-v1`.
- Legacy week = UUID v5, namespace = legacy block UUID, name = canonical decimal
  week number (no whitespace or leading zeroes).
- Progress ID = UUID v5, URL namespace,
  `https://opengym.app/splits/<lowercase-split-uuid>/plans/<lowercase-plan-uuid>/progress-v1`.
- Initial migrated progress revision = UUID v5, namespace = progress ID,
  name = `initial-v1`. Normal explicit moves use UUID v4 revisions.

Blocks sort by `(position, id)`; weeks by `(number, id)`. Block reorder updates
positions under the local mutation gate. Concurrent reorder uses existing LWW
per row and UUID tie-breaking; do not add a collaborative ordering algorithm.

### Relationship and append rules

- Slot identity is `(owner/cache scope, splitId, planId, trainingWeekId)`;
  exact log identity is `sessionId`. Queries return a list, not a unique session.
- Composite server FKs enforce owner **and split**: block → split;
  week → block/split; linked session → week/split; progress → plan/split and
  week/split. Add the supporting parent unique keys and child indexes.
- Retain nullable/missing-plan history. Never invent a plan for an orphan or
  discard a log to satisfy a new FK. Audit existing plan constraints in Task 2;
  if a dangling ID must be normalized for server storage, preserve its original
  value in a legacy-reference payload field and restore it on export.
- Promoted remote links are canonical. Validate JSON agreement, local writes,
  imports, and pulled relationships. Missing legacy links can be normalized;
  conflicting supplied links are errors, never reassigned to the active split.
- Keep a unique live `(blockId, number)` server constraint. Append chooses
  max live number + 1 locally. On a server collision, fetch the block's weeks,
  assign the rejected week the next available number, and retry at most three
  times per sync cycle. Keep the same week/session/progress IDs and saved values.
  Update affected session display snapshots under the mutation gate. Keep dirty
  data and show a retryable sync error if retries exhaust; never discard a week.
- Legacy deterministic weeks reserve their original labels. A late legacy Week N
  takes precedence over a conflicting new random-ID Week N. A transactional
  normalization operation rebases the new week before inserting the legacy
  one, using the same rule. Test this collision in both arrival orders.
- Retain structural tombstones for clear/restore/split deletion. A deleted parent
  wins over a stale live child; IDs are never reused to resurrect a graph.

Separate week rows prevent one device's whole-block write from removing another
week with logs. Separate progress prevents Coach/template edits from overwriting
training position. These three conflict units are justified; do not add a second
repository/cache layer or persist browser selection.

## Runtime rules

### Completion and recovery

`WorkoutProgressionService` owns progression. `WorkoutCompletionService` remains
responsible for the completed session, stopped timer, and PR result. Execute a
completion under the existing exclusive local mutation gate; never recursively
acquire it from internal helpers.

A transition contains `expectedRevision`, `sourceWeekId`, `nextWeekId` (null for
boundary), `resultRevision` (the completing session UUID), and `committedAt`.
Validate that the source matches the session and the target is in the same block.
For active-slot completion:

1. Re-read progress and the latest session under the gate. Compute the next
   supplied week once. Write completion and transition in **one session upsert**.
   A failed write leaves the original draft/timer and progress unchanged.
2. Apply the recorded result only if progress is `ready` at both the expected
   revision and source week. Next week gives `ready`; null target gives
   `awaitingBoundary` at the source. Set revision to `resultRevision` and
   `updatedAt` to the recorded `committedAt`, never the recovery time.
3. If progress persistence fails, completion still succeeded. Show the completed
   log, retain its evidence, and replay before the next ordinary entry or sync.
   Never log twice or restart the timer. Recovery is idempotent; an already
   applied result or mismatching revision is a no-op.
4. Reconcile pulled progress with local progress before replaying session evidence.
   An explicit later boundary choice has a new revision and cannot be undone by
   old evidence. Process eligible evidence deterministically by
   `(committedAt, sessionId)`; bound each reconciliation to the available evidence
   count. Do not infer events from legacy completed logs without evidence.

No separate completion journal or event table. Preserve evidence when editing or
soft-deleting a completed session until its outcome is reconciled; deletion does
not reverse it. Cross-device concurrent edits of the *same session* retain the
existing whole-row LWW limitation; this plan does not promise set-level merging.
If reconciliation leaves a `ready` slot containing only completed logs and no
applicable transition, show its saved result with an explicit Continue action.
On confirmation, re-read the selected completed session and current progress;
advance from that active slot using a fresh progress revision and the normal
successor/boundary rule. This is a single progress write, not another completion
or PR event. It cannot move past an uncompleted slot. Do not automatically infer
progress from arbitrary historical logs or introduce a general Set current week
action. Include this exceptional conflict-recovery case in Task 4 tests.

Same-workout concurrent choices use `(updatedAt, revision)` ordering for progress
on both client and server. A stale upsert must not overwrite a newer server row;
prove the server comparison, not just the client's pull comparison.

Boundary actions re-read progress after any dialog. If another device extended
the block, show Continue to Week N and use that supplied successor instead of
appending again. Move uses the first week of the next block in current order;
Create persists the block/weeks before moving only this workout. If reorder
changes the proposed next block while the sheet is open, refresh the choice
before applying it. Each move replaces the progress revision. Keeping the same
active week ID is insufficient to establish that a dialog is still current.

### Destination and inheritance

A focused `TrainingWeekSessionResolver` consumes a split-scoped snapshot; it does
not query global Hive from inside the initializer.

1. Exact live session ID wins. Otherwise choose the slot's running draft, then
   latest incomplete draft, then latest completed log. Within each category use
   `(updatedAt ?? date, date, id)` descending. Keep the existing account-wide
   running-timer conflict handling. All duplicates remain reachable in History
   or the existing resume surfaces; no deduplication or replacement log.
2. Any saved destination wins over inheritance. Initialize an unsaved preview,
   then persist a real incomplete draft only on edit/start/explicit save.
   Untouched plan-shaped previews do not create history or migration inputs.
3. Later blocks use the immediately preceding live block in current order,
   same plan ID and matching week number. Use its latest completed session;
   ignore source drafts. If absent, use current plan targets directly.
4. In the first block, the first supplied week uses plan targets (even if its
   migrated label is 3). Later supplied weeks use the immediately preceding
   supplied week's completed session; absent source means plan targets.
5. Match exercises by trimmed, whitespace-normalized, case-insensitive name plus
   occurrence index for duplicates. Preserve current plan order/guidance; copy
   matching source sets' reps, weight, RPE and count. New exercises use targets;
   removed exercises and past set notes are not copied. No fuzzy matching.
6. New draft: fresh session ID, current date, incomplete, no start/running timer,
   zero duration, no completion evidence, explicit plan/split/week IDs. Deep-copy
   sets. Source/template edits and reorder never overwrite a saved destination.

“Previous” references are separate from starting values: completed same-plan,
same-split sessions in earlier structural slots, ordered by block `(position,id)`,
then week number, then date/ID. Thus B2/W1 can show B1's final performed week as
Previous while inheriting B1/W1. Exclude itself, drafts and future slots.
Plan-editor Last remains date-based. Fix plan-ID filtering even when no plan-name
argument is provided; the current helper only applies it inside a name guard.

### Local mutation boundaries and efficient reads

`TrainingBlockProvider` exposes the active split's structure/progress; the workout
screen owns selected week/session and expanded block only. Build in-memory maps
by block ID, week ID, plan ID, and `(planId, weekId)` on data reload. Do not scan
all history per chip, build, or timer tick; do not persist duplicate indexes.
Scope rebuilds so the elapsed-time ticker does not rebuild the block strip.

Reuse `SyncService.runExclusiveLocalMutation`. It prevents sync interleaving,
not process death. For block creation, plan+start creation and boundary create,
use one small pending-operation record with fixed IDs and intended writes;
flush it before writes, roll forward idempotently on restart, clear after flush.
Publish provider changes only after completion. A failed action retries the same
IDs, not a second block. Migration and replacement use their larger safety
snapshot described below. Do not build a generic transaction framework.

## Migration, backup, and account lifecycle

### Resumable normalization

One `TrainingBlockMigration` algorithm serves startup, late legacy pull and
v1–3 import, with matching SQL identity fixtures.

1. Finish existing ID and split assignment in the correct account/cache scope.
   Offline-only startup must work without auth/network. Never migrate A's cache
   as B's data. New structure is hidden until preparation succeeds.
2. Snapshot raw records, including tombstones, to an owner-scoped local file.
   Record snapshot path and phases: snapshot → parents → links → progress →
   verification → complete. Flush at phase boundaries and make each repeatable.
   Do not store a full backup blob in SharedPreferences. Retain only the latest
   successful migration safety snapshot per owner; pending recovery is never pruned.
3. For each split, create its deterministic initial block and the union of legacy
   session numbers across all plans, including orphan/tombstoned history. Empty
   split gets Week 1. Preserve gaps, IDs, dates, completion, exercise and timer
   data. Invalid nonpositive/malformed labels stop normalization with export/retry
   available; do not silently rename them. In-memory-only tabs are unrecoverable.
4. Link by stable plan ID. Assign a missing plan ID only when the same owner/split
   contains exactly one matching plan name. Ambiguous history stays orphaned.
5. Initialize missing progress once: running draft first, otherwise latest
   incomplete draft by `(updatedAt ?? date, date, id)`. Without drafts, choose
   the next supplied week after the highest completed legacy number, or keep
   that final week `awaitingBoundary`. No logs means the first supplied week.
   This migration heuristic preserves draft access; it cannot infer whether an
   old draft was browsing or training. Preserve every other draft for exact resume.
6. Verify counts/links and flush before complete. Never expose a partially
   migrated logger through main.dart's broad startup catch. Show retry/export
   on failure without overwriting the original snapshot.
7. Late missing links use the same deterministic mapping, not a second initial
   block. Existing progress is never reset. Parent/progress bootstrap is
   insert-if-absent; a late device adopts existing server state. Deleted parents
   reject resurrection and retain the local source in the recovery snapshot.

Migration must not bump stale session timestamps to “now” and overwrite newer
remote sets. During first sync, pull current sessions/progress before sending
migrated rows. Link backfill updates only missing links against the read revision;
if it changed, fetch and normalize again. Preserve genuinely dirty legacy edits
for normal conflict reconciliation; never clear them just because links migrated.

### Backup and lifecycle matrix

Backup v4 includes blocks, weeks (including empty ones), progress, linked sessions,
plans/splits/settings and source-account provenance. Validate the complete graph
before replacement; reject conflicting supplied references and unknown versions.
Versions 1–3 reuse normalization. Same-account restore preserves IDs; copying
foreign/unknown-provenance data remaps the whole graph, including progress
revisions and transition references. Never copy server activation state.

| Operation | Required behavior |
| --- | --- |
| Restore | Validate first; pause sync, snapshot every box, journal replacement; tombstone absent replaced records and recover after interruption. Update Settings callers and provider reloads. |
| First account adoption | Adopt only unowned/same-owner rows; include structure/progress and pending operations. Preserve deterministic IDs. |
| Account handover | Drain/cancel old sync, invalidate navigation/native intents, clear all boxes/cursors/pending operations and owner-scoped safety files before displaying the new cache. |
| Delete plan / Coach remove plan | Tombstone its progress; retain logged sessions and their week links. No active progress may point to a deleted plan. |
| Delete split | Cascade tombstones through blocks/weeks/progress/plans/sessions; select replacement preference first. Reject stale children. |
| Clear workouts | Retain split profiles; tombstone their workout graph and create a fresh Block 1 / Week 1 with new IDs. Do not revive deterministic legacy IDs. |
| Preset / Coach add plan | Create default structure if absent, choose each plan's start, and include progress/structure in pending operation or rollback. No fake sessions. |
| Sample replacement | Affect only the selected split; create its 1–5 week structure and link fixture logs. |

Default-split reuse is allowed only for the pristine auto-created structure
(Block 1, Week 1, unchanged initial metadata, no plans/logs/pending operations).
Treat renamed, extended, reordered or otherwise edited empty structure as user
content. Never delete it because there are no performed sessions.

## Server compatibility and sync

### Upgrade boundary

Use one feature-capable release, preceded by additive server schema deployment.
The capable client sends `x-opengym-training-schema: 1`. Store irreversible
per-account `minimum_training_schema` in a server-controlled capability row;
activation/backfill is an authenticated, serialized RPC. No client may lower it.
Before first sync of migrated local data, negotiate/activate this boundary.
Offline-only builds migrate locally and negotiate when later enabling sync.

After activation, reject incompatible reads and writes through all affected
routes, including old session/plan upserts, direct DELETE, split cascades and
preferences. Return an explicit upgrade-required error rather than an empty
successful SELECT. Headers are protocol compatibility, **not authorization**;
RLS still checks the authenticated owner and FKs check relationships. Old apps
may only display their existing sync error; they retain local edits until upgraded.
Do not add a full old-client translation bridge or preparatory binary release.

PostgREST exposes lowercased request headers through `request.headers`; verify
transport with the installed SDK and deployed API in Task 2. RLS and table grants
are separate controls. See [PostgREST transaction settings](https://docs.postgrest.org/en/stable/references/transactions.html#request-headers-cookies-and-jwt-claims)
and [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
Use an API pre-request guard (or equivalent tested error-raising gate), not
SELECT filtering alone. Existing deployments/privileged paths must be inventoried
before choosing its migration/configuration details. No service key in the app.

### Ordering, conflicts, and delivery

- Pull parent tombstones before push. Push live splits → blocks → weeks → plans
  → sessions → progress → preference, deleted splits last. Parent failures defer
  children without clearing dirty flags or blocking offline logging.
- Pull parents, plans, sessions, then progress; replay completion evidence only
  after progress reconciliation. Publish one coherent provider refresh.
- Apply existing timestamp LWW semantics consistently on the server, not blindly
  upsert stale rows. Clear dirty only for the exact acknowledged local revision;
  an in-flight edit remains dirty. Parent tombstones override live children even
  when the child's clock is newer.
- Do not advance a cursor past an unapplied relationship. Simplest V1 behavior:
  keep the table cursor unchanged, report a retryable sync error and replay the
  page after parent refetch. Invalid remote graphs must not enter normal boxes.
  No new durable quarantine queue/dashboard is required.
- Use explicit pages and `(server_seq, id)` continuation for deltas, inclusive
  replay at the saved timestamp, and save the cursor only after the entire pull
  applies. This fixes ties/response limits, **not late commits with older stamps**.
  Add a paginated full pull at initial/account sync and at most once per 24 hours
  on a successful foreground sync; manual retry requests one immediately. Scan
  by stable ID; restart the sweep after interruption and never infer deletion
  from absence. This bounds eventual repair without introducing a change-log
  service. Include tombstones. Small structural tables may always use full pull.
- Capture account ID/generation at cycle start and recheck after awaits. A stale
  response cannot write into the next account's cache.
- Index `(user_id, server_seq, id)` and graph relationships. Enable RLS, explicit
  authenticated grants and owner `USING`/`WITH CHECK`; revoke anonymous access and
  public execution of internal helpers. Test own-owner/wrong-split as well as
  wrong-owner links. Keep account-erasure hard cascades separate from tombstones.

## Implementation tasks

Each task follows: add its named failing cases, implement the listed contract,
run focused tests and required analysis, review the diff, explicitly stage and
commit. New test files below are planned, not existing passing tests. Keep
implementation in these focused files; do not simultaneously refactor unrelated
workout UI or replace the sync architecture.

### Task 1 — local records, reads, and migration

**Files:** New `lib/models/{training_block,training_week,workout_progress}.dart`,
`lib/utils/training_block_identity.dart`,
`lib/services/training_block_migration.dart`,
`lib/repositories/training_block_repository.dart`. Modify
`lib/models/workout_session.dart`, `lib/services/hive_service.dart`,
`lib/services/adopt_local_data.dart`, `lib/main.dart`, `lib/auth/auth_gate.dart`,
and Hive test harnesses. Generate model adapters.

**Interfaces:** `TrainingBlockRepository` provides
`List<TrainingBlock> blocksForSplit(String splitId)`,
`List<TrainingWeek> weeksForBlock(String splitId, String blockId)`,
`WorkoutProgress? progressForPlan(String splitId, String planId)`, and
`List<WorkoutSession> sessionsForPlanWeek(String splitId, String planId, String weekId)`.
`TrainingBlockMigration.normalize({required String? ownerId})` returns
`Future<void>` and throws a recoverable preparation error on invalid input.
Public mutations are `Future<TrainingBlock> createBlock({required String splitId,
required String name, required int weekCount})`, `Future<TrainingWeek>
appendWeek(String splitId, String blockId)`, `Future<void> renameBlock(String
splitId, String blockId, String name)`, and `Future<void> reorderBlocks(String
splitId, List<String> orderedIds)`. Validate the supplied reorder contains exactly
the current live IDs. Public mutations own the gate; internal ungated helpers
compose pending operations. Raw writes remain internal to HiveService; reads
are thin wrappers.

- [x] Add `test/training_block_repository_test.dart` for empty structure, owner/
  split validation, duplicate slot sessions, JSON/adapter round trips and nullable
  copy clearing. Extend `test/support/hive_test_harness.dart` and
  `test/support/pump_with_storage.dart` with all boxes/adapters.
- [x] Add `test/training_block_migration_test.dart`: sparse 1/3/12 union, empty
  split, missing/ambiguous plans, tombstones, multiple drafts, exact byte-equivalent
  exercise/timer payloads, Dart UUID vectors and failure after every journal phase.
- [x] Implement records/repository and resumable normalization; rerunning must
  not dirty valid rows, reset progress, or create another initial block.
- [x] Run the two new tests, regenerate adapters, analyze, and commit.

**Exit:** Durable empty weeks and preserved legacy data; UI exposure still gated.

### Task 2 — isolated server proof and graph sync

**Files:** New CLI-generated migrations under `supabase/migrations/`; modify
`lib/services/{supabase_service,sync_service,adopt_local_data}.dart` and
`lib/screens/settings_screen.dart`. New `test/training_block_sync_test.dart`;
extend `test/sync_sequence_test.dart` and `test/sync_data_flow_test.dart`.

**Interfaces:** Sync keeps its existing scheduling API. Add capability negotiation
before migrated uploads, codecs/cursors for the three tables, and explicit
upgrade-required/retryable error status. Internal SQL activation/normalization
operations are idempotent and scoped to `auth.uid()`; no owner supplied by the UI.

- [x] Inventory base plan/session DDL, triggers, grants, API pre-request hooks and
  SDK header support in an isolated database; record findings with the migration.
  The repository lacks initial base-table DDL. Do not guess production constraints.
- [x] Add failing transport/database cases: old-client read/upsert/delete rejection,
  two owners, own-owner wrong split, partial-replica union, newer remote edits
  during backfill, append collision in both orders and three-retry exhaustion.
- [x] Implement schema/backfill/gate and graph ordering. Test parent failure,
  late legacy dirty writes, deleted-parent rejection and in-flight account switch.
- [x] Test more than one response page, equal timestamps, delayed commit behind
  the cursor and its full-pull repair, failed page application, and local edits
  during upload. Verify server stale-write rejection, not merely local LWW.
- [x] Run focused tests and isolated integration checks, analyze, and commit.

**Exit:** Enforced upgrade boundary and convergent graph sync. If the actual API
cannot enforce the gate, stop activation and fix that task; do not ship a UI-only
warning. This is an implementation proof obligation, not another product decision.

### Task 3 — backups and all lifecycle operations

**Files:** `lib/services/{backup_service,hive_service,adopt_local_data,
workout_preset_installer,split_install_target,sample_data_seeder}.dart`,
`lib/services/coach/coach_applier.dart`, `lib/screens/settings_screen.dart`,
plan/split provider delete paths. New `test/training_block_backup_test.dart`;
extend split, preset, auth and Coach tests.

**Interfaces:** Extend `ImportResult` and `replaceAllWorkoutData` with
`blocks`, `weeks`, `progress`. Reuse the typed validated graph for replacement
and recovery; no second normalization algorithm. Existing clear/delete APIs
retain their public meaning and include the new records.

- [x] Test v4 round trip of empty structure, duplicates, pending completion and
  boundary states; v1–3 normalization; conflicting links rejected before writes.
- [x] Test same-owner restore, foreign graph remap including transition revisions,
  process death during replacement, and absent-record tombstones.
- [x] Implement every lifecycle matrix row and bounded owner-scoped recovery files.
  Test plan deletion, split deletion, Clear All Data, custom empty split preservation,
  preset/Coach failure and A→B handover with pending work.
- [x] Run `test/training_block_backup_test.dart`, `test/split_data_layer_test.dart`,
  `test/workout_presets_test.dart`, `test/auth_recovery_test.dart`,
  `test/coach_applier_test.dart`; analyze and commit.

**Exit:** Recovery/export is usable before enabling the feature UI.

### Task 4 — progression, source resolution, and provider

**Files:** New `lib/services/workout_progression_service.dart`,
`lib/services/training_week_session_resolver.dart`,
`lib/providers/training_block_provider.dart`; modify completion/initializer,
`lib/utils/set_history.dart`, provider wiring in `lib/main.dart`.

**Interfaces:** `WorkoutProgressionService.complete(String sessionId)` returns
`Future<WorkoutCompletionResult>` and owns the outer gate;
`applyCompletion(WorkoutProgress progress, WorkoutSession completed)` is a pure
`WorkoutProgress?` transition (`null` = no change).
`continueCompleted({required String sessionId, required String expectedRevision})`
returns `Future<void>` for the explicit completed-slot recovery above.
`chooseBoundary({required String planId, required String expectedRevision,
required String destinationWeekId})` returns `Future<void>` and validates the
allowed successor under the gate. Structure creation uses the pending-operation
mechanism before this move. Resolver produces `WorkoutSession?` destination and
source from explicit lists; initializer takes `TrainingWeek week`, plan, optional
saved destination/source and clock, and returns a `WorkoutSession` without I/O.

- [x] Add `test/workout_progression_test.dart`: Push advances while Pull stays,
  no open/calendar/discard transition, boundary next-visit state, completion-write
  failure, progress-write failure, replay twice, changed revision with same week,
  old replay after boundary choice, two-device competing completion, and explicit
  Continue from a completed active slot without another log or PR event.
- [x] Implement gate + evidence + pure transition. Test finishing an existing
  nonactive timer saves history only. Do not weaken existing PR/timer retry tests.
- [x] Extend `test/workout_session_initializer_test.dart` and
  `test/set_history_test.dart`: B2/W2←B1/W2, first supplied Week 3, missing source,
  duplicate exercise names, changed templates, deep-copy, saved destination wins,
  no copied notes/timers/evidence and plan-ID-only filtering.
- [x] Implement provider maps and source resolution. Run these tests plus
  `test/workout_lifecycle_test.dart`; analyze and commit.

**Exit:** Independent progression and deterministic initialization work without UI.

### Task 5 — workout navigation and management

**Files:** `lib/screens/workout_screen.dart`, `lib/screens/plan_editor_screen.dart`,
new `lib/widgets/workout/training_block_strip.dart` and
`lib/widgets/workout/training_block_dialogs.dart`; relevant plan provider paths.

**Interfaces:** Strip accepts ordered blocks/weeks, `selectedWeekId`,
`expandedBlockId` and select/expand/manage callbacks. It does no persistence.
Screen selection is by week/session ID; block creation/append/rename/reorder go
through the repository's gated mutation methods, not direct widget Hive writes.

- [x] Add `test/training_block_navigation_test.dart`: inline reveal, one expanded,
  entry scrolls active slot, collapse preserves selected context, failed save
  prevents navigation, no phantom max+1 week on open.
- [x] Replace integer caches/keys and legacy per-plan week actions. Preserve exact
  session selections across provider reloads. Remove `_loadWeeks` auto-append.
- [x] Implement next-entry boundary sheets with revision revalidation, dismissal,
  existing-extension reuse and create retry using fixed IDs. Test another device
  extending/reordering while a sheet is open.
- [x] Add starting-slot selection to new/duplicate plan flows; preserve existing
  plan progress. Add accessible Block actions alongside long press.
- [x] Use existing AppHeader/AppBackButton, theme colors, AppRadius, figures,
  48px targets and “Block name · Week N” labels. Test narrow/large-text layouts,
  long names, reduced motion and many blocks; only expanded weeks need widgets.
- [x] Run new tests plus `test/workout_plan_navigation_test.dart`,
  `test/workout_entry_test.dart`, `test/workout_log_test.dart`,
  `test/navigation_mutation_guards_test.dart`, `test/plan_editor_test.dart`,
  `test/screen_layout_test.dart`; analyze, hot reload/restart and commit.

**Exit:** The agreed interaction is usable without changing timer/save semantics.

> Task 5 device verification: Android restart and interactions remain pending
> by user choice. Web debug compilation/restart completed, but browser workout
> interaction was not verified. Actual-font widget screenshots were inspected.

### Task 6 — exact routes, timer, history, and Coach

**Files:** New `lib/navigation/workout_destination.dart`; modify
`lib/app_shell.dart`, `lib/navigation/app_navigation_observer.dart`,
`lib/screens/{home_screen,dashboard_screen,workout_screen,history_screen,stats_screen,
coach_review_screen}.dart`, relevant Home/History widgets,
`lib/services/workout_timer_notification_service.dart`, native
`android/app/src/main/kotlin/com/aalishms/opengym/WorkoutTimerNotification.kt`,
`lib/utils/plan_stats.dart`, statistics/PR services and Coach context/applier.

**Interfaces:** `WorkoutDestination.active(planId)`,
`WorkoutDestination.week(planId, weekId)`, `WorkoutDestination.session(sessionId)`
replace `initialWeekNumber`. Re-fetch at route delivery in the current account;
exact session ID wins. Notification block text is optional display context only.

- [x] Preserve deferred navigation behind sheets/autosaves, exact route reuse,
  orphan detail routes, notification Stop confirmation and account invalidation.
  Test two Week 1s, duplicate logs, renamed/deleted plans and old native snapshots.
- [x] Show block context in history/resume/timer surfaces; unresolved/tombstoned
  context uses retained labels/legacy Week N, never drops a history row.
- [x] Audit analytics to count every distinct completed session once across all
  blocks and remain date-based. Exclude drafts/tombstones; no block filters.
- [x] Coach retains its shared-template contract and date-based history context.
  Review UI selects starts for added plans; removal tombstones progress, edits
  retain progress. No Edge Function deployment or response-contract expansion.
- [x] Run notification/navigation, Home, History, statistics and Coach test suites,
  plus existing native timer tests after discovering the Gradle task. Analyze,
  hot reload/restart and commit.

**Exit:** No caller treats a displayed week number as a unique training location.

### Task 7 — full verification and release preparation

Local scope follows the user's explicit deferral of device checks and prohibition
on deployment/release. [verification.md](verification.md) records the actual
checks and pending external work.

- [x] Run `flutter analyze` and the full Flutter suite. Regenerate Hive adapters
  and confirm no diff; compile/hot restart the web target. Android restart stays
  pending. Full suite: 835 passed, 3 intentionally skipped optional checks.
- [x] Run real loopback SQL/API and installed-SDK trials, including two independent
  Hive directories for offline completion, matching-week inheritance, competing
  append and return-to-first-cache convergence. Re-run automated late-legacy,
  account-switch, interrupted replacement, native intent and boundary checks.
  Physical two-device lifecycle/network interaction stays pending.
- [x] Measure 100 blocks × 52 weeks plus 10,000 sessions on the host VM: stable
  indexes during timer ticks and only the expanded 52 week controls constructed.
  Record measurements and their limits. Android frame profiling stays pending.
- [x] Update DESIGN.md, docs/splits.md, docs/coach.md and
  docs/online_support_verification.md. Keep initialization.md unchanged.
- [ ] Deferred, unauthorized: deploy additive SQL, verify the target API hook,
  grants/RLS and live isolated accounts, then release the capable client.
  Activate only after successful backup/preparation. Use forward fixes or stop
  new activations rather than downgrading an activated account.
- [ ] Deferred, unauthorized: release version/build increment, exact tag,
  signing and universal-APK publication under AGENTS.md.

## Review focus and readiness limits

The five highest-risk cases have explicit owners:

1. Old queued edits after activation → Task 2 compatibility/backfill tests.
2. Crash after session completion but before progress → Task 4 revision replay tests.
3. Two partial replicas with colliding legacy/new week labels → Tasks 1–2 fixtures.
4. Account switch during sync or recovery → Tasks 2–3 ownership tests.
5. Exact running session outside current progress → Tasks 4 and 6 timer tests.

The plan is ready for implementation with the stated V1 defaults. Database
constraints, API gate configuration, native behavior and performance remain
verification work in the tasks above; this documentation review does not certify
a live database or authorize deployment. Do not replace those checks with
assumptions, and do not expand V1 to resolve unrelated app-wide architecture debt.
