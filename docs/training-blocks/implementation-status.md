# Training blocks implementation checkpoint

Tasks 1–7 are locally implemented and verified in the existing
`feature/training-blocks` checkout. The independent final whole-branch review
against base `358894a` is complete and all three Important findings are fixed. Use `superpowers:executing-plans` and
[the plan](implementation-plan.md). No deploy, release, push, merge, tag or
version bump is authorized.

## Completed work

| Work | Commit |
| --- | --- |
| Task 1: records and resumable migration | `6e5d2df` |
| Task 2: compatibility gate and graph sync | `e497dd7` |
| Independent Task 2 review fixes | `1602596` |
| Task 3: backups, ownership and lifecycle | `e8193a8` |
| Task 4: independent progression/inheritance | `b80c1f3` |
| Independent Task 4 review fixes | `e2d7fa9` |
| Task 5: ID navigation, management and boundary/start UI | `41e52c8`, `dd992f3` |
| Task 6: exact destinations, history/timer context and Coach starts | `2c708af` |
| Task 7: isolated replica/scale proof, pull-first append repair and docs | `b6127ff` |

The intermediate review gates are cleared with no deferred minor findings.
Completed tasks must not be reimplemented. Task 6 re-fetches stable destinations
at delivery, retains duplicate logs/orphan details, drops stale timer intents,
and preserves the reviewed Coach starting ID through block reorder.

Task 7's real two-cache trial exposed a pull-before-upload append collision.
Normalization now settles it before strict validation, retaining the canonical
server label and rebasing the pending local week with the existing recovery
journal. Both IDs/logs and independent progress survive. The ordinary suite has
an observed failing-then-passing regression as well as the real API trial.

## Verification and limits

- Full Flutter suite: **838 passed, 3 skipped**. The additional skip is the
  opt-in independent-replica SDK trial; the other skips are the transport SDK
  trial and update-preview rendering. Both SDK trials pass when enabled.
- Analyzer: **no issues**. Build runner succeeded; generated adapters have no diff.
- Real isolated PostgreSQL/PostgREST: **13 passed**. Installed-SDK transport and
  two-independent-cache trials: **2 passed** together, using separate accounts.
- Native Gradle timer tests: **4 passed** with `-PskipDependencyChecks=true` for
  the installed Flutter SDK versus the existing Gradle pin. No version changes;
  this does not certify a supported Android release toolchain.
- The 100 × 52 week / 10,000 session host fixture passed and constructed only
  52 week controls, with zero reloads over five timer seconds. Timing observations
  and profiling limits are in [verification.md](verification.md).
- Four real headless-Chrome recovery cases pass: preparation/export/reopen,
  interrupted replacement recovery, rollback, and owner-scoped cleanup. These
  test browser IndexedDB storage and JSON export, not complete workout UI.
- Task 5 actual-font light/dark workout previews were checked. Web compilation
  and hot restart pass, but no connected browser client's workout interaction
  is certified.
- The focused Android emulator smoke check is recorded below. Physical
  two-device trials and Android frame profiling remain pending.
- SQL/API trials use loopback only. Production configuration, migrations,
  activation and release remain untouched and require separate authorization.

The gitignored ledger at `.superpowers/sdd/implementation-plan/progress.md`
records RED→GREEN evidence, exact commands, rulings and review results. Local
proof services live under `/tmp/opengym-training-proof`; they are temporary test
infrastructure, not project runtime dependencies.

## Final review

The review of `358894a..b6127ff` continued with GPT-6.1 Sol after the earlier
reviewer hit a usage limit. It confirmed three Important findings and no
Critical/Minor findings. One correction pass reproduced and fixed each:

- Public session writes now derive their display label from the current stable
  week ID. Deferred structural refresh after autosave retains entered values.
- Browser recovery uses durable owner-scoped Hive/IndexedDB safety artifacts;
  native file paths and atomic writes stay intact. Recovery, rollback, cleanup
  and export are covered in real Chrome, including reopen.
- Pristine default reuse recognizes both local-null and neutral server-epoch
  stamps, while rejecting genuinely edited structure.

The fix pass has a passing full suite and analyzer. No second review was
requested; regression tests and full verification are the completion gate.
There is no remaining authorized local implementation work. Device checks,
full browser workout interaction, production configuration and release remain
separate pending work; nothing was pushed, merged, tagged or deployed.

## Android emulator smoke check (2026-10-29)

The user authorized a focused Android emulator pass. A headless Pixel 6 AVD
(Android 15 / API 35, x86_64) was launched with SwiftShader because the host
has no display and lacked PulseAudio libraries; those libraries were staged
under `/tmp` without changing system packages. The first Gradle launch hit the
known Flutter 8.14 versus repository Gradle 8.11.1 check. The debug APK built
and installed using `--android-skip-build-dependency-validation`; no pinned
versions changed. For offline interaction only, the run passed empty
`SUPABASE_URL` and `SUPABASE_ANON_KEY` dart defines. No account was activated.

Observed on the emulator:

- Startup completed the ID-key migration (`0 plans, 0 sessions`) without a
  crash. This was an empty-store startup, not a populated legacy migration.
- Created and saved a local plan with Bench Press; opened the workout at Block
  1 · Week 1, edited the set to 60 × 8, started and paused its timer, and logged
  the workout (recorded duration about 1:11).
- The completed-workout boundary prompt offered Add week, Create block, and Not
  now. Add week advanced to Block 1 · Week 2 and displayed the prior 60 × 8
  alongside the initialized 60 × 8 values.
- Force-stopping and relaunching retained the plan and completed History entry.
  Starting the next workout reopened the incomplete Week 2 session at Block 1
  · Week 2 with its 60 × 8 values and previously elapsed 00:05 timer. The Home
  screen itself did not auto-navigate to the workout; tapping Start workout
  resumed it.

The emulator initially displayed a System UI not-responding dialog during
software-renderer startup; selecting Wait restored interaction. Startup logged
skipped frames during initialization, so no frame-performance conclusion is
claimed. This is emulator-only evidence: no physical device, second-device
trial, populated legacy-store migration, second-block CRUD, or frame profiling
was performed. The default-config sign-in gate was not exercised; the test run
was explicitly offline-only.

## Workspace ownership

Pre-existing unstaged `analysis_options.yaml` and `pubspec.lock` are preserved
outside task commits. Their SHA-256 values remained unchanged through Task 7
code generation. Keep unrelated changes out of feature commits.
