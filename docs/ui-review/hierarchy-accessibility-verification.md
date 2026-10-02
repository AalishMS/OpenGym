# Hierarchy and accessibility follow-up

Implemented 2026-10-02, screen by screen against the confirmed findings in
[the review summary](SUMMARY.md).

| Findings | Result |
| --- | --- |
| H02 | Every ordinary Home plan row has a named 48dp overflow action. Long press remains available. |
| DB02 | Completed sessions open their saved details by identity. Draft sessions resume their exact week and identity, including with renamed/deleted plans and competing sessions in the same week. |
| W04 | Disabled Finish explains the Start prerequisite beside the button. |
| W05 | Week rename filters numeric entry, shows field errors, accepts Done, and disposes its controller. |
| P04 | Plan editor Back uses the shared named button with button semantics. |
| DB03 | The sparkline exposes the full weight series in session order, including intermediate rises/falls and units. |
| L01/L02 | Forgot password, email request/result, recovery password/confirmation, field errors, invalid-field focus, guarded submission, and service-error announcements. |
| I02, HI02, ST03, D02 | Spoken intro page position, semantic intro/month/statistics headings, and saved-set values with set context, units, and PR status. D02 is also included in the numeric-accessibility commit. |

The existing Supabase SDK uses PKCE and processes incoming links before the app
starts. Recovery is retained across replayed auth events and subsequent user/token
updates. The gate wraps the root Navigator so recovery and link failures remain
visible above open workout/editor routes. Same-account recovery preserves the
route and draft; an account change replaces the actual Navigator key and prepares
the new account. Password entry is bound to the recovered user and cleared when
that user changes.

Android/iOS register the recovery callback. Desktop recovery opens the deployed
web request form so the email request and link exchange use the same browser's
PKCE verifier. See [online support verification](../online_support_verification.md)
for required redirect configuration and real email/device checks.

The concurrent persistence follow-up adds named progress for intro completion
(I04) and saved-workout editing (E04). Those changes remain separate from this
commit; the final checkout includes them.

## Verification

- Targeted widget tests cover independent Home overflow, exact Dashboard session
  navigation, draft identity after provider refresh, disabled Finish explanation,
  invalid week input/Done, sparkline semantics, named Back, headings/page position,
  and set-specific units/PRs.
- Authentication tests use a mocked Supabase transport: validation, redirect,
  pending requests, errors, confirmation, successful password update, replayed
  recovery, incoming link errors, account changes, and pushed-route draft retention.
- Related intro, history, statistics, accessibility, login, recovery, hierarchy,
  and theme-contrast tests pass. Test fonts are deterministic SDK fixtures; these
  checks do not certify production typography or actual screen-reader output.
- The isolated commit snapshot passes static analysis with no issues and all
  **33** login/recovery/hierarchy widget tests. The related checkout suite passed
  **123** tests before the final account-switch regression was added; that
  regression also passes in the isolated snapshot.
- Initial checkout analysis reported no errors or warnings and four style infos
  in concurrent Settings/Workout edits. Final checkout analysis has no issues.
- A broader run hit a timeout in Home's exercise-reorder test and later stalled
  in its plan-switch test while concurrent persistence edits were present. That
  run was stopped; it is not reported as a passing full suite.
- Live email delivery, Supabase allowlisting, cold-start device callbacks,
  expired/reused real links, and TalkBack/VoiceOver output remain manual checks.
