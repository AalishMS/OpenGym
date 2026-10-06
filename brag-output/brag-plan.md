# OpenGym brag plan

## Answers
- **What it is:** a clean, focused gym tracker for planning workouts, logging lifts, and seeing progress. Offline first, optional sync.
- **Who it's for:** anyone who lifts and wants a dependable record without turning each workout into a data-entry session.
- **What sets it apart:** set logging is built for between sets: last session's weights auto-fill, a big keypad with +2.5 / -2.5 nudges, one Save. Your split knows what's "Next up". Open source (MIT), works without a connection.
- **Most impressive claim:** "Auto-fill last weights" plus the numeric keypad: log a set without typing.
- **Visual hook:** cyan on black, the `> OpenGym` wordmark, big numbers.
- **Real UI to show:** Home (Next up card + Start workout), Workout screen, keypad sheet, Statistics (volume bars, estimated 1RM line, recent records), dark mode home.
- **Tone:** `default` leaning `app-store`: punchy, clean, calm surfaces like the app itself.
- **Share caption:** OpenGym: plan the split, log a set without typing, watch the lifts climb. Offline first, open source.

## Angle
"Lift. Log it. Lift again." The app is the 10 seconds between sets. Everything in the video is about how little the app asks of you.

## Visual identity
- Background `#0D0D0D` (the app's dark background), surface `#1E1E1E`, accent cyan `#00CED1` (dark-mode fill) and `#00A0A3` (light fill).
- Manrope (interface font) for all type, JetBrains Mono for numbers, as in the app.
- Real screenshots from `screenshots/` inside a phone frame; the keypad sheet is composited from the real keypad screenshot so it can slide up, and the kg value animates 70 → 72.5 on a +2.5 tap.
- 1920×1080, 30fps, 120 BPM grid (scene cuts on beats).

## Storyboard (22.0s)
| # | Time | Scene | On screen | Motion / sound |
|---|---|---|---|---|
| 1 | 0.0–2.5 | Hook | "Lift." / "Log it." / "Lift again." stacked, "Log it." in cyan | Each word lands on a beat with a soft hit; pad swell |
| 2 | 2.5–5.5 | Reveal | `> OpenGym` types in with caret; "A clean, focused gym tracker." + "Plan workouts · Log lifts · See progress" | Kick enters on the wordmark |
| 3 | 5.5–8.5 | Next up | Phone slides up with light Home. Caption: "Open it. Your next workout is waiting." | Phone eases up, slow push-in to Next up card, tap ripple on Start workout |
| 4 | 8.5–13.0 | Log a set | Phone switches to Workout screen; keypad sheet slides up. Caption: "Last session's weights, pre-filled." then "Nudge. Save. Back to the bar." | Tap +2.5 (70 → 72.5), tap Save, sheet slides away |
| 5 | 13.0–16.5 | Progress | Two phones: Statistics volume bars and Bench Press estimated 1RM. Caption: "Watch every lift climb." sub "Volume, estimated 1RM and new records." | Phones fan in, staggered |
| 6 | 16.5–19.0 | Anywhere | Home light → dark wipe. Caption: "Works offline. Syncs when you want." sub "Light or dark, your accent." | Cyan wipe line sweeps the phone |
| 7 | 19.0–22.0 | Outro | Big `> OpenGym`, accent cycles through the app's accent swatches and settles cyan. "Open source · Get the APK on GitHub" + github.com/AalishMS/OpenGym | Final chord hit, ring out |

## Sound
Apple Loops (GarageBand library, royalty-free), Chillwave "Moving Pictures" set at 120 BPM: Synth, Bass, Rhythm Guitar, Acoustic Guitar, with the "Minimal Backbeat 01" drum loop. Every stem is phase-locked to the downbeat at 2.5s. The filtered synth opens up under the hook, the full band drops on the wordmark, rhythm guitar enters at 5.5s, and acoustic guitar adds lift at 8.5s. The drums drop out for a half-bar break at 18.5s and everything re-enters on the outro at 19.0s, then fades over the last second. Effects are unpitched (thumps, clicks, filtered whooshes) so they can't clash with the loops' key. Built by `work/mix.mjs A`, loudness-normalized to -15 LUFS.
