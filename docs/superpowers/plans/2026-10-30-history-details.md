# History and workout details implementation plan

**Goal:** Give the training journal a distinct hierarchy and make saved workouts easy to scan.
**Architecture:** Retain existing Provider data, search/grouping, analytics, navigation and editing. Reshape only the presentation in the existing history widgets.
**Design:** A date rail outside compact session cards; title before training context; quiet metrics and small record badges. Details use a spacious title/date, a bounded summary, an exercise section heading and numbered exercise panels with aligned, read-only set values. Use existing semantic colors, Manrope figures, radii and spacing. Preserve unknown-duration omission, notes, units and zero-rep data.
**Approaches considered:** Continuous ruled rows would stay visually close to the rejected detail screen. Large dashboard tiles would make History slower to browse. Choose a compact journal and grouped exercise panels to give each level a clear boundary.

- [x] Reshape history search, month headings, date rail and session content in `history_journal_widgets.dart`; retain row identity and analytics.
- [x] Reshape summary and exercise panels in `workout_details_widgets.dart`; add section spacing in `history_screen.dart`.
- [x] Run analyzer after each changed file and existing history, numeric accessibility, contrast and radius checks. Use existing behavior tests for this presentation change.
- [x] GPT Luna captures representative populated and empty-log layouts in both themes and reviews navigation, search, notes, narrow widths and large text. Resolve defects.
- [x] Update DESIGN.md and commit only the task files, preserving pre-existing changes.

Review focus: long names, missing duration, no performed sets, large text/narrow screens, notes and PR markers.

Verification: flutter analyze clean; full tracked suite 893 passed, 3 skipped; final focused accessibility/layout suite 59 passed and final History suite 21 passed. GPT Luna generated dark/light populated and zero-set fixtures plus 320dp/2x text captures. Live emulator launch reached pre-existing data recovery UI, so visual verification used isolated Provider fixtures without changing emulator data.
