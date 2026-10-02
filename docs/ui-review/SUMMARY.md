# OpenGym UI/UX review

Reviewed **2026-10-02** against current source, `DESIGN.md`, `AGENTS.md`, theme tokens, and widget tests. Covers all nine files in `lib/screens/` and **11 screen classes**, including the details/editor screens inside History. **The outdated `screenshots/` images were excluded.** No application code was changed.

The most urgent fixes are completed-workout scrolling and protection of unsaved edits. Most screens already use solved theme colors, radius tokens, responsive widths, and accessible controls. The remaining problems concentrate in shared numeric controls, persistence feedback, and older utility UI.

## Evidence and severity

- **High:** loss of access to recorded workout content or silently discarded user edits.
- **Medium:** a common task, target, reading/entry mode, or recovery flow is impaired.
- **Low:** consistency, copy, or secondary accessibility polish.
- **Code-confirmed:** the implementation demonstrates the gap; this does not mean every possible failure was reproduced.
- **Widget verified:** a targeted automated probe demonstrated the specific behavior. Probes used default test typography, not production Manrope/JetBrains fonts.
- **Unverified layout risk:** code suggests a problem, but a current render/device reproduction is still required. These are separated below.

References use one-based source lines at the reviewed checkout. Screen reports contain the full six-check assessment and suggested remedies.

## Screen reports

| Screen | Report | Highest finding |
| --- | --- | --- |
| Home | [Home](home_screen.md) | Medium |
| Dashboard, desktop shell | [Dashboard](dashboard_screen.md) | Medium |
| Introduction | [Introduction](intro_screen.md) | Medium, unverified layout risk |
| Sign in / create account | [Login](login_screen.md) | Medium |
| Create / edit plan | [Plan editor](plan_editor_screen.md) | Medium |
| Active / completed workout | [Workout](workout_screen.md) | High |
| History journal | [History](history_screen.md) | Medium, unverified layout risk |
| Saved workout details | [Workout details](workout_details_screen.md) | Medium |
| Edit saved workout | [Edit workout](edit_session_screen.md) | High |
| Statistics | [Statistics](stats_screen.md) | Medium, unverified layout risk |
| Settings | [Settings](settings_screen.md) | Medium |

[Shared controls and navigation](SHARED_UI.md) covers the keypad, set table, shell, tutorial, and shared sheets/dialogs. Shared findings are counted once in the ranking below.

## High priority

| ID | Finding and impact | Evidence |
| --- | --- | --- |
| W01 | Completed workouts disable pointer input on the whole scroll view. Lower exercises cannot be reached by dragging. Probe: 2,615.88dp scroll extent, drag left offset at 0dp. | `lib/screens/workout_screen.dart:874`, `lib/screens/workout_screen.dart:894` |
| W02 | Exercise reorder/delete mutate memory without saving; plan switching and system back lack a save-before-leave path. Custom Back starts saving without awaiting it. Changes can be silently lost. The missing paths are code-confirmed; actual loss sequences remain unverified. | `lib/screens/workout_screen.dart:604`, `lib/screens/workout_screen.dart:717`, `lib/screens/workout_screen.dart:768`, `lib/screens/workout_screen.dart:1058`, `lib/screens/workout_screen.dart:1295` |
| E01 | Edit workout uses a copied draft and saves only on Save; toolbar/system Back have no dirty-state protection or discard confirmation. Device back was not manually exercised. | `lib/screens/history_screen.dart:443`, `lib/screens/history_screen.dart:503`, `lib/screens/history_screen.dart:534`, `lib/screens/history_screen.dart:656` |

## Medium priority: demonstrated or code-confirmed

