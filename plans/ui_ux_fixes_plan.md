# UI/UX Fixes — Create Plan + Edit Plan Screens (REVISED)

**Date**: 2026-06-19
**Goal**: Fix 4 issues in Create Plan screen (and Edit Plan screen), with proper handling of shared state, gesture conflicts, and data integrity.

---

## Prerequisites — Must fix before Fixes 2 and 4

### P1: Extract shared private model classes

**Files**: `lib/screens/create_plan_screen.dart`, `lib/screens/edit_plan_screen.dart`

Both files define identical private classes `_ExerciseSetData` and `_ExerciseWithSets`. Before any other work:

1. Create `lib/models/exercise_with_sets.dart`:
   ```dart
   import 'package:hive/hive.dart';

   class ExerciseSetData {
     final int reps;
     final double weight;

     ExerciseSetData({required this.reps, required this.weight});

     ExerciseSetData copyWith({int? reps, double? weight}) {
       return ExerciseSetData(
         reps: reps ?? this.reps,
         weight: weight ?? this.weight,
       );
     }
   }

   class ExerciseWithSets {
     final String name;
     final List<ExerciseSetData> sets;

     ExerciseWithSets({required this.name, required this.sets});

     ExerciseWithSets copyWith({String? name, List<ExerciseSetData>? sets}) {
       return ExerciseWithSets(
         name: name ?? this.name,
         sets: sets ?? this.sets,
       );
     }
   }
   ```
2. Remove the private class definitions from both screen files.
3. Update all usages of `_ExerciseSetData` → `ExerciseSetData` and `_ExerciseWithSets` → `ExerciseWithSets` in both files.
4. Update imports in both screen files to include `'../models/exercise_with_sets.dart'`.

### P2: Acknowledge data-model limitation (out of scope for this plan)

`ExerciseTemplate` stores only `name` + `sets` (int count). Actual per-set reps/weight are never persisted. Editing a plan **always** destroys existing set data (resets to 8 reps, 0 kg). Fixing this requires a Hive model change (adding reps/weight to ExerciseTemplate or a new SetTemplate model) — **not included in this plan**. Record this as a known limitation in a comment at the top of both screen files. No data-model code change here, but the limitation must be stated so the dev doesn't mistakenly believe Fix 4 reordering preserves data that was already lost earlier in the edit flow.

---

## Fix 1: Custom Exercise Button in Add Exercise Sheet

**Files**: `lib/screens/create_plan_screen.dart`, `lib/screens/edit_plan_screen.dart`

### Current Behavior
In `_showAddExerciseSheet()`, the GridView shows only exercises from the selected category. No way to add a custom-named exercise.

### Design Decision (must document as comment in code)
Custom exercises are **session-only**. They are added to the local `_exercises` list but not persisted to `ExerciseLibrary`. The user cannot re-select a previously created custom exercise from the grid. This is acceptable because the plan creation flow is single-session. If cross-session persistence is desired, it's future work.

### Changes

**a) Grid item count and custom button:**
- Increase `GridView.builder` `itemCount` from `exercises.length` to `exercises.length + 1`.
- For index `i == exercises.length`, render a custom tile instead of an exercise tile:
  - Solid border with `borderColor(context)` at reduced opacity (e.g., `withAlpha(128)`).
  - Label text "[+ CUSTOM]" with accent color.
  - Tapping it calls `_showCustomExerciseDialog(ctx, setSheetState)`.

**b) `_showCustomExerciseDialog` method:**
- Signature: `void _showCustomExerciseDialog(BuildContext sheetContext, void Function(void Function()) setSheetState)`
- Opens a dialog (using `showDialog` with theme styling matching the app: `surfaceColor(context)` background, `jetBrainsMono` text).
- Contains a `TextField` with:
  - `hintText: 'Enter exercise name'`
  - `autofocus: true`
  - Validation logic:
    - **Empty string** → show inline error "Name cannot be empty".
    - **Duplicate name** (check against `_exercises.map((e) => e.name)`) → show error "Exercise with this name already exists".
    - **Valid** → enable confirm button.
  - `textCapitalization: TextCapitalization.words`
  - `onChanged` handler that runs validation and calls `setSheetState` to update button enabled state.
