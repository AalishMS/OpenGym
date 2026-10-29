# Lazy, independent block weeks implementation plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task by task. Steps use checkbox syntax for tracking. This is a proposed plan; implementation has not started.

**Goal:** Reveal weeks one at a time for each workout, carry forward its completed values, and ask for a continuation choice only after its configured block length is completed.

**Architecture:** Keep split-wide blocks and durable week identities. Store the intended block length separately from allocated weeks, and persist each plan's available week identities separately from its active week. Allocate a shared week slot only when needed; make it available only to the workout advancing into it.

**Tech stack:** Flutter, Provider, Hive, existing Supabase row sync and operation recovery.

**Spec:** The user's October 29 request and follow-up: a new block's Week 1 inherits the previous block's Week 1; subsequent weeks inherit the preceding week within the current block. The proposed behavior below records the remaining implementation decisions.

## Proposed behavior

- Creating a four-week block stores an intended length of four and allocates only Week 1. Weeks 2–4 are not pre-created or shown as empty future tabs.
- Completing Push Week 1 makes Push Week 2 available and active. Pull remains on Week 1, with no new Week 2 tab or initialized session. Pull later reaches the same durable Week 2 slot independently.
- Weeks 2, 3 and 4 copy the same workout's completed values from Weeks 1, 2 and 3 respectively. This applies in every block.
- Week 1 of a later block copies that workout's Week 1 of the immediately preceding live block, preserving the user's confirmed cross-block rule.
- Preserve saved destination drafts/logs. Copy set count, weight, reps and RPE using the existing exercise-matching rules; reset completion and timer state. New/unmatched exercises use current plan targets.
- Completing Weeks 1–3 advances automatically without the boundary menu. Completing Week 4 records an awaiting-choice state, without allocating Week 5.
- Reuse the existing next-visit `Choose next week` sheet: `Add week` and `Move to <next block>`, or `Create block` if none follows. Dismissal keeps the completed result and existing continuation action.
- Proposed extension rule: `Add week` extends the shared block length by one, while revealing and advancing only the workout making that choice. Reaching another workout's already allocated slot reuses it. A shared configuration change never immediately moves another workout.
- Proposed navigation rule: ordinary logging navigation offers only reached weeks and the first week of a block; it cannot create future drafts. The permanent `+` must not bypass the completion/limit rules. Route it to the existing boundary flow only when the selected block is the active block and this workout is awaiting a choice; otherwise hide or disable it with an accessible explanation.
- Keep the existing explicit starting-week choice when adding a workout. The picker can list intended week numbers without allocating all of them. Confirming a start allocates/reuses the chosen slot and makes it available only for the new plan; it does not create sessions for earlier weeks or other plans.

## Evidence and approach

`TrainingBlockRepository.createBlock` and `WorkoutProgressionService.createBoundary` currently allocate every requested week. `TrainingBlock` stores no intended length. `WorkoutScreen._loadStructure` displays the provider's entire split-wide week list for every plan. Existing progression tests assert independent active pointers, but do not assert independent visible tabs.

`TrainingWeekSessionResolver.source` currently uses matching week numbers from the preceding block for *all* weeks in later blocks. That must be retained only for Week 1. `WorkoutScreen._getOrCreateSession` caches an initialized session by week ID, so an early template-based preview can also outlive completion of its eventual source.

Recommended approach: preserve shared week IDs and add per-plan availability. Making every week a plan-owned entity would require replacing the existing graph and database uniqueness rules and migrating all session links. Merely filtering tabs by the active week would lose which weeks were previously reached when a plan changes blocks or an old log is deleted.

## Global constraints

- Hive remains the source of truth; the behavior works offline.
- Preserve durable IDs, existing logs, saved drafts, exact-session navigation, owner/split isolation and completion revision checks.
- Keep blocks shared; do not duplicate the block hierarchy per workout.
- Preserve the existing 1–52 week creation input validation. Explicit extensions retain their existing ability to go beyond the initial length.
- Do not overwrite saved destination values or create successor logs before the source completion is durable.
- Do not delete old pre-created week rows merely to hide unused tabs.
- Run `flutter analyze` after each file change, regenerate Hive adapters after model edits, and fully restart the app after model changes.
- Stage files explicitly; preserve the existing unrelated changes to `analysis_options.yaml` and `pubspec.lock`.
- This planning task does not apply remote migrations, publish a release or change app behavior.

## Review focus

1. Push reaches Week 2 while Pull's active week, available weeks, saved values and drafts remain unchanged.
2. An unsaved preview never causes the next week to retain stale template targets after completing its source.
3. Restart/retry after any allocation, completion or progress write produces one successor and no duplicate completion.
4. Existing pre-created weeks, sparse history and exact session links remain accessible without exposing unused future tabs.
5. Two offline devices allocating the same block/week converge on one logical successor without turning Week 2 into Week 3.

## Task 1: Persist intended length and per-plan availability

