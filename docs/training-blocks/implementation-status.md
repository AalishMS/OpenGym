# Training blocks implementation checkpoint

Paused after Task 5 at the user's request. Continue sequentially with Task 6
when instructed. Use `superpowers:executing-plans`, one main implementer, and
[the implementation plan](implementation-plan.md). Do not deploy, release,
push, tag, or bump the version.

## Completed

| Work | Commit |
| --- | --- |
| Task 1: durable records, repository, local migration | `6e5d2df` |
| Task 2: compatibility gate and graph sync | `e497dd7` |
| Independent Task 2 review fixes | `1602596` |
| Task 3: backups, ownership, lifecycle recovery | `e8193a8` |
| Task 4: independent progression and inheritance | `b80c1f3` |
| Independent Task 4 review fixes | `e2d7fa9` |
| Task 5: ID navigation, management, boundary/start UI | `41e52c8` plus this checkpoint commit |

Both requested intermediate review gates are cleared. No deferred minor
findings were reported. The final whole-branch review is still required after
Tasks 6–7. Task 5 has no additional independent review gate in the agreed
workflow.

Task 5 adds the inline block/week strip, management forms, starting-slot
selection for new and duplicated plans, next-entry boundary choices, durable
boundary retries, and ID-based workout selection. Exact duplicate sessions
remain selected after reload. Untouched previews do not create logs; individual
week deletion/rename and automatic max+1 allocation are removed. Save/timer
race, mutation-guard, and layout tests remain covered.

## Verification

- Final full Flutter suite after the header refinement: 820 passed, 2 skipped.
- Final header refinement: six workout-log tests passed; actual-Manrope preview
  test passed in both themes. The selected block/week label remains readable at
  normal phone size; timer width is bounded on narrow/large-text layouts.
- Analyzer: no issues. The final task completion and full-suite outputs are
  recorded in `.superpowers/sdd/implementation-plan/progress.md` (gitignored).
- Widget tests cover 100 blocks with 52 supplied weeks each and construct only
  the expanded block's week controls. The Task 7 10,000-session/device profile
  is still outstanding.
- Web debug compilation and hot restart completed, but the browser fallback
  remained blank and reported no connected debug client. No browser workout
  interaction is certified.
- No Android device or configured emulator is available. The user explicitly
  chose to record Android restart, native-device timer interaction, and device
  profiling checks as pending.

SQL/API and installed-SDK loopback trials passed during Tasks 2–3. They used
isolated PostgreSQL/PostgREST, with no remote deployment. Recheck process state
before using `/tmp/opengym-training-proof` in a resumed session; those processes
and temporary logs are not durable project dependencies.

## Remaining

1. Task 6: introduce `WorkoutDestination.active/week/session`, remove the
   temporary `initialWeekNumber` screen route, re-fetch destinations at delivery,
   add block context to History/resume/native timer, audit date-based analytics,
   and add Coach review starting-slot selection. Run its focused Flutter suites
   and discover/run the existing native Gradle timer tests.
2. Task 7: final full verification, isolated multi-replica/account trials,
   100 × 52 weeks plus 10,000 sessions measurement, and update DESIGN.md,
   docs/splits.md, docs/coach.md, docs/online_support_verification.md. Android
   manual checks remain pending unless a device becomes available.
3. Independent final review of the whole branch from base `358894a`; fix
   Important/Critical findings with observed failing-then-passing regressions
   and a passing full suite before finishing.

The gitignored ledger is the detailed execution record and holds every ruling.
Keep it until final review is complete. Already completed tasks must not be
reimplemented.

## Workspace notes

`analysis_options.yaml` and `pubspec.lock` were already dirty at resume and are
preserved outside the task commits. They contain analyzer exclusions and local
Flutter SDK dependency-resolution changes. Do not sweep them into a feature
commit or discard them without determining ownership. All training-block task
changes are committed at this checkpoint.
