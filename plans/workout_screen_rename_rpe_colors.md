# Workout Screen Rename And RPE Colors Implementation Plan

> [!NOTE]
> This plan is retained as implementation history. Its typography references
> describe the app at that time; use `DESIGN.md` for current product direction.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update workout screen exercise renaming to happen on tap instead of long press, and color-code only the displayed RPE value in set rows.

**Architecture:** Keep the existing workout screen structure unchanged. Make the smallest UI-only changes in `ExerciseCard` and `SetRow`, without changing Hive models, providers, dialogs, or reorder behavior.

**Tech Stack at implementation time:** Flutter, Dart, Provider, Hive, Material widgets, and Google Fonts.

---

### Task 1: Change Exercise Rename Gesture

**Files:**
- Modify: `lib/widgets/workout/exercise_card.dart`

**Step 1: Locate the exercise name InkWell**

Find the `InkWell` around `exercise.name.toUpperCase()`.

Current behavior:

```dart
onLongPress: () => onRename(exerciseIndex),
```

**Step 2: Change long press to tap**

Replace it with:

```dart
onTap: () => onRename(exerciseIndex),
```

**Step 3: Keep reorder behavior unchanged**

Do not modify `lib/screens/workout_screen.dart`.

The reorder listener should remain:

```dart
ReorderableDelayedDragStartListener(
  key: ValueKey(index),
  index: index,
  child: Container(
    ...
  ),
)
```

**Step 4: Verify expected behavior manually**

Expected behavior:
- Tapping an exercise name opens the rename exercise dialog.
- Long-press dragging the exercise card still reorders exercises.
- Long-pressing the exercise name no longer opens rename.

---

### Task 2: Color-Code Displayed RPE Only

**Files:**
- Modify: `lib/widgets/workout/set_row.dart`

**Step 1: Add an RPE color helper**

Add a private helper inside `SetRow` or below the class:

```dart
Color _rpeColor(int rpe) {
  if (rpe <= 2) return Colors.grey;
  if (rpe <= 4) return Colors.lightBlue;
  if (rpe <= 6) return Colors.green;
  if (rpe <= 8) return Colors.yellow;
  if (rpe == 9) return Colors.orange;
  return Colors.red;
}
```

**Step 2: Replace the single Text widget with RichText**

Current display:

```dart
Text(
  '${set.weight}kg x ${set.reps}${set.rpe != null ? ' @${set.rpe}' : ''}',
  style: GoogleFonts.jetBrainsMono(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: textPrimaryColor(context),
  ),
)
```

Replace with a `RichText` where only the RPE span is colored:

```dart
RichText(
  text: TextSpan(
    style: GoogleFonts.jetBrainsMono(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: textPrimaryColor(context),
    ),
    children: [
      TextSpan(text: '${set.weight}kg x ${set.reps}'),
      if (set.rpe != null)
        TextSpan(
          text: ' @${set.rpe}',
          style: TextStyle(color: _rpeColor(set.rpe!)),
        ),
    ],
  ),
)
```

**Step 3: Leave dialogs unchanged**

Do not change:
- `WorkoutDialogs.showAddSetDialog`
- `WorkoutDialogs.showEditSetDialog`

RPE picker buttons should keep the existing accent-based selected state.

**Step 4: Verify expected color mapping**

Expected displayed RPE colors:
- RPE 1-2: grey
- RPE 3-4: light blue
- RPE 5-6: green
- RPE 7-8: yellow
- RPE 9: orange
- RPE 10: red

---

### Task 3: Static Analysis

**Files:**
- No file edits unless analyzer errors require fixes.

**Step 1: Run analyzer**

Run:

```bash
flutter analyze
```

**Expected:**
- No analyzer errors.
- Existing warnings or info-level issues can remain if unrelated.

**Step 2: Fix any errors from changed files**

If errors appear in:
- `lib/widgets/workout/exercise_card.dart`
- `lib/widgets/workout/set_row.dart`

Fix only those errors.

**Step 3: Re-run analyzer**

Run:

```bash
flutter analyze
```

**Expected:**
- No analyzer errors.

---

### Task 4: Update Project Context

**Files:**
- Modify: `opencode.md`

**Step 1: Add a short Recent Changes entry**

Add a concise entry under `## Recent Changes`:

```markdown
- Updated workout screen exercise interactions:
  - Tapping an exercise name now opens the rename dialog.
  - Long-press drag remains reserved for exercise reordering.
  - Displayed RPE values are color-coded by exertion level.
```

**Step 2: Run analyzer again if Dart files changed after this point**

Run:

```bash
flutter analyze
```

**Expected:**
- No analyzer errors.
