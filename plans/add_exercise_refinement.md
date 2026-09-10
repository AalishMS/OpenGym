# Redesign the add-exercise picker

## Summary

Replace the text-heavy opening list with a visual muscle-group browser. Keep search prominent and preserve immediate add/remove behaviour. Apply the same picker to plan editing and active workouts.

The current implementation gives too many elements equal emphasis, truncates exercise names, and provides no consolidated selection review.

## Interface and navigation

- Open a near-full-height bottom sheet with **Add exercises**, a close control, and search. Do not open the keyboard automatically.
- Show six muscle-group tiles in a two-column grid: Chest, Back, Shoulders, Arms, Legs, Core. Each contains a body-area illustration, group name, and exercise count.
- Use bundled, code-drawn vector silhouettes with the relevant region highlighted using theme colours. These are navigation cues, not detailed anatomy diagrams.
- Tapping a group replaces the grid with its exercise list. A **Muscle groups** back control and group heading keep the location clear.
- Search spans the entire library from any view. Show category subtitles in results; clearing search restores the previous browsing view.
- Keep **Create custom exercise** as a separate secondary action below search, rather than an exercise-shaped first result.

## Exercise selection and visual treatment

- Use quiet list rows with readable names and a trailing checkbox. Allow names to wrap; remove repeated ADD/REMOVE labels and individual heavy borders.
- Make the whole row tappable, with at least a 48-pixel target. Selected rows receive a subtle accent wash and checked control.
- Pin **Selected (n)** and **Done** in the footer. Selected opens a review list containing all current selections, including custom exercises; Back restores browsing.
- Changes apply immediately. Use concise supporting copy: “Changes apply as you select.” Done, close, and dismiss retain changes.
- Provide explicit empty states for search and selection review. An unsuccessful search offers custom creation prefilled with the search text.
- Use sentence case and existing app typography, spacing, colour, and radius tokens throughout, including the custom-exercise dialog.
- Keep search and footer reachable above the keyboard; make the content scroll and adapt the grid to one column when large text requires it.

## Implementation

- Consolidate both implementations into `lib/widgets/exercise_picker_sheet.dart`; make the plan editor use the existing callback interface.
- Preserve `selectedExerciseNames`, `onAdd`, `onRemove`, and `selectionOwner`. Retain display names alongside case-insensitive selection keys so custom selections can be reviewed.
- Keep the existing exercise catalog and ordering. Derive group counts and search category labels from its category mapping.
- Preserve caller behaviour: plan edits remain local until saved; workout edits continue autosaving. No Hive model changes, dependencies, or network assets.
- Preserve current removal semantics; this redesign does not introduce staged changes or undo.

## Verification

- Test group navigation, global search, clearing search, no results, selection review, and custom creation with blank/duplicate validation.
- Verify selection consistency across views and retention after dismissal, in both plan and workout flows.
- Check narrow phones, keyboard visibility, large text, long names, screen-reader labels, and light/dark themes.
- Visually inspect the grid, exercise list, search results, and selected view before accepting the design.
- Run required Flutter analysis after edits, relevant picker/integration tests, and theme contrast tests.

**Defaults:** muscle groups first; immediate changes; illustrated categories rather than individual exercise images; no new history, favourites, equipment filters, or exercise coaching content.
