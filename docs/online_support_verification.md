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
