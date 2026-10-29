# Training blocks verification

Local verification uses the existing `feature/training-blocks` checkout and
isolated loopback services. It does not deploy SQL/Edge Functions, activate a
production account, publish a client or certify a device release.

## Automated checks

Final full Flutter suite: **838 passed, 3 optional skips**. Analyzer: **no issues**.

The final independent whole-branch review of `358894a..b6127ff` was completed
with GPT-6.1 Sol after the earlier reviewer hit a usage limit. Three Important
findings were reproduced and corrected in one test-verified pass: stale labels
from unsaved edits during rebase, browser filesystem-only recovery storage,
and neutral epoch stamps preventing pristine default-split reuse after sync.
No Critical or Minor findings were reported; no second review was dispatched.

- The normal Flutter suite includes the final review regressions plus storage, migration, backup ownership,
  interrupted-write/reopen recovery, account invalidation, progression,
  inheritance, exact routes, notification deferral, boundary/start controls,
  History, date-based analytics and Coach selection.
- `supabase/tests/training_blocks/test_api.py`: 13 real PostgreSQL/PostgREST
  cases passed. They exercise the irreversible account boundary, queued old
  writes, grants/RLS/relationships, sparse/late legacy rows, LWW, tombstones,
  capacity replacement and UUID fixtures. The test fixture refuses remote
  hosts/databases; see its [setup](../../supabase/tests/training_blocks/README.md).
- `test/integration/training_blocks_api_test.dart`: installed SDK transport
  passed against the loopback API, including 1,003 equal-timestamp additional
  sessions, duplicate-slot retention and a real uploaded session edit.
- `test/integration/training_blocks_replicas_test.dart`: two independent Hive
  directories passed offline Push/Pull completion and competing append trials
  against the real API, then converged through successive syncs. Both append
  IDs and both logs survive, each plan advances independently, and later-block
  matching-week initialization copies the performed values. It uses the other
  isolated account so it can run alongside the transport trial.
- Native `:app:testDebugUnitTest`: 4 passed. Legacy snapshots default to no
  block text; labeled pause/resume retains the exact session ID. The installed
  Flutter SDK requires a newer Gradle than the repository pin, so local tests
  used `-PskipDependencyChecks=true`. No version files were changed. This is
  unit-test evidence, not supported release-toolchain certification.
- Four headless-Chrome tests pass using real Hive IndexedDB: preparation and
  export after reopen, interrupted replacement/reopen recovery, explicit
  rollback, and owner-scoped cleanup. Native file paths/protocol remain intact.
  The dedicated browser safety box keeps full snapshots out of settings and
  operation intents. This verifies recovery storage, not end-to-end workout UI.
- Hive build runner completed and generated adapters match the committed files.
  Its older analyzer dependency reports an SDK language-version warning; the
  generated files compile and `flutter analyze` remains the final lint gate.

Run the SQL suite before the SDK trials to seed their two isolated accounts:

```bash
python3 supabase/tests/training_blocks/test_api.py
flutter test --dart-define=OPENGYM_LOCAL_API_TESTS=true test/integration/training_blocks_api_test.dart test/integration/training_blocks_replicas_test.dart
flutter test test/training_block_scale_test.dart
# Set CHROME_EXECUTABLE to an installed Chrome/Chromium when needed.
flutter test --platform chrome test/training_recovery_web_test.dart
./android/gradlew -p android -PskipDependencyChecks=true :app:testDebugUnitTest
flutter analyze
flutter test
```

The ordinary suite skips the loopback-only SDK trials unless explicitly enabled.
The execution ledger records exact commands, full-suite totals, commits and
review findings in `.superpowers/sdd/implementation-plan/progress.md`.

## Scale observation

The real-Hive/widget fixture contains 100 blocks × 52 weeks and exactly 10,000
sessions. On the development host's debug VM, its first index build took
52.844 ms and an explicit reload took 36.658 ms. Only the expanded block's 52
week controls were constructed; the last selected slot was visible. Five timer
seconds caused zero provider reloads and retained the same session index.

These are observations from one host run, not Android frame measurements,
performance thresholds or universal timing guarantees. Source review confirms
chip status uses the per-slot index and timer ticks update the elapsed display;
history/source selection occurs on selection/reload, outside those paths.

## Android emulator smoke check (2026-10-29)

The user authorized a focused Android run on the headless Pixel 6 AVD (Android
15 / API 35, x86_64). The host had no display and the emulator initially lacked
PulseAudio libraries, so compatible libraries were staged under `/tmp` and the
AVD ran with SwiftShader. No system packages or project versions were changed.
The first `flutter run -d emulator-5554` attempt was stopped by the known
installed-Flutter minimum Gradle check; retry with
`--android-skip-build-dependency-validation` built and installed the debug APK.
The offline-only
run used empty `SUPABASE_URL` and `SUPABASE_ANON_KEY` defines; no account or
production backend was involved.

- Startup log: `id-key migration OK: 0 plans, 0 sessions.` This checks empty
  startup only; no populated legacy migration fixture was loaded on Android.
- Created a local plan and Bench Press workout, edited the first set to 60 × 8,
  started/paused the timer, then logged the workout at roughly 1:11.
- The end-of-block prompt offered Add week, Create block, and Not now. Add week
  advanced from Block 1 · Week 1 to Block 1 · Week 2; prior performance and the
  new set both displayed 60 × 8.
- After force-stop/relaunch, the plan and completed Week 1 History entry
  remained. Home's Start workout reopened the incomplete Week 2 session with
  Block 1 · Week 2, 60 × 8, and the prior elapsed timer value of 00:05.
- Home did not auto-open the in-progress workout; resumption required tapping
  Start workout. The test therefore verifies persisted resume context through
  the normal plan entry, not automatic route restoration.

The emulator showed a System UI not-responding dialog during software renderer
startup; selecting Wait restored the app. Startup emitted skipped-frame logs,
so device performance is not certified. Physical-device behavior, two-device
trials, populated Android legacy migration, second-block CRUD, default-config
auth, and frame profiling remain unverified. Physical two-device lifecycle and
network trials remain pending; independent local cache/API trials cover
persistence/convergence.

## Other pending checks

Web debug compilation and hot restart completed. The server reported no
connected debug client; browser workout interaction remains unverified.
Separate real headless-Chrome recovery tests pass as listed above. Full browser
workout interaction remains unverified. Actual-font light/dark workout previews
were checked at the Task 5 checkpoint.

Before a separately authorized rollout, verify the target API's pre-request
hook, exposed-table grants and RLS, migration history, old-client rejection and
account activation only after successful local backup/preparation. Validate
with isolated live accounts and native devices. Activated accounts cannot be
rolled back to an old writer: use forward fixes or stop new activations. Follow
the existing signed universal-APK/version-code release procedure only when a
release is explicitly authorized.
