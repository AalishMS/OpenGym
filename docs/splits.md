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

Backups use format version 5 and include all splits, intended block lengths,
allocated weeks, per-plan available/active weeks, linked logs, owner provenance
and the active selection. Versions 1–4 are normalized on import;
foreign/unknown-provenance copies receive new IDs. Global settings remain account-wide;
sample data affects only the active split, while Clear All Data removes workout
data across every split without deleting the split profiles.

## Blocks and workout progress

A new workspace supplies Block 1 / Week 1. Blocks and week identities are
shared; available weeks and active progress are independent for each workout.
A block's chosen length is its intended duration, not a request to allocate
all weeks upfront. A four-week block starts with Week 1. Logging Push creates
or reuses its next slot and reveals it only for Push; Pull remains unchanged.
Each later week inherits that workout's preceding completed week within the
block. A new block's Week 1 retains matching Week 1 inheritance from the
preceding block.

Only logging advances progress. After the intended final week, the next
ordinary entry offers the existing boundary choices; dismissal keeps the result
and Choose next week action. Add week extends the shared intended duration and
moves only the choosing workout. The strip cannot add future weeks early.
New/duplicated/Coach-added plans choose their start from intended weeks, with
allocation deferred until saving; existing plan edits retain their position.

Create, rename and reorder blocks, or extend a block at its boundary. Individual
block/week deletion and week rename/reorder are unavailable. History still
includes every completed live session by date across blocks, even when its
original plan no longer exists. Exact-session resume keeps duplicate logs and
nonactive started drafts distinct. See [DESIGN.md](../DESIGN.md) for inheritance,
completion recovery, backup ownership and the irreversible account compatibility
boundary. Local API verification is recorded in
[training-blocks/verification.md](training-blocks/verification.md); deployment
and native-device checks remain separate.