- Two buttons: `[CONFIRM]` (disabled while invalid) and `[CANCEL]`.
- On confirm: call `setState` (parent state) to add a new `ExerciseWithSets` with the entered name and 3 default `ExerciseSetData(reps: 8, weight: 0)`, mark it expanded in `_expandedExercises`, then close the sheet via `Navigator.pop(sheetContext)`.

---

## Fix 2: Tappable Stepper Number — Inline TextField

**Files**: `lib/widgets/workout/stepper_widget.dart` (NEW), then update imports in both screen files

### Current Behavior
`_buildStepper()` shows number as a plain `Text` widget. User can only change value via `-` / `+` buttons. The method exists as identical private code in both screen files.

### Change

**a) Create `lib/widgets/workout/stepper_widget.dart`:**
- Extract a `StepperWidget` **StatefulWidget** with these constructor parameters:
  ```dart
  class StepperWidget extends StatefulWidget {
    final double value;
    final double min;
    final double max;      // NEW: explicit max (was hardcoded 999 in clamp)
    final double step;
    final Color accent;
    final Color backgroundColor;
    final Color surfaceColor;
    final Color borderColor;
    final Color textPrimaryColor;
    final Color textSecondaryColor;
    final void Function(double) onChanged;

    const StepperWidget({super.key, required this.value, ...});
  }
  ```
  Theme colors are passed explicitly to avoid `context` dependency inside the widget (makes it testable and reusable).

- **State** fields:
  - `late TextEditingController _controller`
  - `late FocusNode _focusNode`
  - `bool _isEditing = false`
  - `double _currentValue` (synced from `widget.value`)

- **Lifecycle**:
  - `initState`: create controller and focus node, set initial text via `_formatValue(widget.value)`, add focus listener that calls `_commitValue()` on focus loss.
  - `didUpdateWidget`: if `widget.value != _currentValue`, sync controller text.
  - `dispose`: dispose controller and focus node.

- **Display mode** (`_isEditing == false`):
  - Same layout as current: `-` button | number display | `+` button.
  - Number display is a `GestureDetector` wrapping a `Container`:
    - On tap → `setState(() => _isEditing = true)`, then request focus via `_focusNode.requestFocus()`.
    - Text content uses `_formatValue(_currentValue)`.

- **Edit mode** (`_isEditing == true`):
  - `-` and `+` buttons hidden (to avoid confusion while typing).
  - Center area becomes a `TextField`:
    - `keyboardType: TextInputType.numberWithOptions(decimal: true)`
    - `controller: _controller`
    - `focusNode: _focusNode`
    - `autofocus: true`
    - `textAlign: TextAlign.center`
    - Style matching the existing text display (`jetBrainsMono`, same color, same font size).
    - `textInputAction: TextInputAction.done` (shows "done" on keyboard)
    - `onSubmitted: (_) => _commitValue()`

- **`_commitValue()` method**:
  ```dart
  void _commitValue() {
    final text = _controller.text.trim();
    final parsed = double.tryParse(text);
    if (parsed == null || text.isEmpty) {
      // Reset to min on invalid input
      _currentValue = widget.min;
    } else {
      _currentValue = parsed.clamp(widget.min, widget.max);
    }
    _controller.text = _formatValue(_currentValue);
    widget.onChanged(_currentValue);
    setState(() => _isEditing = false);
  }
  ```

- **`_formatValue(double val)` helper**: mirrors existing logic:
  ```dart
  String _formatValue(double val) {
    return val == val.roundToDouble() ? '${val.toInt()}' : val.toString();
  }
  ```

**b) Update both screen files:**
- Add import: `import '../widgets/workout/stepper_widget.dart';`
- Remove the private `_buildStepper` method from both files.
- Replace all calls to `_buildStepper(...)` with `StepperWidget(...)`, passing:
  - `backgroundColor: backgroundColor(context)`
  - `surfaceColor: surfaceColor(context)`
  - `borderColor: borderColor(context)`
  - `textPrimaryColor: textPrimaryColor(context)`
  - `textSecondaryColor: textSecondaryColor(context)`
  - Existing params: `value`, `min`, `step`, `accent`, `onChanged`
  - New param: `max: 999` (formerly hardcoded in clamp)