**Files:** `lib/models/training_block.dart`, `lib/models/workout_progress.dart`, their generated adapters, `lib/services/training_block_graph.dart`, `lib/services/training_block_migration.dart`, `lib/services/training_block_restore.dart`, `test/training_block_repository_test.dart`, `test/training_block_migration_test.dart`.

**Interfaces:** Add nullable legacy-compatible `int? plannedWeekCount` at the next unused block Hive field (9), and `List<String>? availableWeekIds` at the next unused progress field (10). Null means an old record needing normalization; an explicit empty list is distinct. Add the corresponding `copyWith` and JSON support. Normalization produces non-null values for live graphs.

- [ ] Add failing adapter/JSON round-trip and old-record normalization tests. A fresh four-week block has intended length 4. An old block with weeks 1–4 gets length 4; a sparse block uses its highest live week number rather than its row count.
- [ ] Test availability migration from each plan's own active slot, session slots and recorded completion destinations. Include Week 1, retain reached earlier slots within the same block, and preserve referenced historical slots across blocks. Another plan's sessions or empty future rows must not reveal weeks for this plan. Never rewind an active draft or completed boundary.
- [ ] Implement model serialization and idempotent graph normalization. Validate available IDs against the same split/owner and remap them when backup/import copies identities. Use recorded IDs for availability so structural rebasing cannot change what the plan reached.
- [ ] Regenerate with `flutter pub run build_runner build --delete-conflicting-outputs`; analyze after changes. Run `flutter test test/training_block_repository_test.dart test/training_block_migration_test.dart` and require all tests to pass before committing the relevant files explicitly.

## Task 2: Allocate and advance lazily, with recovery

**Files:** `lib/repositories/training_block_repository.dart`, `lib/services/workout_progression_service.dart`, `lib/models/completion_transition.dart` if additional recovery evidence is required, `lib/services/hive_service.dart`, `test/workout_progression_test.dart`, `test/training_block_review_recovery_test.dart`.

**Interfaces:** Preserve the public `createBlock`, `complete`, `continueCompleted`, `extendBoundary` and `createBoundary` signatures. Introduce one internal find-or-create-next-slot operation under the existing exclusive mutation gate. Both ordinary and boundary block creation persist intended length and exactly one initial week.

- [ ] Add failing tests: `weekCount: 4` allocates only Week 1; completing Push allocates/reuses Week 2, updates only Push's availability/progress and leaves Pull byte-for-byte unchanged. Pull's later completion reuses the same Week 2 ID.
- [ ] Add failing tests for automatic progression through Week 4, awaiting-choice at the limit, no Week 5 allocation before an explicit choice, a one-week block, and `Add week` extending the intended length once. Test a second workout reaching a slot already allocated by the first.
- [ ] Implement next-slot lookup using the intended length, not the number of allocated/shared rows. Within the limit, reuse or allocate the immediate next number, then reveal it only for the completing plan. At the limit, record a boundary even if another structural row happens to exist beyond it.
- [ ] Keep creation/continuation intents recoverable with fixed IDs. Persist enough information to recover a successor allocation without silently completing a session whose completion write failed. A durable completed session's transition must replay both progress and availability. Apply the same rules to `continueCompleted` and recovered boundary operations.
- [ ] Add failure-injection tests before and after allocation, session write, availability/progress write and journal cleanup. Retrying/restarting must keep one successor, preserve the original completion time/revision and never mutate Pull.
- [ ] Run `flutter test test/workout_progression_test.dart test/training_block_review_recovery_test.dart`; require passing results and analysis, then commit this task explicitly.

## Task 3: Correct inheritance and initialization timing

**Files:** `lib/services/training_week_session_resolver.dart`, `lib/services/workout_session_initializer.dart`, `lib/screens/workout_screen.dart`, `test/training_week_session_resolver_test.dart`, `test/training_block_navigation_test.dart`; extend the existing initializer tests located by searching for `WorkoutSessionInitializer`.

**Interfaces:** Preserve `TrainingWeekSessionResolver.source` and `WorkoutSessionInitializer.initialize` signatures. Change source selection: Week 1 uses matching Week 1 of the immediately preceding live block; later weeks use the preceding supplied/reached slot within their own block, with old sparse history preserved.

- [ ] Write failing tests with deliberately different values: prior block Week 2 = 40 kg, current block Week 1 = 55 kg, template = 30 kg. Current block Week 2 must inherit 55 kg. New block Week 1 must inherit the preceding block's Week 1. Include matching reps, RPE, set count and reset completion state.
- [ ] Test saved destination priority, missing/deleted/noncompleted sources, duplicate exercise matching and unmatched exercises using plan targets.
- [ ] Apply the source-selection rule and prevent unreached-week previews from initializing cached sessions. Invalidate only unsaved, untouched initialization caches when their source changes; keep edited or persisted drafts authoritative.
- [ ] Test completing a source after an earlier screen/provider snapshot and then opening its successor. The successor must use the completed source rather than a cached template snapshot.
- [ ] Run resolver, initializer and navigation tests, require passing analysis, and commit the relevant files explicitly.

