# Statistics screen

Reviewed 2026-11-03. Scope: the four focused views, chart selection, compact
calendar, selectors, records, and entry from Home.

The screen uses Overview, Strength, Blocks, and Records navigation instead of a
vertical stack of chart panels. Charts and figures share the page ground. The
active view stays visible while its content scrolls.

## Verification

- `flutter analyze` passes.
- 157 targeted tests cover analytics, the four views, exact chart readouts,
  incomplete weeks, performed-set counts, filtering, provider updates, split
  isolation, block trends and totals, navigation, typography, and color contrast.
- New view-layout checks exercise 320×640 screens, 1×/2× text, and both themes.
  The existing screen suite also checks 390px and 1200px layouts.
- Android debug APK builds. Emulator review checks the actual app typography,
  open-canvas hierarchy, modal pickers, and both light and dark appearances.

## Six checks

| Check | Current behavior |
| --- | --- |
| Visual consistency | Theme-derived colors, Manrope/tabular figures, spacing and radius tokens; no chart-panel backgrounds or decorative shadows. Period controls use a quiet neutral track. |
| Hierarchy | One dominant chart per analytical view. Weekly selection updates volume and the workout/set/rep strip together. Strength separates the exercise, measure, selected value, and period summary. Blocks leads with one cross-block trend, then two-column totals, weekly workload, and expandable gains. |
| States | The whole-page empty state scrolls. Strength explains missing data and offers a period/measure choice. Blocks and Records have explicit empty states. Analytics read local state without a network dependency. |
| Ergonomics | Navigation and chart selections have at least 48px targets. Weekly and block history browse horizontally. The exercise directory and measure selection open in sheets; formula help opens through the info control. |
| Accessibility | Selected controls expose state; chart selections have date, value, and button roles; selected readouts are live regions. Section headings use heading semantics. Actual screen-reader traversal remains a manual check. |
| Small/large screens | Controls and summaries wrap for larger text; navigation scrolls horizontally when needed; vertical scrolling remains available for short screens. Content caps at 832px. |

Finished Android captures are in `screenshots/statistics-premium/`. Research and
design rationale are in [statistics design](../statistics-design.md).

Block refinement captures use the read-only, seven-block fixture in
`tool/statistics_preview.dart`; saved workouts are not modified. The new block
tests cover long histories, retained browsing position, metric/basis changes,
kg/lbs conversion, unstarted weeks, expanded gains, zero/flat/single series, and
320px layouts with 2× text.
