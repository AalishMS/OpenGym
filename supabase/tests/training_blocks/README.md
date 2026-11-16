# Isolated training-block compatibility proof

The base schema fixture was reconstructed from read-only catalog queries on the
OpenGym database on 2026-10-28 (PostgreSQL 17.6.1.155), before training-block changes.
It contains schema metadata only; JWT helpers and roles are local test scaffolding.

Inventory findings:

- Plans/sessions have UUID primary keys, owner FKs to `auth.users`, and composite
  `(split_id,user_id)` FKs to splits with hard-delete cascades for account erasure.
- Sessions have nullable `plan_id`, **without a plan FK**. Dangling historical plan
  IDs can be retained. No session-slot unique constraint exists.
- `server_seq` is `timestamptz`, populated by `touch_server_seq()` using `now()`.
  It is neither a sequence nor a commit-order guarantee.
- The four workout tables have owner RLS. Authenticated grants permit read/insert/
  update; plans/sessions also permit direct DELETE. Anonymous access is revoked.
- Existing helpers are invokers with empty search paths and execution revoked
  from PUBLIC/anon/authenticated. The only public security-definer routines are
  Coach usage helpers callable by service_role, not app users.
- Neither authenticator role settings nor database-role settings contain a
  `pgrst.db_pre_request` override. Deployment configuration still needs a live
  API check; a catalog inventory cannot prove an external configuration value.
- Supabase CLI 2.122.0 and installed Dart supabase 2.14.0 were inspected. The SDK
  accepts initialization headers and forwards them to PostgREST.

No remote schema change or account activation was performed for this inventory.

## Running the isolated checks

Use PostgreSQL 17.6 and PostgREST 16.5, listening only on `127.0.0.1:55439` and
`127.0.0.1:55440`. Create the database `opengym_training_blocks_test` owned by your
local OS user, load `base_schema.sql`, then every migration from
`20261028072415` onward, in order (the training-block schema, lazy independent
weeks, the exercise identity catalog, and the block lifecycle). The fixture
already contains the earlier split migrations. Do not
load this fixture into a Supabase project. The Python tests truncate **only this
named loopback test database** before every case.

PostgREST configuration:

```ini
db-uri = "postgresql://<local-user>@127.0.0.1:55439/opengym_training_blocks_test"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "opengym-training-blocks-isolated-test-secret-32-characters"
server-host = "127.0.0.1"
server-port = 55440
```

Install `psycopg[binary]` in an isolated Python environment, then run:

```bash
python3 supabase/tests/training_blocks/test_api.py
python3 supabase/tests/training_blocks/test_lazy_weeks.py
python3 supabase/tests/training_blocks/test_block_lifecycle.py
python3 supabase/tests/training_blocks/test_exercise_identity.py
flutter test --dart-define=OPENGYM_LOCAL_API_TESTS=true test/integration/training_blocks_api_test.dart
flutter test test/training_block_sync_test.dart test/sync_sequence_test.dart test/sync_data_flow_test.dart
flutter analyze
```

Run the Python suite before the SDK trial to seed its accounts and workouts.
The SDK trial is skipped by the ordinary Flutter suite because it requires this
local API. It verifies actual SDK header transport, pulls more than two pages of
equal-timestamp rows, retains duplicate-slot sessions, and uploads a session edit.
The mock honors requested sort direction: the installed SDK defaults to
**descending**, so every forward page explicitly requests ascending order.

The SQL/API suite covers irreversible per-account activation, old read/upsert/
DELETE/preference errors, unactivated accounts, owner and split boundaries,
UUID vectors, sparse union/backfill, preserved sets/timers/orphan IDs, invalid
input rollback, parent tombstones, stale plans/sessions/preferences/progress,
revision tie-breaking, both legacy/random label arrival orders, concurrent
activation, and an old HTTP write held across activation.

These checks prove the isolated schema/API. They do not certify production
pre-request configuration, authorize deploying this migration, or activate any
production account.

Bootstrap rows use neutral edit timestamps (null locally, epoch on first SQL
insert), and the client inserts them only when absent. Existing server structure
wins over synthetic defaults, while explicit local edits use normal LWW. Local
week relabels also flush a fixed-week recovery intent before changing the week or
session labels; startup and sync finish that intent before graph validation.

A second opt-in SDK trial uses the other fixture account and two independent
Hive directories:

```bash
flutter test --dart-define=OPENGYM_LOCAL_API_TESTS=true test/integration/training_blocks_replicas_test.dart
```

It performs independent offline completions with lazily allocated successors,
creates competing appends with the same canonical slot identity,
syncs each cache in turn, and checks both stable IDs/logs, independent progress
and Week 1 cross-block initialization. It cleans up its own temporary split through
the loopback API. This reproduces a pull-before-upload collision that push-only
retry tests cannot exercise; client normalization must reconcile the accepted
remote label with the pending local append before strict graph validation.

The lazy-week suite verifies schema 2 activation and schema 1 rejection for
upgraded accounts, intended duration without eager slot allocation, independent
per-plan availability, metadata backfill without progress/revision changes, and
rejection of invalid/foreign available week references. Session JSON remains
version 1. New lazy slots use a deterministic block/number UUIDv5 ID so two
replicas do not turn one logical Week 2 into Weeks 2 and 3. The Python suites
truncate only the named loopback fixture; never run them against a remote project.


The exercise identity migration adds schema 3. Its standalone SQL proof creates
its own temporary database on the loopback PostgreSQL instance, applies the
base fixture and all four migrations, then drops only that database:

```bash
python3 supabase/tests/training_blocks/test_exercise_identity.py
```

Python 3 must have `psycopg` installed. The test covers custom catalog RLS and
grants, shared IDs under different account keys, durable merge precedence over
newer unmerged writes, stale edits, and schema 2 rejection after activation.
The existing schema 1/2 suites remain useful compatibility proofs for accounts
which have not activated schema 3. Apply the catalog migration to a separate
fixture before running the current opt-in SDK trials; those now send schema 3.

The block lifecycle migration adds schema 4 (`test_block_lifecycle.py`): the
`planned_week_count_updated_at` duration clock (newer clock wins, a tie keeps the
larger count, a null count never replaces a stored one, and a writer that omits
the clock ties with the stored value, so schema 1-3 writers stay grow-only), and
`public.delete_training_block(target uuid)`, which tombstones an unused block
and its weeks in one transaction under the account lock. It refuses with PT409
(`last_block`, `in_use`, `split_deleted`) and PT426 below schema 4, returns null
for an unknown or foreign id, and is idempotent. An account activated at 4
rejects headers 1-3 with PT426. `test_lazy_weeks.py` must keep passing unchanged:
it is the proof that the legacy rule survives.

`RescueAndLosingUpsertTest` (same file) covers the rescue contract: a session in a
tombstoned week can move to a live week of another block with its completion
evidence re-pointed (and only re-pointed), a progress row that wins last-write-wins
is accepted, and an upsert that loses it is a silent no-op even when the stored
row's parent is a tombstone. Its race tests open two direct connections and take no
advisory lock: the delete RPC row-locks the block's weeks, and every session /
progress write holds its week `FOR SHARE`, so the in-use check cannot miss a write.
