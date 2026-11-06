---
name: refresh-screenshots
description: Refresh OpenGym's screenshots/ gallery after UI changes, using the running app and realistic sample history in both themes. Use for screenshot refresh or recapture requests, not for implementing UI changes.
---

# Refresh OpenGym screenshots

Update the requested images in `screenshots/`. Default to the whole existing gallery when no subset is specified. Preserve filenames used by README.md and existing light/dark coverage; inspect the current files and README before capture. Follow the project's AGENTS.md. Do the capture work, not just provide commands.

## Prepare the real app

Prefer Flutter web at a mobile viewport: it excludes Android's status bar and navigation dock without cropping app content. Use the current source and bundled fonts. Use an isolated local browser profile/origin containing only demo data; never replace personal training data or sign into an account for screenshots.

The included [assets/preview.dart](assets/preview.dart) skips onboarding and starts the normal app. From the project root:

```bash
flutter build web --debug --no-wasm-dry-run \
  --target .agents/skills/refresh-screenshots/assets/preview.dart \
  --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  --output build/screenshot-preview
python3 -m http.server 8083 --bind 127.0.0.1 --directory build/screenshot-preview
```

Use persistent command sessions for long builds and the server. Pick another free port if needed. Debug mode is intentional: **Load sample data** is hidden in release builds. Keep the empty backend defines so the normal app starts offline. Do not change production code, auth settings, or signing configuration to make capture easier.

Use the shared browser tools available in the session. In T3 Code, call `preview_status`, then `preview_open`; use that browser unless its documented fallback conditions apply. Start with 430 × 956 CSS pixels (860 × 1912 PNG at DPR 2). Match actual screenshot dimensions, not an assumed device scale. Keep the same framing across theme pairs. A taller viewport is useful for a dense statistics screen; avoid excessive blank space.

## Populate through Settings

Open **Settings → Load sample data → Load** and wait for **Sample data refreshed**. Load once for the capture batch, then preserve that dataset while navigating and changing themes. Do not substitute hand-painted values, modified DOM labels, hardcoded screen fixtures, or old PNGs.

The seeder in `lib/services/sample_data_seeder.dart` should provide several populated blocks, gradual progress, and history for all five plans. Verify what the current build actually shows:

- Home has plans and recent training; History has plausible sessions and dates.
- Open a plan's current week with recorded history. Workout **Previous** must show real weights × reps for the visible exercises. Previous follows structural plan/exercise/set slots: an arbitrary first week or new plan can legitimately have no history and makes a poor showcase.
- Statistics has several logged weeks, an exercise with multiple strength observations, populated records, and multiple populated blocks for the block trend.

If sample coverage is still missing or looks implausible, tell the user the concrete defect. Capture suitable populated views where possible and report any images that could not be refreshed honestly. Do not silently fix the seeder unless that work is also requested.

## Capture the gallery

Use current controls and fresh accessibility snapshots; do not rely on coordinates or refs from an earlier run. Flutter may initially expose only **Enable accessibility**. Activate it before inspecting semantic controls. If a canvas scroll does not move, dispatch a wheel event to the element at the intended scroll position through browser evaluation; verify the resulting screen. Navigation, loading, and theme transitions must finish before capture.

| Filenames (existing variants only) | Show |
| --- | --- |
| `home`, `home_dark` | Plan list, next workout, recent training |
| `history`, `history_dark` | Several logged workouts, dates, volume, PRs |
| `statistics`, `statistics_dark` | Weekly overview and training rhythm |
| `statistics_2` | Block progress with multiple populated blocks; frame workload/gains if more useful |
| `statistics_3` | Exercise strength trend with several points and readable values |
| `statistics_records`, `statistics_records_dark` | Records with lift names, weights/reps, dates |
| `settings`, `settings_dark` | Appearance and useful preferences |
| `block_menu`, `block_menu_dark` | Open block selector with actual populated blocks |
| `block_create`, `block_create_dark` | Create dialog with a plausible name and week count; cancel afterwards |
| `workout`, `workout_dark` | Active logging with populated Previous and plausible current sets |
| `workout_keypad`, `workout_keypad_dark` | Same workout with numeric keypad open and previous sets visible |

Capture Home, History, Settings, and Statistics before starting a workout, so the workout-in-progress banner does not obscure their content. For workout captures, select a plan with history, start or resume its current week, and open a weight field for keypad shots. Keep the workout and week consistent across theme pairs. Avoid adding unnecessary weeks or blocks solely to fill a screenshot. Cancel dialogs and dismiss transient notifications before navigation.

Move the pointer to a neutral margin and allow hover highlights, tooltips, ripples, snackbars, and animations to disappear before saving. Save browser screenshot artifacts, inspect them, then copy approved PNGs into `screenshots/`. Native-device capture is also acceptable when necessary, using the session's device tools; remove only system chrome and retain the app's own header, bottom navigation, week controls, and keypad.

## Verify and finish

Inspect **every replaced image**, individually or in a legible contact sheet, and zoom into the workout and chart captures. Confirm correct page/theme, populated Previous, readable charts/records, no system bars/browser chrome, no tooltips/errors/loading screens, and no accidental duplicates. File changes alone do not prove successful capture.

Check that the requested coverage was replaced and README image links still resolve. Run `flutter analyze` as required by the project. Remove temporary launchers/artifacts outside ignored build output and stop only servers/apps/tabs created for this task. Commit screenshot files explicitly under the project workflow; leave unrelated edits untouched. Do not push or release unless requested. Report the refreshed coverage, verification, commit, and any remaining sample-data limitations.
