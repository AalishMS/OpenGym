# Exercise identity verification — 2026-11-05

Target: production `uhvemfdgxlhpalmkulnv`, client 1.0.17+18.
This record distinguishes live API checks, local automated checks and pending
installed-device checks. No production schema changes were made.

## Production checks passed

- Migration `20261105120000` is installed. The authenticator role configures
  `pgrst.db_pre_request=training_internal.guard_training_schema`.
- Before testing, all three capability records were schema 2. The installed
  migration source contains no account activation DML. This supports installation
  leaving capabilities unchanged, but no pre-migration snapshot was available
  to prove historical equality for every account.
- The supplied primary test account could read using schema 2 before activation.
  A real authenticated schema 3 activation returned 3. Only that account's
  capability changed; the other two remained at 2.
- After activation, schema 2 GET, POST, PATCH and DELETE requests against
  `exercise_definitions` returned HTTP 426 / `PT426`. Schema 3 reads succeeded.
- Unsigned GET and POST returned HTTP 401 / `42501`.
- The supplied second account credentials failed. A disposable account was
  created with authorization. Its unactivated schema 2 GET and POST succeeded.
  Its GET and PATCH against a known primary-account exercise ID returned no
  rows; a foreign-owner INSERT returned HTTP 403 / `42501`. The original row
  remained unchanged. A separate transactional database role check also found
  no visible or updateable foreign row.
- A source merge was accepted before the target existed. A later unmerged
  update with a newer rename timestamp did not remove the redirect or replace
  the source name. The target could subsequently be inserted.
- Temporary API exercise fixtures and the disposable account were deleted.
  The primary test account remains at schema 3; it was not downgraded.

These API requests exercise production PostgREST and RLS, but do not constitute
an entire app sync or two-device trial.

## Local automated checks passed

81 tests passed with real Hive storage and mocked HTTP:

```sh
flutter test test/exercise_identity_test.dart test/exercise_management_test.dart test/training_block_sync_test.dart test/training_block_backup_test.dart test/exercise_picker_sheet_test.dart --reporter expanded
```

Coverage includes combined strength/records/volume/previous sets with preserved
historical names, IDs and sets; both merge conflict directions including a newer
unmerged rename; format 6 round-trip; foreign-account reference remapping;
older same-account backups preserving redirects; shorter-block, deleted-session
and omitted-week recovery; catalog clearing on account handover; custom creation
surviving Hive reopen; and interrupted prefix delivery, offline reopen and late
target resolution without rewriting saved log identity.

## Installed Android checks and remaining gaps

The emulator initially contained 1.0.16+17 and invalid split data, showing Data
recovery with `FormatException: Invalid split names or count`. With explicit
permission, that installation and storage were removed. Current 1.0.17+18 built,
installed and started successfully through onboarding to sign-in.

Automation stopped at sign-in: email fill returned `Field focus was refused`;
the advised debug retry returned `Ref @e5 belongs to an expired ref frame`.
Device instructions require stopping after that retry fails. This is an
automation blocker, not an observed schema 3 app defect.

Still pending on actual installations:

- Picker propagation across two devices and splits; complete sync in both orders.
- Combined stats and previous sets after real server/device merge conflicts.
- Backup export/restore UI for format 6, old same-account and foreign accounts.
- Account switching UI and offline workout logging followed by cold restart.
- Interrupted sync and offline Retry UI, followed by late-target delivery.
- Shorter-block, deleted-workout and omitted-week restore UI trials.

The local tests cover the corresponding storage/service behavior, but do not
replace these installed-device checks. This checklist is not fully certified.
