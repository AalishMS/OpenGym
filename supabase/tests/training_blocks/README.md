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
local OS user, load `base_schema.sql`, then the training-block migration. Do not
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
