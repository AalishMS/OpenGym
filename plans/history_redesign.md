# History redesign: a readable training journal

## Summary

Replace the dense expandable cards with a month-grouped workout journal, searchable by workout or exercise name. Each workout opens a dedicated detail screen. Refresh the existing editing and deletion flows to match.

The approved direction is a full History flow redesign. Preserve offline storage, active-split filtering, Provider architecture, and existing editing capabilities.

## Layout and visual design

Use existing Manrope theme typography, with `AppTypography.trainingData` only for aligned set values. Use semantic colors, `AppSpacing`, and `AppRadius`; introduce no fonts, hardcoded colors, or global theme changes.

```text
History
[ Search workouts or exercises       × ]

September 2026                     8 workouts

 11    Push day                            ›
 Fri   Week 4 · 5 exercises · 18 sets
       48m · Volume load 3.2 t
       Personal record

 09    Pull day                            ›
 Wed   Week 4 · 6 exercises · 20 sets
       52m · Volume load 4.1 t

August 2026                       12 workouts
...
```

- The signature element is the date column: prominent day number with a quieter weekday, aligned beside the workout. Repeat dates for multiple workouts on the same day.
- Use quiet surface rows, rounded corners, and generous separation between months. Avoid decorative timeline lines, summary dashboards, and charts.
- Use `titleLarge` for month headings, `titleMedium` for workout names, and `bodySmall` for supporting information. Preserve user-entered capitalization.
- Give rows 16px padding and 12px gaps; use 24px between month groups. Page gutters are 16px, with centered content capped at 880px.
- Workout names and metadata wrap naturally. At narrow widths or large text scales, move the date above the workout rather than squeezing columns.
- All actions have accessible labels and at least 48px touch targets. Preserve normal navigation transitions and visible focus states.

## Behavior and implementation

### Journal browsing

- Keep the existing `HistoryScreen` entry point. Use stateful search and a lazy list containing month headers and workout rows.
- Display completed, non-deleted sessions from the active split, newest first. Include the year in every month heading; month counts reflect search results.
- Search immediately using a trimmed, case-insensitive substring match against saved workout names and exercise names. No search persistence, extra filters, calendar, or pagination in this version.
- Preserve query and scroll position when returning from details or switching tabs. Clear both when the active split changes.
- Empty history: “No completed workouts” and “Finish and log a workout to see it here.”
- Empty search: “No matching workouts” with a “Clear search” action.

### Workout details

- Tapping a row opens a read-only detail route with Back, “Workout details,” and an accessible actions menu containing “Edit” and “Delete.”
- Show the full workout name, full date, week, exercise count, performed sets, duration, and clearly labeled volume load.
- Show exercises in their saved order. Each section contains its name, exercise note, and aligned Set / Weight / Reps / RPE values. Show set notes beneath their corresponding rows.
- Preserve all saved sets in details, including zero-rep sets. Missing RPE displays an em dash; missing duration says “Not recorded.” Omit missing duration from journal summaries.
- Match detail data by stable session identity and refresh after editing. If the session disappears, show “Workout no longer available” with Back; never keep stale mutation controls active.

### Data correctness and reuse

- Reuse `StatisticsAnalyticsService.eligibleSessions`, `sessionStatistics`, and `recordEvents`; use existing statistics formatters for weight, volume, duration, and dates.
- Count performed sets using the existing `reps > 0` rule. Keep volume as a double until formatting. Convert displayed weights using the selected kg/lbs preference.
- Calculate record events from the complete eligible split history **before search filtering**. Associate events with source sessions and show one “Personal record” badge per qualifying workout. Later achievements must not erase earlier record events.
- Compute summaries and the record lookup outside individual row builders. Remove the current per-card Hive reads and comparisons against all other workouts.
- Keep all persistence and sync operations behind the existing provider. No Hive fields, adapters, migrations, backend changes, or new dependencies.

### Editing and deletion

- Preserve `EditSessionScreen(session: ...)` compatibility and existing set-entry/dialog components.
- Replace terminal-style headings, bracketed actions, uppercase transformations, and tiny text throughout the touched History flow.
- Keep current edit capabilities: workout name, set changes, exercise removal, RPE, and notes. Display explicit units; do not write converted pounds back as kilograms.
- Save only through `updateSession`; disable repeated submission while saving. On failure, retain edits and show a useful error message. On success, return to refreshed details with “Workout updated.”
- Delete requires a dialog naming the workout and date, with “Cancel” and “Delete.” Await `deleteSession`, prevent repeated submission, and return to the refreshed journal only after success. Keep the dialog open with retry available on failure.
- Use focused widgets under `lib/widgets/history/`; keep history presentation calculations separate from widget layout. Avoid unrelated refactoring.

## Verification and completion

- Add focused tests for month/year grouping, newest-first ordering, same-day workouts, search by both name types, clearing search, and split changes.
- Verify draft/tombstone exclusion, performed-set counts, fractional volume, kg/lbs formatting, missing duration, notes, and historical record badges unaffected by search or later records.
- Test detail navigation, return-state preservation, successful edit refresh, canceled/confirmed deletion, and failed mutations retaining recoverable UI.
- Update existing History assertions in the screen-layout and split tests to exercise the new navigation.
- Visually inspect populated journal, details, editing, and empty states in light and dark themes at 320px and typical phone widths, plus wide layout and 2× text scaling. Confirm no overflow, clipped notes, or undersized controls.
- Run `flutter analyze` after each file change as required by repository guidance. Run focused tests, theme contrast tests, and then the full Flutter test suite.
- Update `opencode.md` with the completed redesign. Stage intended files explicitly and commit according to repository guidance; preserve unrelated changes.

## Handoff prompt

> Implement the History redesign specified in `plans/history_redesign.md`.
>
> Read `AGENTS.md`, `opencode.md`, and `DESIGN.md`. Follow the plan’s approved training-journal layout and full History flow scope. Use existing theme tokens, statistics calculations, formatters, Provider mutations, and set-editing components. Preserve public screen constructors, active-split isolation, stored kilograms, and all saved workout details.
>
> Work sequentially: journal and search, read-only details, edit/delete integration, then regression tests and visual verification. Follow the plan’s explicit behavior rather than inventing additional features. Run required analysis after each file change, fix errors, and complete the stated tests. Update documentation and commit only intended changes. Report what changed, verification results, and any remaining limitations.
