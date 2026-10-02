# Login / create-account screen

Reviewed 2026-10-02. Scope: both form modes, validation, loading, credential entry. Current code only; old screenshots excluded. Network authentication and confirmation-email behavior were not exercised.

## Findings

- **L01 · Medium · Code-confirmed — no password recovery entry point.** The form offers submit and mode switching only (`lib/screens/login_screen.dart:157`, `lib/screens/login_screen.dart:181`). A returning user who has forgotten the password cannot start recovery from this screen. Add a clearly labeled Forgot password action and a complete recovery/result flow. Backend recovery support and account policy are unverified.
- **L02 · Medium · Code-confirmed — validation is not associated with fields.** Empty fields produce one shared message (`lib/screens/login_screen.dart:35`), rendered below the password field (`lib/screens/login_screen.dart:145`). Neither field gets `errorText` or focus to the first invalid control (`lib/screens/login_screen.dart:96`, `lib/screens/login_screen.dart:108`, `lib/screens/login_screen.dart:212`). Keep the existing live-region message for service failures, but show local errors on the responsible fields and focus the first invalid field.
- **L03 · Low · Code-confirmed — spacing uses literals despite an existing scale.** Padding/gaps of 24/8/32/16dp occur at `lib/screens/login_screen.dart:72`, `lib/screens/login_screen.dart:81`, `lib/screens/login_screen.dart:95`, `lib/screens/login_screen.dart:107`, `lib/screens/login_screen.dart:156`. Replace with `AppSpacing.xl/sm/xxl/lg`. The 420dp content cap and spinner size are component geometry, not automatically spacing-token violations.

## Six checks

| Check | Assessment and evidence |
| --- | --- |
| Visual consistency | Headings/body use theme roles; colors and input radii use helpers/tokens (`lib/screens/login_screen.dart:63`, `lib/screens/login_screen.dart:84`, `lib/screens/login_screen.dart:218`). L03 is the main token debt. No hardcoded hex colors or literal radii found. |
| Hierarchy | One filled action clearly tracks Sign in/Create account, followed by the quieter mode switch (`lib/screens/login_screen.dart:157`, `lib/screens/login_screen.dart:189`). L01 leaves a common recovery task without an action. |
| States | Busy state disables submit/mode switch, uses a named live-region spinner (`lib/screens/login_screen.dart:159`, `lib/screens/login_screen.dart:165`, `lib/screens/login_screen.dart:183`); service errors have a live region (`lib/screens/login_screen.dart:147`). L02 covers validation. Successful sign-up requiring email confirmation is **unverified** because no live auth request was made. |
| Ergonomics | Email/Next and password/Done are configured, with submission on Done and password-visibility tooltip (`lib/screens/login_screen.dart:102`, `lib/screens/login_screen.dart:119`, `lib/screens/login_screen.dart:123`, `lib/screens/login_screen.dart:128`). Autofill is grouped (`lib/screens/login_screen.dart:75`). No number input. Tests assert visibility/mode-switch targets are at least 48dp (`test/login_screen_test.dart:160`). |
| Accessibility | Persistent input labels, appropriate autofill, themed foregrounds, named busy/error states are present (`lib/screens/login_screen.dart:101`, `lib/screens/login_screen.dart:113`, `lib/screens/login_screen.dart:213`). L02 improves error context. |
| Small/large screens | SafeArea, scrolling, and 420dp cap are present (`lib/screens/login_screen.dart:69`, `lib/screens/login_screen.dart:71`, `lib/screens/login_screen.dart:74`). Keyboard visibility plus 1.3x/2x text and very long server errors need runtime verification; no overflow is asserted from old screenshots. |

See [summary](SUMMARY.md).
