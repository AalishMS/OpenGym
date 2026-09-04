# Split Workspaces

OpenGym treats a split as an independent training workspace. Plans, completed
sessions, history, statistics, personal records, progression suggestions, and
previous-set lookups are always scoped to the active split.

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

Backups use format version 3 and include all splits plus the active selection.
Older backups import into one `My Split`. Global settings remain account-wide;
sample data affects only the active split, while Clear All Data removes workout
data across every split without deleting the split profiles.
