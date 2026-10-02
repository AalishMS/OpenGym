# Workout details screen

Reviewed 2026-10-02. Scope: `WorkoutDetailsScreen` in `history_screen.dart`, summary, exercise/set readouts, Edit and Delete. Old screenshots excluded.

## Findings

- **D01 · Medium · Code-confirmed — saved numeric values can shrink back at large text.** Weight/reps are inside `FittedBox(fit: BoxFit.scaleDown)` (`lib/widgets/history/workout_details_widgets.dart:383`, `lib/widgets/history/workout_details_widgets.dart:391`). Fixed set gutter and proportional columns keep the same horizontal allocation (`lib/widgets/history/workout_details_widgets.dart:337`). At large text or long weights, fitting reduces the requested text scale instead of reflowing. Use minimum readable column widths, stacked rows, or horizontal scrolling. The exact shrink threshold with production fonts is unverified.
- **D02 · Low · Code-confirmed — weight/reps lack set-specific semantic context.** Each set creates an unlabeled semantic container (`lib/widgets/history/workout_details_widgets.dart:407`); weight and reps are plain text children (`lib/widgets/history/workout_details_widgets.dart:418`, `lib/widgets/history/workout_details_widgets.dart:446`). Only RPE explicitly says which set/value it describes (`lib/widgets/history/workout_details_widgets.dart:447`). Add a row summary such as “Set 2, 60 kilograms, 8 reps, RPE 7” or field-level labels. Actual reading order/announcement must be checked on a screen reader.

## Six checks

| Check | Assessment and evidence |
| --- | --- |
| Visual consistency | Summary and log use theme typography/neutral rules, field/card tokens, and solved PR fill/foreground (`lib/widgets/history/workout_details_widgets.dart:183`, `lib/widgets/history/workout_details_widgets.dart:225`, `lib/widgets/history/workout_details_widgets.dart:430`). The forced 18sp value at `lib/widgets/history/workout_details_widgets.dart:397` should become a named shared training-data role if the live/saved log are meant to match. No hardcoded hex or raw corner radii found. |
| Hierarchy | Plan name and session summary precede exercises (`lib/screens/history_screen.dart:396`); Edit is a named app-bar icon and Delete is in overflow with error ink (`lib/screens/history_screen.dart:327`, `lib/screens/history_screen.dart:350`). Edit also appears in overflow (`lib/screens/history_screen.dart:345`); this redundancy is not ranked as a defect. |
| States | Missing session and empty exercises/sets have explicit messages (`lib/screens/history_screen.dart:363`, `lib/screens/history_screen.dart:402`, `lib/widgets/history/workout_details_widgets.dart:254`). Delete has confirmation, disabled/progress state, failure message and retry (`lib/screens/history_screen.dart:216`, `lib/screens/history_screen.dart:267`, `lib/screens/history_screen.dart:278`). Page reads are local. |
| Ergonomics | Back/Edit/overflow use standard labeled controls; menu items are 48dp (`lib/screens/history_screen.dart:319`, `lib/screens/history_screen.dart:327`, `lib/screens/history_screen.dart:345`). Read-only numeric boxes are not actions, so their 44dp height (`lib/widgets/history/workout_details_widgets.dart:384`) is not a tap-target violation. No number keyboard. |
| Accessibility | Exercise headings and notes have semantics (`lib/widgets/history/workout_details_widgets.dart:231`, `lib/widgets/history/workout_details_widgets.dart:329`); PR and RPE are labeled (`lib/widgets/history/workout_details_widgets.dart:421`, `lib/widgets/history/workout_details_widgets.dart:447`). D01/D02 concern numeric readability/context. Delete error at `lib/screens/history_screen.dart:237` is not a live region; whether it is automatically announced is unverified. |
| Small/large screens | Summary chooses two/four columns based on scaled width (`lib/widgets/history/workout_details_widgets.dart:96`); page caps at 880dp and scrolls (`lib/screens/history_screen.dart:387`, `lib/screens/history_screen.dart:388`). Long names/notes wrap. Existing history tests exercise scaled layouts (`test/history_redesign_test.dart:718`), but passing overflow tests does not establish readable numbers under D01. |

See [summary](SUMMARY.md).
