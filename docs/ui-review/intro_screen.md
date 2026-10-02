# Introduction screen

Reviewed 2026-10-02. Scope: both onboarding pages, preview cards, Skip, Next, and Get started. Old screenshots were excluded.

## Findings

- **I01 · Medium · Unverified layout risk — preview card has a fixed height.** The card is exactly 278dp tall with 24dp padding (`lib/screens/intro_screen.dart:243`). Its title, three text rows, fixed gaps, and `Spacer` all share that space (`lib/screens/intro_screen.dart:251`, `lib/screens/intro_screen.dart:274`, `lib/screens/intro_screen.dart:277`, `lib/screens/intro_screen.dart:303`). Scaled/wrapped text can outgrow it, especially around 2x; outer page scrolling cannot repair an internal Flex overflow. Use a minimum height and content-driven layout. Existing compact test covers 320 × 568dp at default text size only (`test/intro_screen_test.dart:83`).
- **I02 · Low · Code-confirmed — page progress has no spoken equivalent.** The two indicator dots are painted containers (`lib/screens/intro_screen.dart:168`), with no “Page 1 of 2” semantics or announcement on `onPageChanged` (`lib/screens/intro_screen.dart:114`). Add a single current-page semantic label; exclude decorative dots and mark the page title as a heading.
- **I03 · Low · Code-confirmed — ordinary section label uses data typography.** “Your plan”/“Today's workout” use an explicit 11sp monospaced style and tracking (`lib/screens/intro_screen.dart:135`). Use a theme label role; the numerical preview at `lib/screens/intro_screen.dart:294` is an appropriate training-data use.
- **I04 · Low · Code-confirmed — completion disables controls without busy feedback.** `_finish` sets `_finishing` while awaiting storage (`lib/screens/intro_screen.dart:46`), but Skip/Get started only become disabled (`lib/screens/intro_screen.dart:103`, `lib/screens/intro_screen.dart:194`). Add a named progress state to the final action. How perceptible the delay is on a phone is unverified.

## Six checks

| Check | Assessment and evidence |
| --- | --- |
| Visual consistency | Spacing and corners use theme tokens; preview grounds and foregrounds use helpers (`lib/screens/intro_screen.dart:245`). I03 is the typography exception. No hardcoded UI hex colors or raw corner radii found. |
| Hierarchy | One full-width bottom action and quiet top Skip are clear (`lib/screens/intro_screen.dart:102`, `lib/screens/intro_screen.dart:191`); page title uses the display role (`lib/screens/intro_screen.dart:145`). |
| States | Intro has fixed content, so empty/loading data states are not applicable. Persistence errors reset busy state and show a retry message (`lib/screens/intro_screen.dart:51`). I04 concerns completion loading. |
| Ergonomics | Main action stays at the bottom outside the page scroller (`lib/screens/intro_screen.dart:159`), and theme button minimums are 48dp (`lib/theme/app_theme.dart:543`, `lib/theme/app_theme.dart:567`). No number inputs or keyboard-dependent flow. |
| Accessibility | Theme colors are used; reduced-motion preference is honored (`lib/screens/intro_screen.dart:67`, `lib/screens/intro_screen.dart:127`, `lib/screens/intro_screen.dart:172`). I01/I02 cover scaling/progress. Production screen-reader output remains unverified. |
| Small/large screens | Content is capped at 460dp and each page scrolls (`lib/screens/intro_screen.dart:89`, `lib/screens/intro_screen.dart:117`). The preview itself is fixed-height (I01); test 1.3x and 2x, both pages, short landscape, and large display sizes. |

See [summary](SUMMARY.md).