| IDs | Finding | Evidence |
| --- | --- | --- |
| K01 / E02 | Keypad excludes child semantics but supplies no current weight/rep semantic value. Probe displayed 100 with an empty semantic value. Affects Workout, Plan editor, and Edit workout. | `lib/widgets/workout/set_entry_table.dart:869`, `lib/widgets/workout/set_entry_table.dart:879`, `lib/widgets/workout/set_entry_table.dart:937` |
| K02 / D01 / E03 | Shared numeric cells/keypad and saved details shrink enlarged text through scale-down fitting. Exact production-font thresholds remain unverified. | `lib/widgets/workout/set_entry_table.dart:655`, `lib/widgets/workout/set_entry_table.dart:950`, `lib/widgets/workout/set_entry_table.dart:962`, `lib/widgets/history/workout_details_widgets.dart:391` |
| P02 | Plan prescription `RichText` omits a text scaler, so the requested accessibility scale does not reach its spans. | `lib/screens/plan_editor_screen.dart:801`, `lib/screens/plan_editor_screen.dart:807` |
| H01 | Home activity days measure 44.3dp wide at 390dp, below the requested 48dp target minimum. | `lib/widgets/home/training_snapshot.dart:110`, `lib/widgets/home/training_snapshot.dart:126`, `lib/screens/home_screen.dart:248` |
| P03 | Nested plan-editor gutters leave about 238dp for the table at 320dp. Shared-widget probe measured a 41.9dp weight target. Full-screen production-font measurement remains unverified. | `lib/screens/plan_editor_screen.dart:323`, `lib/screens/plan_editor_screen.dart:705`, `lib/widgets/workout/set_entry_table.dart:363`, `lib/widgets/workout/set_entry_table.dart:390` |
| DB01 | Dashboard plan rows have small content/padding and no minimum height; normal rows fall below 48dp. Production-font dimensions remain unverified. | `lib/widgets/dashboard/plan_status_tile.dart:30`, `lib/widgets/dashboard/plan_status_tile.dart:34`, `lib/widgets/dashboard/plan_status_tile.dart:39` |
| P04 | Plan editor Back is an unlabeled chevron InkWell. | `lib/screens/plan_editor_screen.dart:472`, `lib/screens/plan_editor_screen.dart:478` |
| K03 | Custom keypad has no physical number-key, Backspace, or Enter handling; entry is through buttons. | `lib/widgets/workout/set_entry_table.dart:737`, `lib/widgets/workout/set_entry_table.dart:1017`, `lib/widgets/workout/set_entry_table.dart:1079` |
| H04 | Duplicate announces success before async persistence; Delete/color Save also omit awaited failure handling. | `lib/screens/home_screen.dart:509`, `lib/screens/home_screen.dart:513`, `lib/screens/home_screen.dart:571`, `lib/screens/home_screen.dart:688` |
| P01 | Plan Save has no in-flight guard, loading state, or catch around persistence. | `lib/screens/plan_editor_screen.dart:46`, `lib/screens/plan_editor_screen.dart:116`, `lib/screens/plan_editor_screen.dart:166` |
| W03 | Autosave/timer storage failures lack feedback; several callers discard the save future. | `lib/screens/workout_screen.dart:188`, `lib/screens/workout_screen.dart:203`, `lib/screens/workout_screen.dart:268`, `lib/screens/workout_screen.dart:974` |
| S01 | Settings replacement/clear/import actions lack guarded, visible in-flight state. Error handling exists; repeated-click effects are unverified. | `lib/screens/settings_screen.dart:130`, `lib/screens/settings_screen.dart:624`, `lib/screens/settings_screen.dart:822`, `lib/screens/settings_screen.dart:927` |
| H02 | Ordinary plan-list actions are available only by long press; explicit overflow appears only in Manage mode. | `lib/widgets/home/home_plan_row.dart:60`, `lib/widgets/home/plan_card.dart:120` |
| DB02 | Dashboard Resume opens a plan without the displayed session/week, including after completed sessions. It can open a different workout. | `lib/screens/dashboard_screen.dart:195`, `lib/screens/dashboard_screen.dart:267`, `lib/screens/workout_screen.dart:107` |
| W04 | Finish is disabled until the separate top-bar Start action is used, with no explanation beside Finish. | `lib/screens/workout_screen.dart:822`, `lib/screens/workout_screen.dart:1000` |
| W05 | Rename week has a numeric keyboard but no formatter, inline invalid-input feedback, or Done submission. | `lib/widgets/workout/workout_dialogs.dart:540`, `lib/widgets/workout/workout_dialogs.dart:546`, `lib/widgets/workout/workout_dialogs.dart:565` |
| L01 | Login offers no password recovery entry point. Backend recovery support/policy is unverified. | `lib/screens/login_screen.dart:157`, `lib/screens/login_screen.dart:181` |
| L02 | Login's shared validation message is not associated with fields and does not focus the invalid field. | `lib/screens/login_screen.dart:35`, `lib/screens/login_screen.dart:96`, `lib/screens/login_screen.dart:145`, `lib/screens/login_screen.dart:212` |
| DB03 | Dashboard sparkline lacks an accessible trend/series alternative; min/max and delta do not describe the path. | `lib/widgets/dashboard/progression_sparkline.dart:63`, `lib/widgets/dashboard/progression_sparkline.dart:82` |
| S02 | Settings spans the desktop pane without a reading-width cap, pushing trailing actions far from their labels. | `lib/screens/settings_screen.dart:179`, `lib/screens/settings_screen.dart:369`, `lib/screens/settings_screen.dart:569`, `lib/screens/settings_screen.dart:592` |

