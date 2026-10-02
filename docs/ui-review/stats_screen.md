# Statistics screen

Reviewed 2026-10-02. Scope: weekly volume, exercise progress, selectors, recent records, chart scrolling/readouts. Old screenshots excluded.

## Findings

- **ST01 · Medium · Unverified layout risk — whole-page empty state cannot scroll.** No-completed-workouts state is a centered non-scrollable column with 32dp padding (`lib/screens/stats_screen.dart:98`, `lib/screens/stats_screen.dart:100`). Short landscape plus 2x text may overflow below the AppBar. Test reduced heights, then use the same scrollable empty-state pattern as Home.
- **ST02 · Low · Code-confirmed — spacing bypasses existing tokens.** Recurring 16/12/8/24/32dp literals occur in page/panel padding and gaps (`lib/screens/stats_screen.dart:120`, `lib/screens/stats_screen.dart:128`, `lib/screens/stats_screen.dart:186`, `lib/screens/stats_screen.dart:197`, `lib/screens/stats_screen.dart:330`, `lib/screens/stats_screen.dart:365`, `lib/screens/stats_screen.dart:423`). Replace with `AppSpacing.lg/md/sm/xl/xxl`. Explicit chart slots/axis geometry are not automatically spacing defects.
- **ST03 · Low · Code-confirmed — section headings have no semantic heading role.** `StatisticsSectionHeader` returns plain `Text` (`lib/widgets/statistics/statistics_widgets.dart:16`). Add `Semantics(header: true)` for Weekly training, Exercise progress, and Recent records.

No confirmed high-severity issue found in this screen.

## Six checks

| Check | Assessment and evidence |
| --- | --- |
| Visual consistency | Neutral heading roles, solved chart fills/ink, card/bar radius tokens are used (`lib/screens/stats_screen.dart:88`, `lib/screens/stats_screen.dart:331`, `lib/widgets/statistics/training_charts.dart:136`). ST02 is theme-spacing debt. No hardcoded hex colors or raw radii found. |
| Hierarchy | Weekly training, exercise progress, then records are clear (`lib/screens/stats_screen.dart:127`, `lib/screens/stats_screen.dart:198`, `lib/screens/stats_screen.dart:297`); metric and period are local to progress (`lib/screens/stats_screen.dart:223`). Latest action appears while browsing older chart data (`lib/widgets/statistics/training_charts.dart:531`). No ambiguous primary mutation action. |
| States | Page, no-performed-sets, no-progress, and no-records states exist (`lib/screens/stats_screen.dart:97`, `lib/screens/stats_screen.dart:206`, `lib/screens/stats_screen.dart:299`, `lib/widgets/statistics/training_charts.dart:32`). Analytics are synchronous local reads; no network loading/error screen is needed. ST01 is the height risk. |
| Ergonomics | Weekly slots have at least 56dp width and progress slots at least 80dp (`lib/widgets/statistics/training_charts.dart:44`, `lib/widgets/statistics/training_charts.dart:249`); Latest has 48dp height (`lib/widgets/statistics/training_charts.dart:528`). Native dropdowns are labeled and expanded (`lib/screens/stats_screen.dart:358`). No numeric entry. |
| Accessibility | Each chart data point exposes date/value, selected state, and button role (`lib/widgets/statistics/training_charts.dart:72`, `lib/widgets/statistics/training_charts.dart:295`); changing readout has a live region (`lib/widgets/statistics/training_charts.dart:397`). ST03 improves section navigation. Solved color contrast tests passed; actual screen-reader interaction remains unverified. |
| Small/large screens | Metric/period stack under 300dp or above 1.3x (`lib/screens/stats_screen.dart:245`); page caps at 880dp (`lib/screens/stats_screen.dart:123`). Chart slots/footer scale; axes measure text, and long history scrolls horizontally (`lib/widgets/statistics/training_charts.dart:494`, `lib/widgets/statistics/training_charts.dart:592`). Existing tests cover 1/1.3/2x and 390/1200dp (`test/screen_layout_test.dart:192`). Very large histories are eagerly built with for-loops (`lib/widgets/statistics/training_charts.dart:71`, `lib/widgets/statistics/training_charts.dart:289`); performance impact is unverified and not ranked as an observed defect. |

See [summary](SUMMARY.md).
