# Exercise identity and catalog

`ExerciseDefinition` describes a reusable movement. `ExerciseTemplate` is an
occurrence in a plan, and `Exercise` is an occurrence in a workout with its own
sets and note. Both occurrences retain a name snapshot and a nullable legacy
`exerciseId`. New writes supply an ID. The snapshot is never an identity key.

The catalog belongs to the account, across splits. Statistics, records, and
previous-set references retain their existing split and workout scopes. Bundled
movements have explicit permanent IDs in `ExerciseLibrary.idsByName`; renaming a
label must not change its ID. Newly created custom movements use UUID4. The
`exercise_definitions` Hive box stores JSON for custom definitions and account
specific overrides of bundled entries. It is cleared on account handover and
adopted with other offline data on first sign-in.

Search includes names, aliases, and merged source names. Creating a custom
exercise reuses an exact unambiguous catalog match, and suggests similar
movements for explicit selection. Suggestions never establish identity. For
example, `DB Bench Press` is a reviewed alias of `Dumbbell Press`, but `DB Press`
is ambiguous and stays separate until the user chooses a movement or merges it.
Flat, incline, and shoulder presses have different IDs.

## One name per movement

A movement's name is its catalog name. Every plan, workout, log, Home card and
chart shows `ExerciseCatalog.label(name, exerciseId)`: the catalog name of the
occurrence's canonical identity, falling back to the stored snapshot only for a
movement the catalog does not know yet. Snapshots are still written (new
occurrences take the current catalog name) and kept for backups, legacy
identity resolution and older app versions, but they are never what decides a
label.

Renaming is therefore one catalog write, the same from a workout's *Rename
exercise* and from Settings → Manage exercises (`showExerciseRenameDialog` →
`ExerciseRenameService.rename` → `ExerciseCatalog.rename`). The ID is kept, no
plan or workout row is rewritten, and the previous name becomes a search alias.
Bundled movements can be renamed too: the account stores a copy of the bundled
entry under the same permanent ID, which also inherits any alias the library
gains later. A name another movement already goes by (its name or an alias,
`ExerciseCatalog.nameOwner`) is refused by the catalog; the dialog offers to
merge into that movement instead. A movement the catalog has not seen is
recorded under its current name before being renamed.

Older app versions could only rename a bundled movement by rewriting the
snapshots in one split's plans and workouts. `ExerciseNameAdoption` keeps
those names once per account during local preparation: each bundled movement
whose plans call it something else (the most recently saved plan wins; the
latest workout when no plan has it) takes that name, stamped with the epoch so
any deliberate rename on any device wins. It skips movements already renamed or merged,
custom movements (every older rename already updated their catalog name),
names another movement goes by, and the old name of a movement merged into it.
It waits until the account has a plan on the device.

How a movement is measured follows its ID as well: `ExerciseLibrary` gives each
bundled ID a kind (weighted, bodyweight or timed), and `ExerciseCatalog.kindOf`
and `isTimed` resolve the canonical ID. A renamed Plank still stores seconds; a
custom exercise is weighted whatever it is called.

## Migration and merging

`ExerciseIdentityMigration.prepare` is pure and repeatable. It links normalized
exact names and reviewed aliases to bundled or supplied custom definitions.
Unmatched legacy names use UUIDv5 of the normalized name, so independently
migrating devices agree. Normalization trims, collapses whitespace, and ignores
case; it does not guess abbreviations. Explicit existing IDs always win over
names. Weights, reps, RPE, notes, exercise order, session IDs, dates, and edit
timestamps are retained. Changed parents become dirty without being stamped as
a new user edit.

Startup, import, new-graph installation, and late remote delivery use the same
migration. Training normalization writes an owner-scoped safety artifact before
linking legacy rows. Custom definitions and redirects are included in graph
recovery snapshots. An interrupted migration can run again with the same IDs.

Settings → Manage exercises lists the movements the account trains first, with
their usage, and lets the user merge one into another after a confirmation
that says it can't be undone; renaming to another movement's name offers the
same merge. The source stores `mergedIntoId`; no plan or workout sets are
rewritten or removed. Every identity consumer resolves redirect chains, so
older backups and late uploads also combine. Catalog rows are delivered
individually, so a redirect may arrive before its custom target. That unresolved
dependency is retained unchanged, while identity resolution stops at the last
known definition. The known movement remains selectable and its logs remain
usable offline; startup, retries, recovery snapshots, and backups do not require
network metadata to become available. When the target arrives, the catalog cache
is invalidated and the full chain resolves automatically, including cycles.
Ownership and redirect shape validation remain strict; no target definition is
invented from the redirect alone.

Statistics are computed from the original sets, including multiple occurrences
in one session. Session record events combine those occurrences, and block gains
use their best estimated 1RM.

A merge takes precedence over an unmerged copy, regardless of clock skew.
Conflicting merged destinations follow whole-row LWW. Opposing offline merges
can form a cycle; resolution deterministically uses the smallest ID in that
cycle. Exactly that representative remains visible in the picker. A restore
cannot erase an existing redirect with an older unmerged definition. Catalog
entries are retained when replacing workout graphs, because the library is
account-wide and old references may still arrive.

## Backup and cloud compatibility

Backup format 6 includes exercise definitions, redirects, and all occurrence IDs.
Imports of versions 1–5 migrate identities; format 6 rejects missing identities
or custom definitions. Foreign-account imports remap custom IDs and every
reference/redirect together; bundled IDs remain shared. Missing custom merge
target IDs receive fresh mappings too, so they cannot resolve to an unrelated
exercise already present in the destination account. Same-account restores
preserve exercise identities even when shortening a block, removing a lazy slot,
or restoring deleted records requires fresh training graph IDs.
`TrainingBlockGraph.remap` requires an explicit `remapExerciseIds` choice:
structural restores pass false, while foreign/unknown-provenance imports pass
true. Format 6 still requires a definition for every custom ID used directly by
a plan or session; only a merge target's not-yet-delivered metadata may be absent.

Cloud catalog rows are keyed by `(user_id, id)` and protected by owner RLS.
Anonymous access and client DELETE are revoked; authenticated clients can
select, insert, and update their own definitions. The catalog is pulled in full
before the workout graph and pushed before plans and sessions. Dirty records
remain on the device if any request fails.

Apply `20261105120000_exercise_identity_catalog.sql` before releasing the client.
It extends the existing per-account training compatibility gate to schema 3.
Installation alone upgrades no account. On successful local preparation the
updated client negotiates schema 3 before any upload. Older clients are then
rejected for that account, preventing them from stripping occurrence IDs from
plan/session JSON. Session `trainingSchemaVersion` remains 1 because the
training-slot representation is unchanged. Deploying SQL and verifying the
production pre-request hook are separate release actions, not consequences of
editing the repository.

## Verification

Run `flutter test` and `flutter analyze`. Focused coverage includes
`exercise_identity_test.dart`, `exercise_management_test.dart`,
`training_block_sync_test.dart`, and the existing migration, recovery, backup,
Coach, statistics, editor, and logger suites.

The isolated SQL proof in
`supabase/tests/training_blocks/test_exercise_identity.py` requires Python 3 with
`psycopg` and the existing loopback PostgreSQL fixture on port 55439. It creates
and drops only its own temporary database, applies the base fixture and all
three training/catalog migrations, and checks account isolation, grants, stale
writes, merge precedence, and old-client rejection. No production account is
activated by these tests. Production API configuration still needs the checks
in `docs/online_support_verification.md`.