## Medium priority: unverified layout risks

Reproduce these before treating them as observed overflow bugs.

| ID | Scenario to verify | Evidence |
| --- | --- | --- |
| H03 | Plan menu/color picker at short landscape heights, long names, and 2x text: non-scrollable columns and fixed action Row. | `lib/screens/home_screen.dart:399`, `lib/screens/home_screen.dart:413`, `lib/screens/home_screen.dart:607`, `lib/screens/home_screen.dart:674` |
| I01 | Both intro previews at 1.3x/2x: fixed 278dp card with padding, text, fixed gaps, and Spacer. | `lib/screens/intro_screen.dart:243`, `lib/screens/intro_screen.dart:251`, `lib/screens/intro_screen.dart:303` |
| HI01 | Empty/no-match history with search keyboard, short height, and 2x text: non-scrollable centered body below search. | `lib/screens/history_screen.dart:99`, `lib/screens/history_screen.dart:127`, `lib/widgets/history/history_journal_widgets.dart:319` |
| ST01 | Empty statistics at short landscape heights and 2x text: padded centered Column cannot scroll. | `lib/screens/stats_screen.dart:98`, `lib/screens/stats_screen.dart:100` |

## Low priority

| IDs | Finding | Evidence |
| --- | --- | --- |
| H05, L03, ST02, S04 | Existing spacing tokens are bypassed by recurring literal gaps/padding. S04 also paints an update snackbar on accent ink instead of accent fill; its `onColor` foreground means this is not a demonstrated contrast failure. | `lib/screens/home_screen.dart:608`, `lib/screens/login_screen.dart:72`, `lib/screens/stats_screen.dart:120`, `lib/screens/settings_screen.dart:180`, `lib/screens/settings_screen.dart:118` |
| DB04, I03, P05, W06, S03 | Ordinary UI uses legacy small monospace, uppercase, or prompt-prefixed copy rather than sentence case/theme roles. Numerical data remains an appropriate monospace use. | `lib/screens/dashboard_screen.dart:100`, `lib/widgets/dashboard/plan_status_tile.dart:48`, `lib/screens/intro_screen.dart:135`, `lib/screens/plan_editor_screen.dart:314`, `lib/widgets/workout/workout_dialogs.dart:492`, `lib/screens/settings_screen.dart:169` |
| P06 | Delete exercise footer uses ordinary secondary ink rather than distinct destructive treatment. | `lib/screens/plan_editor_screen.dart:853`, `lib/screens/plan_editor_screen.dart:856` |
| I02 | Intro dots/page changes lack a spoken page-position equivalent. | `lib/screens/intro_screen.dart:114`, `lib/screens/intro_screen.dart:168` |
| I04, E04 | Intro completion only disables controls; Edit workout replaces Save with an unnamed spinner. Add named progress feedback. | `lib/screens/intro_screen.dart:46`, `lib/screens/intro_screen.dart:194`, `lib/screens/history_screen.dart:540`, `lib/screens/history_screen.dart:544` |
| HI02, ST03 | Visible month/statistics headings lack semantic heading roles. | `lib/widgets/history/history_journal_widgets.dart:58`, `lib/widgets/statistics/statistics_widgets.dart:16` |
| D02 | Saved weight/reps lack explicit set-specific semantic context, unlike RPE. Actual spoken reading order is unverified. | `lib/widgets/history/workout_details_widgets.dart:407`, `lib/widgets/history/workout_details_widgets.dart:418`, `lib/widgets/history/workout_details_widgets.dart:447` |
| S05 | “Add sample plans and workouts” understates the replacement/clear operation, although confirmation explains it. | `lib/screens/settings_screen.dart:216`, `lib/screens/settings_screen.dart:615`, `lib/screens/settings_screen.dart:634` |
| N01 | Compact Home and desktop Plans name the same destination differently. | `lib/widgets/app_bottom_nav.dart:27`, `lib/widgets/app_nav_rail.dart:29` |

