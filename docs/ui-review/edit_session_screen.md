# Edit workout screen

Reviewed 2026-10-02. Scope: `EditSessionScreen` in `history_screen.dart`, workout name, exercise/set editing, notes/RPE, confirmations and Save. Outdated screenshots excluded.

## Findings

- **E01 · High · Code-confirmed — Back silently discards unsaved edits.** The screen edits a copied session (`lib/screens/history_screen.dart:443`), mutates only that draft (`lib/screens/history_screen.dart:656`), and persists only in `_save` (`lib/screens/history_screen.dart:503`). It returns a plain `Scaffold` with the default AppBar Back (`lib/screens/history_screen.dart:534`) and no dirty tracking/PopScope/discard prompt. Protect both toolbar and system back, preserving the draft until Save or an explicit discard. Actual device-back behavior has not been manually exercised.
- **E02 · Medium · Verified shared-widget semantics — keypad hides the current weight/rep value.** This screen uses `SetEntryTable` (`lib/screens/history_screen.dart:763`); the keypad's selected-field wrapper excludes child semantics without providing a value (`lib/widgets/workout/set_entry_table.dart:937`). The probe saw “Set 1 Kg” with an empty semantic value although 100 was displayed. Apply K01.
- **E03 · Medium · Code-confirmed — fitted values can defeat text scaling.** Shared editable number cells use proportional columns and scale-down fitting (`lib/widgets/workout/set_entry_table.dart:374`, `lib/widgets/workout/set_entry_table.dart:655`); narrow editing rows already trade away Previous (`lib/widgets/workout/set_entry_table.dart:186`). Apply K02 rather than relying solely on no-overflow tests.
- **E04 · Low · Code-confirmed — Save loses its accessible name while saving.** The labeled Save text is replaced by an unlabeled spinner (`lib/screens/history_screen.dart:540`, `lib/screens/history_screen.dart:544`). Keep a “Saving workout” label/live region around the progress indicator, matching the login busy-state pattern.

## Six checks

| Check | Assessment and evidence |
| --- | --- |
| Visual consistency | Name field/cards use tokens and text roles (`lib/screens/history_screen.dart:564`, `lib/screens/history_screen.dart:720`). No hardcoded page hex/radius/recurring spacing issues found; shared numeric role overrides are covered by K02. |
| Hierarchy | Save remains in the app bar (`lib/screens/history_screen.dart:539`); each exercise has clearly labeled Delete and Add set (`lib/screens/history_screen.dart:739`, `lib/screens/history_screen.dart:771`). App-bar-only Save can be harder to reach on tall phones; its practical impact is unverified. |
| States | Save has repeat-submit guard, disabled inputs, preserved draft on error and a retry message (`lib/screens/history_screen.dart:504`, `lib/screens/history_screen.dart:518`, `lib/screens/history_screen.dart:563`). Empty exercises/sets are explicit (`lib/screens/history_screen.dart:577`, `lib/screens/history_screen.dart:752`), and removal is confirmed (`lib/screens/history_screen.dart:453`). E01 concerns leaving without saving; E04 concerns progress semantics. |
| Ergonomics | Standard controls and set-detail minimum targets are covered by tests (`test/history_redesign_test.dart:633`). Shared keypad avoids OS number keyboard overlap, but physical number-key input is missing (K03). Name input uses the scaffold's standard keyboard resize; very short landscape with keyboard is unverified. |
| Accessibility | Workout name is labeled, exercise-delete icons carry names, set details have a tooltip (`lib/screens/history_screen.dart:565`, `lib/screens/history_screen.dart:740`, `lib/widgets/workout/set_entry_table.dart:550`). E02–E04 are remaining gaps. |
| Small/large screens | Page scrolls inside an 880dp cap (`lib/screens/history_screen.dart:555`, `lib/screens/history_screen.dart:557`); exercise names/notes wrap (`lib/screens/history_screen.dart:733`, `lib/screens/history_screen.dart:749`). Existing tests cover 320dp, 2x at 390dp, and desktop (`test/history_redesign_test.dart:718`). Production numeric readability still needs K02 verification. |

See [shared controls](SHARED_UI.md) and [summary](SUMMARY.md).
