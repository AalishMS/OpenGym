# Online support verification

The production app uses mandatory Supabase authentication and keeps Hive as its
local runtime store. The sync architecture and security invariants are described
in [DESIGN.md](../DESIGN.md).

Deployment checks that require live accounts remain manual:

- In Supabase Auth URL Configuration, set the site URL to
  `https://open-gym.netlify.app` and allow redirects for
  `https://open-gym.netlify.app/**` and `http://localhost:8080/**`.
- Also allow `io.opengym.app://reset-password/` for Android/iOS password
  recovery. Both platforms register this callback; Supabase's `app_links`
  handler exchanges the recovery link using the SDK's existing PKCE flow.
- With a real account, verify sign-up/sign-in on the deployed site, cross-device
  sync with mobile, and an offline reload after the site has been cached.
- Deploy the recovery UI before checking the desktop Forgot password action:
  it opens `https://open-gym.netlify.app/?reset_password=true` in the browser.
  The email request and reset link must use that same browser, so its PKCE
  verifier is available. Mobile requests must open their email link on the same
  installation that requested it.
- Check password recovery with a real account on web and Android/iOS, including
  an app cold start, cancellation, an expired/reused link, a service failure,
  and the new password's sign-in. Confirm that the configured password policy
  is enforced by Supabase (the client only requires a nonempty password with at
  least six characters for account creation/reset).

Mock-server tests cover field validation/focus, reset request/redirect, guarded
submission, failure/result announcements, password confirmation/update, and
keeping recovery visible through subsequent auth events. They do not verify
the deployment's redirect allowlist, email delivery, or device link handling.

The values embedded in `SupabaseService` are publishable client configuration,
not service-role credentials. Row-level security is the security boundary.


## Training-block compatibility

Training-block SQL and client code are locally verified and remain undeployed
by this work. The [local verification record](training-blocks/verification.md)
distinguishes real loopback PostgreSQL/PostgREST + installed-SDK trials from
mocked/widget checks and explicitly pending Android/browser checks.

For a separately authorized rollout:

- Apply the additive training-block migration through the release workflow.
  Verify the API pre-request guard is configured for every exposed workout and
  preference table; nullable columns alone do not protect an activated account.
- Verify authenticated table grants and owner/split RLS/foreign keys against the
  target project's actual Data API configuration. Publishable keys do not bypass
  those controls.
- With isolated accounts, check unactivated legacy reads/writes, then successful
  local safety backup/preparation followed by activation with the capable client.
  Confirm old reads, upserts, deletes and preference writes receive upgrade-required
  errors after activation, including an old request queued across activation.
- On two actual installations, check offline independent workout completion,
  same-number weeks in different blocks, duplicate log access, competing appends,
  late legacy upgrade and matching-week initialization. Check account switch,
  interrupted import/restart, dismissed boundary choices, exact nonactive timer
  resume and Stop confirmation behind sheets/autosaves.
- Check Android cold restart and notification pause/resume/Stop on a device,
  including old persisted notification snapshots. Profile the large-data fixture
  on the project's Android device for frame spikes. These checks are pending by
  user choice; host widget timings and native JVM tests do not replace them.
- Establish full browser workout interaction separately. Web compilation/hot
  restart and targeted real-Chrome storage/recovery/export tests pass; these do
  not certify end-to-end workout interaction.

Activation is an irreversible per-account writer boundary. After activation,
use forward fixes or stop new activations; do not downgrade data to an old
client. Deployment, release, tags and version bumps require separate authorization.

## Exercise identity (schema 3)

Before releasing the exercise identity client, apply
`20261105120000_exercise_identity_catalog.sql` and verify the existing
`training_internal.guard_training_schema` pre-request hook is active in the
production Data API. Migration installation alone must leave existing account
capabilities unchanged.

With isolated test accounts, verify that a schema 3 sync activates only its own
account and that schema 2 reads and writes for that upgraded account return
`PT426`. Accounts which have not upgraded must retain their prior behavior.
Anonymous catalog reads/writes must fail, and one account must not read or
update another account's `exercise_definitions` rows, even with a known ID.

Create a custom exercise on one device, sync, and find it in the picker on a
second device and in another split of the same account. Merge its duplicate
name into the intended movement, then sync both devices in each order. Exercise
statistics and previous sets should combine, all sets and historical names
should remain, and a stale unmerged definition must not reverse the merge.
Repeat while the duplicate has a newer rename timestamp than the merge.

Export and restore format 6, including a merged custom exercise. Restore an
older unmerged same-account backup and confirm the saved redirect survives.
Restore into a different test account and confirm custom IDs and all their
references move together. Switch accounts on a shared device and confirm the
previous account's custom exercise names are absent. Log once more offline,
restart, and confirm that its identity and history remain available.


For interrupted catalog delivery, stop the originating device's upload after a
custom source redirect is accepted but before its custom target is published.
Let a second device receive that prefix, then restart it offline. Local
preparation and Retry must succeed; the last known source/target in the chain
must remain selectable and all its sets must remain available. Publish the
missing target and reconnect the receiving device: its existing logs must now
resolve to that target without rewriting their saved exercise IDs or names.

For same-account restore, export a backup before a custom exercise is merged,
then merge it and extend the live block beyond the backup's duration. Restore
the shorter backup. Training graph IDs should change as required by structural
recovery, while the custom exercise ID and saved merge remain intact and its
strength history stays combined. Repeat with a deleted session and an added
lazy week omitted by the backup.