---

## Fix 3: Double Outline in Plan Name Input

**Files**: `lib/screens/create_plan_screen.dart`, `lib/screens/edit_plan_screen.dart`

### Current Behavior
The `TextField` inside `_buildPlanNameInput()` has `border: InputBorder.none` but Flutter may still render default underlines/outlines (especially on focus or via theme), creating a double-outline effect with the Container's outer border.

### Change
Explicitly suppress all border variants in the `InputDecoration`:
```dart
decoration: const InputDecoration(
  hintText: 'e.g. PUSH DAY',
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
),
```

Safe change. No side effects. No state management changes needed.

---

## Fix 4: Draggable Exercise Cards (Reorder)

**Files**: `lib/screens/create_plan_screen.dart`, `lib/screens/edit_plan_screen.dart`

### Current Behavior
Exercise cards are in a `ListView.builder` — no reorder support.

### Changes

**a) Restructure the exercise list area:**
```
Expanded(
  child: _exercises.isEmpty
      ? _buildEmptyState()
      : ReorderableListView.builder(
          itemCount: _exercises.length,
          buildDefaultDragHandles: false,   // KEY: manual drag handles to avoid gesture conflicts
          proxyDecorator: _buildReorderProxyDecorator,
          itemBuilder: (context, index) {
            // Key is applied to the top-level Padding below
            return Padding(
              key: ValueKey(_exercises[index].name),   // stable key by name
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildExerciseCard(_exercises[index], index, accent),
            );
          },
          onReorder: _onReorder,
        ),
),
```

The empty-state ternary is safe here because once `_exercises` transitions to non-empty, the widget type becomes `ReorderableListView` and stays that type. If the last exercise is deleted, the widget tree changes type at the `Expanded` child — Flutter handles this fine by unmounting the old widget and mounting the new one.

**b) `buildDefaultDragHandles: false`** — Required to prevent the entire card from being long-press draggable, which would conflict with the expand/collapse `InkWell` that wraps the card header. Only the explicit drag handle triggers reorder.

**c) Stable item keys:**
Use `ValueKey(exercise.name)` for each item. This is suitable because exercise names are unique within a plan (the add-exercise dialog already prevents duplicates). Apply the key to the top-level `Padding` returned by `itemBuilder`.

**d) Drag handle placement and gesture:**
Add the drag handle to the exercise card header **before** the expand/collapse `InkWell`, not inside it. Restructure the header `Row`:

```
Row(
  children: [
    // DRAG HANDLE — outside InkWell, uses ReorderableListViewDragStartListener
    ReorderableListViewDragStartListener(
      index: exerciseIndex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.drag_handle, size: 16, color: textSecondaryColor(context)),
      ),
    ),
    const SizedBox(width: 4),
    // Expand/collapse InkWell wraps the rest of the header content
    Expanded(
      child: InkWell(
        onTap: () => setState(() =>
            _expandedExercises[exerciseIndex] = !(_expandedExercises[exerciseIndex] ?? false)),
        child: Row(children: [
          Text('[${(exerciseIndex + 1).toString().padLeft(2, '0')}]'),
          const SizedBox(width: 8),
          Expanded(child: Text(exercise.name, ...)),
          Text('${exercise.sets.length} SETS', ...),
          InkWell(onTap: () => setState(() => _exercises.removeAt(exerciseIndex)), child: ...),
          Icon(expanded ? Icons.expand_less : Icons.expand_more, ...),
        ]),
      ),
    ),
  ],
)
```

`ReorderableListViewDragStartListener` (from `package:flutter/material.dart`) handles the long-press/reorder start gesture correctly without conflicting with parent `InkWell` tap handlers.

**e) `onReorder` callback with correct state remapping:**

