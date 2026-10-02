# History screen

Reviewed 2026-10-02. Scope: searchable month-grouped journal and its empty states. Workout details and editing have separate reports because they are separate screens despite sharing the source file. Old screenshots excluded.

## Findings

- **HI01 · Medium · Unverified layout risk — empty state cannot scroll when height is constrained.** `HistoryEmptyState` is a centered, padded, non-scrollable column (`lib/widgets/history/history_journal_widgets.dart:319`). It sits below the persistent search field in the remaining expanded body (`lib/screens/history_screen.dart:99`, `lib/screens/history_screen.dart:127`). The search keyboard, short landscape height, and 2x text can leave too little room for “No matching workouts” and Clear search. Test that combination, then add a scrollable/constrained empty body.
- **HI02 · Low · Code-confirmed — month sections are not semantic headings.** The visible month title is an ordinary `Text` in a `Wrap` (`lib/widgets/history/history_journal_widgets.dart:58`, `lib/widgets/history/history_journal_widgets.dart:63`), without `Semantics(header: true)`. Mark month titles as headings so assistive navigation matches the visual grouping. Screen-reader grouping of whole workout rows is unverified.

## Six checks

| Check | Assessment and evidence |
| --- | --- |
| Visual consistency | Search, rows, and separators use theme type, colors, radii, and spacing (`lib/widgets/history/history_journal_widgets.dart:41`, `lib/widgets/history/history_journal_widgets.dart:95`, `lib/widgets/history/history_journal_widgets.dart:106`). No actionable hardcoded hex/radius or recurring page-spacing violations found. Date-chip widths are deliberate geometry. |
| Hierarchy | Search is persistently visible, result count follows it, and rows open details (`lib/screens/history_screen.dart:106`, `lib/screens/history_screen.dart:119`, `lib/screens/history_screen.dart:166`). No competing primary mutation action on this browsing screen. |
| States | Distinct no-history and no-match messages; search has Clear search (`lib/widgets/history/history_journal_widgets.dart:325`, `lib/widgets/history/history_journal_widgets.dart:332`). Local data is synchronous; no page loading state required. Long journal uses `ListView.builder` (`lib/screens/history_screen.dart:134`). HI01 is the empty-state height risk. |
| Ergonomics | Entire workout rows are tappable with generous padding (`lib/widgets/history/history_journal_widgets.dart:102`, `lib/widgets/history/history_journal_widgets.dart:106`); clear icon is labeled (`lib/widgets/history/history_journal_widgets.dart:36`). Keyboard uses Search (`lib/widgets/history/history_journal_widgets.dart:29`); there are no number inputs. A drag-to-dismiss keyboard behavior is not configured on the journal (`lib/screens/history_screen.dart:134`); its necessity is unverified, not a confirmed defect. |
| Accessibility | Metric semantics include units/context (`lib/widgets/history/history_journal_widgets.dart:274`), and PR pill uses the solved foreground (`lib/widgets/history/history_journal_widgets.dart:248`). HI02 is the navigation gap. |
| Small/large screens | Rows stack date/content below 310dp or at 1.6x+ text (`lib/widgets/history/history_journal_widgets.dart:109`); names and metrics wrap (`lib/widgets/history/history_journal_widgets.dart:209`, `lib/widgets/history/history_journal_widgets.dart:216`). Page caps at 880dp (`lib/screens/history_screen.dart:96`). Existing tests cover 320dp, 2x at 390dp, desktop, and empty states (`test/history_redesign_test.dart:718`), without a visible keyboard/short-height combination. |

See [workout details](workout_details_screen.md), [edit workout](edit_session_screen.md), and [summary](SUMMARY.md).
