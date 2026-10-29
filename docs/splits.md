# Split Workspaces

OpenGym treats a split as an independent training workspace. Plans, completed
sessions, history, statistics, personal records, progression suggestions, and
previous-set lookups, shared blocks/weeks and independent plan progress are scoped to the active split.

## Using splits

- Open the split control in the top-right of the Home header to switch
  workspaces.
- Select `New split` to create an empty workspace.
- Select `Manage splits` to rename or permanently delete a split.
- Up to five active splits are supported. Names are 1–24 characters and must be
  unique for the account, ignoring letter case.
- Deleting the active split requires choosing its replacement first. The dialog
  shows how many plans and sessions will be removed.

The active selection is synchronized across the account on the normal sync
cadence. Every split remains cached locally, so switching works offline.

## Data behavior

`SplitProvider` owns the available splits and active selection. Plan and session
providers listen to it and reload their split-scoped repository views when the
selection changes. A workout already in progress retains the split from its
plan.

Split deletion is irreversible in the product. Locally and in Supabase it is
represented by durable tombstones so an offline device cannot restore deleted
workout data during a later sync.

Backups use format version 4 and include all splits, empty blocks/weeks, per-plan
progress, linked logs, owner provenance and the active selection. Versions 1–3
are normalized on import; foreign/unknown-provenance copies receive new IDs. Global settings remain account-wide;
sample data affects only the active split, while Clear All Data removes workout
data across every split without deleting the split profiles.

## Blocks and workout progress

A new workspace supplies Block 1 / Week 1. All workouts share its structure;
each workout has its own active slot. The logger expands the selected block
inline, constructs only its week controls, and uses durable IDs for navigation.
Only logging advances progress through supplied weeks. At a block boundary the
next ordinary entry offers an explicit next step; dismissing keeps the result
and a Choose next week action. Adding a shared week moves only the workout
choosing that action. New/duplicated/Coach-added plans choose their start;
editing an existing plan retains its position.

Create, rename and reorder blocks, or append weeks to a chosen block. Individual
block/week deletion and week rename/reorder are unavailable. History still
includes every completed live session by date across blocks, even when its
original plan no longer exists. Exact-session resume keeps duplicate logs and
nonactive started drafts distinct. See [DESIGN.md](../DESIGN.md) for inheritance,
completion recovery, backup ownership and the irreversible account compatibility
boundary. Local API verification is recorded in
[training-blocks/verification.md](training-blocks/verification.md); deployment
and native-device checks remain separate.