## Task 4: Show each workout's reached weeks and reuse boundary controls

**Files:** `lib/providers/training_block_provider.dart`, `lib/screens/workout_screen.dart`, `lib/widgets/workout/training_block_strip.dart`, `lib/widgets/workout/training_block_dialogs.dart`, `lib/services/training_plan_installer.dart`, `lib/screens/plan_editor_screen.dart`, and starting-week callers in Home/Coach as needed; `test/training_block_navigation_test.dart`.

**Interfaces:** Add `Map<String, List<TrainingWeek>> weeksByBlockForPlan(String planId)` to the provider. Keep the full week index for graph resolution and exact-session navigation. Logger tabs and remembered block selections consume the plan-specific projection, not the split-wide list. First weeks of live blocks remain browseable without making that block active.

- [ ] Add widget regressions that create a four-week block, complete Push Week 1 and switch to Pull: Push displays Weeks 1–2; Pull displays Week 1 and retains its values. Repeat after provider reload and app/storage reopen.
- [ ] Wire logger navigation to the plan-specific projection, maintain selected-tab scrolling, and preserve exact links to existing drafts/logs. The week-count field describes intended length rather than immediate tab creation.
- [ ] Prevent the strip's `+` from allocating weeks before the current workout reaches its limit. Reuse the existing boundary sheet and preserve its next-visit timing, dismissal and retry behavior. Test that completing Week 3 does not show it, while completing Week 4 does on the next ordinary entry.
- [ ] Keep explicit new-plan starting-week selection functional using intended week choices and on-confirmation allocation. Test choosing Week 3 of an otherwise unallocated four-week block without exposing Week 3 for Push/Pull or creating preceding sessions.
- [ ] Run navigation and affected plan-installation tests, require passing analysis, and commit this task explicitly.

## Task 5: Preserve the new behavior through sync and backups

**Files:** `lib/services/sync_service.dart`, `lib/services/backup_service.dart`, `lib/services/training_block_graph.dart`, `lib/services/training_block_restore.dart`, `lib/auth/training_data_gate.dart`, a new migration created through the Supabase CLI, `supabase/tests/training_blocks/`, `test/training_block_sync_test.dart`, `test/training_block_backup_test.dart`, `test/integration/training_blocks_replicas_test.dart`.

**Interfaces:** Carry `plannedWeekCount` and `availableWeekIds` through remote row mappings and backup graphs. Server columns must default/backfill old rows safely and enforce owner/split-valid links. Update the existing compatibility gate so older clients cannot discard new fields or resume eager creation against upgraded data.

- [ ] Add failing round-trip tests: Push sees Weeks 1–2 and Pull only Week 1 after export/import, account-safe graph cloning and sync to a fresh replica. Preserve intended length 4 even though only two week rows exist. Accept existing backup versions with deterministic normalization; version the new export format to prevent older readers silently discarding new state.
- [ ] Add a replica test for two plans/devices independently allocating the same logical Week 2 offline. Use a stable canonical slot identity or an explicit alias reconciliation strategy for new lazy slots; preserve existing random IDs and logs. Do not reuse the current generic collision rebase that would turn one Week 2 into Week 3. Include current legacy-label reservation behavior in the test.
- [ ] Implement serialization, schema/backfill, graph validation and conflict handling together. Ensure dependent week rows are durable/synced before availability references, merge without revealing another plan's weeks, and preserve the existing revision protection for competing completions.
- [ ] Verify with `flutter test test/training_block_sync_test.dart test/training_block_backup_test.dart test/integration/training_blocks_replicas_test.dart` and the local database/API suite documented in `supabase/tests/training_blocks/README.md`. Follow current Supabase migration tooling; do not apply changes to a remote project during implementation without deployment authorization.
- [ ] Require passing analysis and commit the migration and affected files explicitly.

## Task 6: Verify the complete flow and update current documentation

**Files:** `DESIGN.md`, `docs/splits.md`, `docs/training-blocks/manual-device-checklist.md`, relevant Coach starting-week documentation if its picker changes.

- [ ] Update current documentation to distinguish intended length, allocated shared slots, per-plan available weeks and active progress. Replace the rule that every week in later blocks inherits the preceding block's matching number.
- [ ] Run `flutter analyze` and `flutter test`. Investigate failures; do not relax contrast, typography, identity or recovery checks to make the suite pass.
- [ ] Fully restart the app after the Hive changes. Manually create a four-week block, log Push Week 1 with changed values, verify Pull is untouched, verify Push Weeks 2–4 inherit sequentially, and verify the existing continuation sheet appears only at the limit. Create the next block and verify its Week 1 copies the preceding block's Week 1.
- [ ] Repeat the important transitions after restart and offline/online sync. Verify that a saved draft's custom values survive switching workouts, and that extending the block never immediately moves another workout.
- [ ] Review the diff, stage only intended files and commit the completed changes. Report actual test results and any device or database checks that could not be performed.
