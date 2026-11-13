# Statistics design

Stats is a focused training instrument, with four persistent views rather than a
feed of cards. Overview answers how much training happened and how regularly;
Strength inspects one lift; Blocks follows a training phase; Records keeps the
achievement history. Ordinary phone layouts show the main plot and its supporting
figures together. Vertical scrolling remains available for large text, short
screens, and deliberately opened history.

## Reference research

- [Oura's app redesign](https://ouraring.com/blog/new-oura-app-experience/):
  focused destinations reduce the number of competing health metrics. Borrow
  the separation of daily context and long-term trends.
- [Oura Trends](https://ouraringhelp.zendesk.com/hc/en-us/articles/360055983614-Using-Trends):
  a clear selected value and change over time. Keep exact values readable beside
  visual patterns.
- [WHOOP Trend Views](https://www.whoop.com/us/en/thelocker/track-progress-with-new-trend-views/):
  period controls, contextual comparisons, and one dominant plot. Borrow the
  direct relation between selection, value, and comparison.

The implementation does not copy these products' card layouts or color systems.
OpenGym uses the visual language of a training log: weekly workload, individual
lifts, performed sets, and a calendar of days trained.

## Design plan and critique

The reference palette is paper `#FAFAFA`, carbon `#080808`, graphite `#707070`,
mist `#E6E6E6`, blue `#0075BB`, and pale blue `#DCECF5`. These are descriptive
swatches, not literal UI tokens. Production colors use the existing solved
background, surface, text, accent, accent fill, and accent washes; they adapt to
the selected accent and brightness.

Manrope carries the interface and the data. Tabular figures keep changing values
stable. The scale is 40px for the selected value, 24px for an exercise, 17px for a
section, and 12–14px for controls and context. The layout is left aligned with
24px page margins and an 832px content maximum.

```text
Overview   Strength   Blocks   Records
──────────────────────────────────────
Weekly training         All exercises
Selected week / dates
Exact volume + completed-week comparison

│  │ │  ││  │  │││  │   weekly timeline

Workouts        Sets         Reps
──────────────────────────────────────
Training rhythm
compact training-day calendar
```

The first idea—large totals followed by a grid of metric cards—was rejected
because it repeated the existing scrolling problem. The final layout spends its
visual emphasis on the selected plot, with supporting totals integrated into the
same canvas. Quiet controls, precise selection, strong type hierarchy, and
consistent spacing carry the premium feel. There are no decorative shadows,
hero illustrations, or independent color themes.

## Interaction details

- Overview defaults to the last complete week. Home's weekly shortcut opens
  the current week and resets the exercise filter. In-progress weeks are named
  and do not receive a comparison against a full week.
- A week selection changes volume and the workout/set/rep totals together.
  Exercise filtering applies to both, while the calendar retains the full split.
- Weekly history scrolls horizontally with at least 48px per selection. The
  exact readout and date are accessible for each point.
- Strength's exercise directory opens in a sheet with latest values, sparklines,
  and change. An info control opens the plain-language measure explanation. Period controls retain
  full spoken names. The trend uses straight segments between recorded values;
  it does not invent smoothing or measurements.
- Blocks leads with a selectable line chart across logged blocks, using saved
  block order. Volume, Sets, Workouts, and Records share one quiet measure
  selector. Per trained week is the default basis; Block total reveals sums.
  Only blocks with workouts enter the trend, so unused blocks are not presented
  as measured zeroes. A single logged block renders one point and explains how
  to extend the trend. Long histories scroll horizontally in whole visible
  slots, while measure changes retain the browsing position.
- Block totals sit in two generous columns on phones, without per-metric rate
  subtitles or vertical separators. Weekly workload has one selected-week
  readout instead of values above every bar. Strength gains show a lift and its
  percentage; tapping reveals the start and end weights. Older block selection
  updates all three sections. The page is deliberately scrollable.
- Records load twelve events at a time, with more available on demand.
- Large text can expand the page; navigation scrolls horizontally when its
  labels need more space. Empty states provide a next step.

## Reviewing multiple blocks

`tool/statistics_preview.dart` is a debug-only device entry point containing seven
in-memory blocks. It uses the real Stats screen, analytics, and chart widgets.
It does not initialize storage or accounts and never changes saved workouts.
Build it with `flutter build apk --debug --target tool/statistics_preview.dart`.
The block refinement screenshots use this fixture to demonstrate browsing a
longer history. Build the normal `lib/main.dart` target to restore the regular app.

The refinement keeps the same palette and type roles. Its layout is a quiet
measure selector, selected block/value, one comparison line, the block trend,
then totals, weekly workload, and gains with 24–32px section spacing. The rejected
alternative was keeping the old four-column row and merely adding a graph:
that would retain the cramped hierarchy the refinement is meant to resolve.