```dart
void _onReorder(int oldIndex, int newIndex) {
  setState(() {
    // Adjust newIndex for ReorderableListView convention
    if (newIndex > oldIndex) newIndex -= 1;

    // Reorder the exercises list
    final item = _exercises.removeAt(oldIndex);
    _exercises.insert(newIndex, item);

    // Remap _expandedExercises to follow exercises, not positions
    final oldExpanded = Map<int, bool>.from(_expandedExercises);
    _expandedExercises = {};

    for (int i = 0; i < _exercises.length; i++) {
      // oldIndex is now gone from the list; everything shifted
      int originalIndex;
      if (i >= newIndex && i < oldIndex) {
        // Items that were after newIndex but before oldIndex moved right by 1
        originalIndex = i + 1;
      } else if (i <= oldIndex && i > newIndex) {
        // Items that were before oldIndex but after newIndex moved left by 1
        originalIndex = i - 1;
      } else if (i == oldIndex) {
        // This shouldn't happen since oldIndex was removed, but safety
        originalIndex = i;
      } else {
        originalIndex = i;
      }
      // Except: the item now at newIndex is the moved item (was at oldIndex)
      if (i == newIndex) {
        originalIndex = oldIndex;
      }
      if (oldExpanded.containsKey(originalIndex)) {
        _expandedExercises[i] = oldExpanded[originalIndex]!;
      }
    }
  });
}
```

**Simplify with a map rebuild approach (alternative, clearer):**
```dart
void _onReorder(int oldIndex, int newIndex) {
  setState(() {
    if (newIndex > oldIndex) newIndex -= 1;

    // Build a name-to-expanded mapping before reorder
    final expandedByName = <String, bool>{};
    for (int i = 0; i < _exercises.length; i++) {
      if (_expandedExercises[i] == true) {
        expandedByName[_exercises[i].name] = true;
      }
    }

    // Reorder
    final item = _exercises.removeAt(oldIndex);
    _exercises.insert(newIndex, item);

    // Rebuild _expandedExercises from name mapping
    _expandedExercises = {};
    for (int i = 0; i < _exercises.length; i++) {
      if (expandedByName[_exercises[i].name] == true) {
        _expandedExercises[i] = true;
      }
    }
  });
}
```

This name-based approach is simpler, correct, and immune to off-by-one errors in index arithmetic. Use this version.

**f) Custom proxy decorator for drag feedback:**
Match the app's terminal theme (flat surfaces, no shadows, colored borders):
```dart
Widget _buildReorderProxyDecorator(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      return Material(
        color: surfaceColor(context),
        elevation: 0,   // flat, no shadow — matches app theme
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor(context)),
          borderRadius: BorderRadius.zero,
        ),
        child: child,
      );
    },
    child: child,
  );
}
```

**g) Delete handler compatibility:**
The existing delete button calls `setState(() => _exercises.removeAt(exerciseIndex))`. This works correctly with `ReorderableListView` as long as keys are stable (they are — `ValueKey(exercise.name)`). No additional changes needed. Note: deleting an item while a drag animation is in-flight may produce a Flutter key error, but simultaneous drag+delete is prevented by the UI (drag starts from handle, delete is at the opposite end of the card header).

---

## Verification

```bash
flutter analyze
```

Must pass with 0 errors.

### Manual test checklist:
1. **Fix 1** — Create Plan → tap [+ ADD EXERCISE] → scroll to bottom of any category → verify "[+ CUSTOM]" tile exists. Tap it → enter empty name → verify error shown. Enter duplicate name → verify error. Enter valid name → verify it appears in exercise list with 3 default sets and is expanded.
2. **Fix 2** — Tap a stepper number (reps or kg) → verify it turns into a TextField with keyboard. Type a value → press Enter → verify it commits and closes. Repeat → tap outside the field → verify it commits. Type non-numeric text → verify it resets to minimum value on commit.
3. **Fix 3** — Focus the plan name TextField → verify no double-border or underline appears.
4. **Fix 4** — Add 3+ exercises → long-press a drag handle → drag to reorder → verify list reorders smoothly. Verify expand/collapse state follows the exercise, not the position. Verify the delete button still works after reordering.
5. **Duplication** — Repeat all above steps in Edit Plan screen. Verify identical behavior.
