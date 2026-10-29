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
- Establish browser workout interaction separately; web compilation/hot restart
  alone has passed, with no connected browser client certified.

Activation is an irreversible per-account writer boundary. After activation,
use forward fixes or stop new activations; do not downgrade data to an old
client. Deployment, release, tags and version bumps require separate authorization.