## Cross-cutting issues and suggested fix order

1. **Restore scrolling and protect drafts.** Fix W01, then centralize awaited persistence/dirty-navigation handling for W02/E01. The plan editor already supplies a useful discard pattern (`lib/screens/plan_editor_screen.dart:302`).
2. **Fix shared numeric controls once.** Address K01–K03 and P03 in the set table/keypad, then P02 and saved-details fitting. Verify target width and actual rendered text size, not just absence of overflow (`lib/widgets/workout/set_entry_table.dart:363`, `lib/widgets/workout/set_entry_table.dart:655`, `lib/widgets/workout/set_entry_table.dart:937`).
3. **Make async mutations reviewable and recoverable.** Add guard/progress/error handling for H04/P01/W03/S01; preserve drafts on failure and announce progress. Finish and Edit workout already contain guarded/error patterns (`lib/screens/workout_screen.dart:362`, `lib/screens/history_screen.dart:504`).
4. **Repair task discovery and action meaning.** Expose plan actions, make Resume target the session, explain Start/Finish, validate week input, and add login recovery/field errors. References are in H02/DB02/W04/W05/L01/L02 above.
5. **Close accessibility and responsive gaps.** Fix Home/Dashboard targets, Back naming, sparkline alternatives, headings and progress semantics. Reproduce the four layout risks with current fonts and add focused regression coverage; cap Settings width.
6. **Unify utility UI.** Replace repeated spacing literals with `AppSpacing`, use sentence-case theme typography, distinguish destructive actions, and align navigation labels. Keep intentional chart dimensions, set geometry, and minimum target sizes as explicit component constraints rather than converting every number into a page-spacing token.

## Verification and limits

- Static analysis passed using the installed Flutter tool with `analyze --no-pub`.
- Existing UI/theme suite: **185 passed, 1 failed**. The clear-split test passed its data-preservation assertions but failed to find the success snackbar (`test/screen_layout_test.dart:713`, `test/screen_layout_test.dart:720`). An isolated rerun failed earlier because Google Fonts runtime fetching was disabled and font assets were unavailable. This is **not established as a product defect**.
- Four temporary widget probes passed: Home day width, narrow set-table width, keypad semantic value, completed-workout drag scrolling. Probe file was removed afterward.
- Existing tests cover numerous 1.3x/2x, compact/desktop, semantics, theme contrast, and radius cases (`test/screen_layout_test.dart:192`, `test/history_redesign_test.dart:718`, `test/theme_contrast_test.dart:1`). Passing them does not prove readable fitted text or production-font layout.
- No current screenshots, TalkBack/VoiceOver session, live authentication, Android keyboard/insets, or installer run was captured. Extra runtime questions in the screen checklists are explicitly unverified and are not promoted to confirmed defects.
- No screen-level literal hex UI colors or raw corner-radius violations were found. Theme contrast checks passed. Intentional alpha-only shader stops were excluded (`lib/widgets/underline_tab_strip.dart:165`); no contrast failure is inferred merely from a small type size.

Review method also consulted the [Web Interface Guidelines](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md), adapted to Flutter and the project's own design/copy requirements.
