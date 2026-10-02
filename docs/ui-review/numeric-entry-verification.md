# Numeric entry and target verification

Verified 2026-10-02 for K01, K02, K03, P02, P03, H01, and DB01.

## Implemented behavior

| Finding | Result |
| --- | --- |
| K01 | Keypad fields expose numeric values with kilograms, repetitions, or an RPE value out of 10. The selected field is a live region, including cleared values. Ordinary table-field values remain in semantics. |
| K02 | Set tables, saved numeric cells, and PR badges retain the requested text size. Column minima are measured using the rendered styles and text scaler. Narrow tables scroll horizontally with a visible, draggable scrollbar. Fields and keypad buttons grow in height; keypad context and adjustment controls reflow. |
| K03 | The open keypad accepts top-row and numpad digits, decimal weight entry, Backspace, and Delete. Enter advances or finishes the last field; Escape closes while retaining live edits, like the existing Back behavior. Modifier shortcuts remain available outside numeric entry. |
| P02 | Prescription metrics use scaled rich text, larger unit labels, and grouped wrapping. Compact headers give the summary the card width and allow exercise names to wrap. The Add exercise label can wrap at large text sizes. |
| P03 | Editable numeric cells have at least 48dp width and height, including the 238dp table constraint produced by a 320dp plan editor. |
| H01 | Each day slot is at least 48dp wide. Compact Home layouts scroll the day strip horizontally. |
| DB01 | Dashboard plan rows have a 48dp minimum height while retaining the 22dp marker. |

## Readability and layout matrix

`test/ui_numeric_accessibility_test.dart` covers both themes at **320 × 640dp**
and **1280 × 900dp**, each at **1x, 1.3x, and 2x**.

Checks include actual `RenderParagraph` text scaling, height, intrinsic numeric
width, and the absence of a shrinking paint transform. They also verify target
geometry, scrolling to fields and Save, day activation, semantic values and
announcements, physical-key events, integer/decimal/RPE validation, and closing
the keypad without leaking numeric input into the underlying page.

The same matrix passed with actual Manrope and JetBrains Mono fonts. Screenshots
were inspected for readable figures, PR badges, units, name/summary wrapping,
and access to offscreen controls. These are rendering tests, not only checks for
overflow exceptions. Numeric sizes remain 20/26/40sp in the table,
17/22.1/34sp in the keypad, and 18/23.4/36sp in saved details. Prescription
numbers retain 13/16.9/26sp, with units at 12/15.6/24sp.

Production-font screenshots are generated under the ignored directory
`build/previews/numeric_accessibility/`. Capture requires the cached font files
`build/previews/manrope.ttf` and `build/previews/jetbrainsmono.ttf`.

## Regression checks

138 affected tests passed: 129 numeric/plan/history/accessibility/contrast tests,
eight selected Home tests, and the compact workout logging layout test. The
production-font matrix separately passed all 25 tests.

```powershell
flutter test --no-pub test/ui_numeric_accessibility_test.dart test/set_row_test.dart test/accessibility_test.dart test/plan_editor_test.dart test/history_redesign_test.dart test/theme_contrast_test.dart
flutter test --no-pub test/home_screen_test.dart --name 'new plan is an inline|snapshot|weekly activity|day|week'
flutter test --no-pub test/workout_log_test.dart --name 'continuous log fits'
flutter test --no-pub test/ui_numeric_accessibility_test.dart --dart-define=UI_REVIEW_CAPTURE=true
flutter analyze --no-pub --no-fatal-infos
```

Analysis found no errors or warnings. Informational brace lints were
reported in concurrently edited screens, outside
the changes documented here. The full suite was attempted but was not clean
during concurrent workout save/navigation changes; it is not recorded as
passing. Independent review found no actionable defects in this scope.

TalkBack/VoiceOver output and a physical device keyboard were not exercised;
semantics and hardware key events were verified through Flutter tests.
