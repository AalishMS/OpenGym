# UI/UX Redesign Plan — Home + Create Plan Screens

**Date**: 2026-06-19
**Goal**: Improve Home screen and Create Plan screen UI/UX following Figma prototype design, keeping existing theme/color system intact.

---

## Overview

| Phase | Description | Files Changed |
|-------|-------------|---------------|
| 0 | Git backup commit | — |
| 1 | Add `planColor` field to WorkoutPlan Hive model | `workout_plan.dart`, `workout_plan.g.dart`, `sample_data_seeder.dart`, `plan_colors.dart` (new) |
| 2 | Bottom navigation bar widget (4 tabs) | `lib/widgets/app_bottom_nav.dart` (new) |
| 3 | Home screen redesign | `home_screen.dart` |
| 4 | Create Plan screen redesign | `create_plan_screen.dart` |
| 5 | Edit Plan screen follow-up | `edit_plan_screen.dart` |
| 6 | Update main.dart for bottom nav | `main.dart` |

---

## Phase 0: Git Backup

```bash
git add -A
git commit -m "backup before UI/UX redesign - Home + Create Plan"
```

---

## Phase 1: Add `planColor` to WorkoutPlan Model

### 1a. Create `lib/data/plan_colors.dart`

```dart
const List<int> kPlanColors = [
  0xFFa78bfa, // purple
  0xFFf472b6, // hot pink
  0xFF22d3ee, // cyan
  0xFF60a5fa, // electric blue
  0xFFfbbf24, // warm amber
  0xFF34d399, // emerald
  0xFFfb923c, // deep orange
  0xFFef4444, // red
  0xFF818cf8, // indigo
  0xFFe879f9, // fuchsia
];
```

### 1b. Modify `lib/models/workout_plan.dart`

Add `@HiveField(2)` for plan color as a nullable `int` (stores `Color.value`):

```dart
@HiveField(2)
final int? planColor;
```

Update constructor:
```dart
WorkoutPlan({
  required this.name,
  required this.exercises,
  this.planColor,
});
```

Update `toJson()`:
```dart
Map<String, dynamic> toJson() => {
  'name': name,
  'exercises': exercises.map((e) => e.toJson()).toList(),
  'planColor': planColor,
};
```

Update `fromJson`:
```dart
factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
  name: json['name'] as String,
  exercises: (json['exercises'] as List)
      .map((e) => ExerciseTemplate.fromJson(e as Map<String, dynamic>))
      .toList(),
  planColor: json['planColor'] as int?,
);
```

### 1c. Run build_runner

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This regenerates `workout_plan.g.dart` with the new field. The generated adapter will read/write field index 2.

If the build_runner fails, manually update `workout_plan.g.dart`:
- Add `planColor` read: `fields[2] as int?` in `read()`
- Update `write()`: increment `writeByte` count from 2 to 3, add `..writeByte(2)..write(obj.planColor)`

### 1d. Update `lib/services/sample_data_seeder.dart`

Import `plan_colors.dart` and assign colors to each sample plan:

```dart
import '../data/plan_colors.dart';
```

```dart
WorkoutPlan(
  name: 'Push Day',
  exercises: [...],
  planColor: kPlanColors[0],
),
WorkoutPlan(
  name: 'Pull Day',
  exercises: [...],
  planColor: kPlanColors[1],
),
// etc.
```

### 1e. Migration Note

**⚠️ Note for existing user data:** `planColor` is nullable (`int?`). Existing plans without a color will render with the app's accent color as fallback (`plan.planColor != null ? Color(plan.planColor!) : accent`). This is cosmetic only — no data migration needed. Users can assign colors via the long-press `[COLOR]` option added in Phase 3f.

---

## Phase 2: Bottom Navigation Bar Widget (4 tabs)

**New file**: `lib/widgets/app_bottom_nav.dart`

### Specs

- **Background**: `surfaceColor(context)`
- **Top border**: `1px` `borderColor(context)`
- **Height**: ~56px
- **4 tabs**:

| Tab | Icon | Label |
|-----|------|-------|
| PLANS | `Icons.grid_view` | `PLANS` |
| HISTORY | `Icons.history` | `HISTORY` |
| STATS | `Icons.bar_chart` | `STATS` |
| SETTINGS | `Icons.settings` | `SETTINGS` |

- **Active tab**: Icon + label in `accent` color
- **Inactive tab**: Icon + label in `textSecondary` color
- **Font**: JetBrains Mono, `9px`, `0.08em` letter spacing

### Full Implementation

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav({required this.currentIndex, required this.onTap, super.key});

  static const _icons = [
    Icons.grid_view,
    Icons.history,
    Icons.bar_chart,
    Icons.settings,
  ];

  static const _labels = ['PLANS', 'HISTORY', 'STATS', 'SETTINGS'];

  @override
  Widget build(BuildContext context) {
    // accent and textSecondary MUST be declared from context
    final accent = context.watch<SettingsProvider>().accentColor;
    final textSecondary = textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: Row(
        children: List.generate(4, (i) {
          final active = i == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icons[i], size: 18, color: active ? accent : textSecondary),
                    const SizedBox(height: 3),
                    Text(
                      _labels[i],
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        letterSpacing: 0.08,
                        color: active ? accent : textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
```

---

## Phase 3: Home Screen Redesign

**File**: `lib/screens/home_screen.dart`

### Key Changes

1. **Remove FAB** — replace with inline "NEW PLAN" button at bottom of grid
2. **Remove header nav icons** (stats/history/settings) — navigation moves to bottom nav
3. **Redesign plan card** — add color strip, exercise preview, styled index
4. **Add long-press color change** option in dialog
5. **Rename import** (if history screen removed from imports)
6. **Grid + inline button** wrapped in a custom scroll view or column layout

### 3a. Remove Imports for Header Icons

Remove unused: `history_screen.dart`, `settings_screen.dart`, `stats_screen.dart` imports from home_screen if no longer directly navigated from header.

### 3b. Remove FAB

Delete the `floatingActionButton` parameter from `Scaffold`.

Delete the `_buildFab` method entirely.

### 3c. Simplify Header

```dart
Widget _buildHeader(BuildContext context, Color accent, Color border) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: border, width: 1)),
    ),
    child: Row(
      children: [
        Text(
          '> OPENGYM',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: accent,
          ),
        ),
      ],
    ),
  );
}
```

### 3d. Plan Card Redesign

Replace `_buildPlanCard` content:

```dart
Widget _buildPlanCard(
    BuildContext context, WorkoutPlan plan, int index, Color accent) {
  final surface = surfaceColor(context);
  final border = borderColor(context);
  final textPrimary = textPrimaryColor(context);
  final textSecondary = textSecondaryColor(context);
  final planColor = plan.planColor != null ? Color(plan.planColor!) : accent;

  final exerciseNames = plan.exercises.map((e) => e.name).toList();
  final previewLines = exerciseNames.take(3).toList();

  return InkWell(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutScreen(plan: plan, planIndex: index),
        ),
      );
    },
    onLongPress: () => _showPlanOptions(context, plan, index, accent),
    child: Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Color strip
          Container(height: 2, color: planColor),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Index badge
                  Text(
                    '[${(index + 1).toString().padLeft(2, '0')}]',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: textSecondary,
                      letterSpacing: 0.08,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Plan name
                  Text(
                    plan.name.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                      letterSpacing: 0.04,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Exercise preview
                  ...previewLines.map((name) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '· $name',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: textSecondary,
                        letterSpacing: 0.02,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                  if (exerciseNames.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '+${exerciseNames.length - 3} more',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: textSecondary.withAlpha(128),
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Exercise count
                  Text(
                    '${plan.exercises.length} EXERCISES',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: planColor,
                      letterSpacing: 0.06,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

### 3e. Inline "NEW PLAN" Button

Add below the GridView:

```dart
Widget _buildNewPlanButton(BuildContext context, Color accent) {
  final textSecondary = textSecondaryColor(context);
  return InkWell(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreatePlanScreen()),
      );
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: accent.withAlpha(60)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add, size: 12, color: textSecondary),
          const SizedBox(width: 8),
          Text(
            '[+ NEW PLAN]',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              letterSpacing: 0.1,
              color: textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}
```

To keep the grid + button in a scrollable view, wrap in a `CustomScrollView` or simply make the body a `Column` with `Expanded` grid + fixed bottom button:

```dart
// In build() — restructure the Column children
// The Scaffold body should be:
body: SafeArea(
  child: Column(
    children: [
      _buildHeader(context, accent, border),
      Expanded(
        child: Consumer<WorkoutPlanProvider>(
          builder: (context, provider, child) {
            if (provider.plans.isEmpty) {
              return _buildEmptyState(context, provider, accent);
            }
            return _buildPlanSection(context, provider, accent);
          },
        ),
      ),
      // NEW PLAN button OUTSIDE Consumer to avoid unnecessary rebuilds
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _buildNewPlanButton(context, accent),
      ),
    ],
  ),
),
```

Also add the `_buildPlanSection` method (replaces `_buildPlanGrid`):

```dart
Widget _buildPlanSection(
    BuildContext context, WorkoutPlanProvider provider, Color accent) {
  return GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.85,
    ),
    itemCount: provider.plans.length,
    itemBuilder: (context, index) =>
        _buildPlanCard(context, provider.plans[index], index, accent),
  );
}
```

**Method renamed from `_buildPlanGrid` to `_buildPlanSection`.**

Also add the import needed for Phase 3f:
```
import '../data/plan_colors.dart';
```

### 3f. Long-Press: Add "CHANGE COLOR" Option

In `_showPlanOptions`, add a new action before the existing ones:

```dart
_buildActionButton(
  label: '[COLOR] Change plan color',
  onTap: () {
    Navigator.pop(ctx);
    _showColorPickerDialog(context, plan, index, accent);
  },
  accent: accent,
),
```

Add `_showColorPickerDialog` method:

```dart
void _showColorPickerDialog(
    BuildContext context, WorkoutPlan plan, int planIndex, Color accent) {
  int? selectedColor = plan.planColor;
  final surface = surfaceColor(context);
  final border = borderColor(context);
  final textSecondary = textSecondaryColor(context);

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: border, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '> ${plan.name} — COLOR',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SELECT PLAN COLOR',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kPlanColors.map((colorValue) {
                      final color = Color(colorValue);
                      final isSelected = selectedColor == colorValue;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() => selectedColor = colorValue);
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            border: Border.all(
                              color: isSelected ? accent : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? Icon(Icons.check, size: 18,
                                  color: color.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(color: textSecondary)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final updated = WorkoutPlan(
                            name: plan.name,
                            exercises: plan.exercises,
                            planColor: selectedColor,
                          );
                          context.read<WorkoutPlanProvider>().updatePlan(planIndex, updated);
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        child: Text('[SAVE]', style: GoogleFonts.jetBrainsMono()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
```

### 3g. Card Aspect Ratio

The card needs more vertical space for exercise previews. Change `childAspectRatio` from `1.2` to `0.85`.

---

## Phase 4: Create Plan Screen Redesign

**File**: `lib/screens/create_plan_screen.dart`

### 4a. Remove AppBar — Add Inline Header

```dart
// At top of build method, before the body Column:
Widget _buildHeader(Color accent) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: borderColor(context))),
    ),
    child: Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          child: Icon(Icons.chevron_left, color: accent),
        ),
        const SizedBox(width: 8),
        Text(
          '> CREATE PLAN',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: accent,
            letterSpacing: 0.08,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: _savePlan,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              '[SAVE]',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: accent,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
```

### 4b. Plan Name Input

```dart
Widget _buildPlanNameInput(Color accent) {
  return Container(
    decoration: BoxDecoration(
      color: surfaceColor(context),
      border: Border.all(color: borderColor(context)),
    ),
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            '>',
            style: GoogleFonts.jetBrainsMono(fontSize: 13, color: accent),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'e.g. PUSH DAY',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              letterSpacing: 0.04,
              color: textPrimaryColor(context),
            ),
          ),
        ),
      ],
    ),
  );
}
```

### 4c. Color Picker

```dart
Widget _buildColorPicker(Color accent) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'PLAN COLOR',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          color: textSecondaryColor(context),
          letterSpacing: 0.08,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: kPlanColors.map((colorValue) {
          final color = Color(colorValue);
          final isSelected = _selectedColor == colorValue;
          return GestureDetector(
            onTap: () => setState(() => _selectedColor = colorValue),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(
                  color: isSelected ? accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          );
        }).toList(),
      ),
    ],
  );
}
```

Add `int? _selectedColor = kPlanColors[0];` to state.

### 4d. Exercise Card with Stepper Controls

Replace `_buildExerciseCard` with expandable cards + steppers.

**Stepper widget** (inline helper or extracted):

```dart
Widget _buildStepper({
  required double value,
  required double min,
  required double step,
  required Color accent,
  required void Function(double) onChanged,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      InkWell(
        onTap: () => onChanged((value - step).clamp(min, 999)),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: surfaceColor(context),
            border: Border.all(color: borderColor(context)),
          ),
          child: Center(
            child: Text('−',
                style: TextStyle(fontSize: 16, color: textSecondaryColor(context))),
          ),
        ),
      ),
      Container(
        width: 38,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor(context),
          border: Border(
            top: BorderSide(color: borderColor(context)),
            bottom: BorderSide(color: borderColor(context)),
          ),
        ),
        child: Text(
          value == value.roundToDouble() ? '${value.toInt()}' : value.toString(),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            color: textPrimaryColor(context),
          ),
        ),
      ),
      InkWell(
        onTap: () => onChanged(value + step),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: surfaceColor(context),
            border: Border.all(color: borderColor(context)),
          ),
          child: Center(
            child: Text('+',
                style: TextStyle(fontSize: 16, color: accent)),
          ),
        ),
      ),
    ],
  );
}
```

**Expandable exercise card**:

```dart
Widget _buildExerciseCard(
    _ExerciseWithSets exercise, int exerciseIndex, Color accent) {
  return Container(
    decoration: BoxDecoration(
      color: surfaceColor(context),
      border: Border.all(color: borderColor(context)),
    ),
    child: Column(
      children: [
        // Exercise header (always visible)
        InkWell(
          onTap: () => setState(() => _expandedExercises[exerciseIndex] =
              !(_expandedExercises[exerciseIndex] ?? false)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Text(
                  '[${(exerciseIndex + 1).toString().padLeft(2, '0')}]',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: textSecondaryColor(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exercise.name,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: textPrimaryColor(context),
                      letterSpacing: 0.03,
                    ),
                  ),
                ),
                Text(
                  '${exercise.sets.length} SETS',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: textSecondaryColor(context),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() => _exercises.removeAt(exerciseIndex)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline, size: 14, color: textSecondaryColor(context)),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  (_expandedExercises[exerciseIndex] ?? false)
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: textSecondaryColor(context),
                ),
              ],
            ),
          ),
        ),
        // Expanded sets area
        if (_expandedExercises[exerciseIndex] ?? false) ...[
          // Column headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: backgroundColor(context)),
            child: Row(
              children: [
                SizedBox(width: 52,
                    child: Text('SET', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: textSecondaryColor(context)))),
                Expanded(child: Text('REPS', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: textSecondaryColor(context)))),
                Expanded(child: Text('KG', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: textSecondaryColor(context)))),
                const SizedBox(width: 28),
              ],
            ),
          ),
          // Set rows
          ...exercise.sets.asMap().entries.map((entry) {
            final si = entry.key;
            final set = entry.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor(context))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      (si + 1).toString().padLeft(2, '0'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: textSecondaryColor(context).withAlpha(128),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildStepper(
                      value: set.reps.toDouble(),
                      min: 1,
                      step: 1,
                      accent: accent,
                      onChanged: (v) => _updateSet(exerciseIndex, si, v.toInt(), set.weight),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStepper(
                      value: set.weight,
                      min: 0,
                      step: 2.5,
                      accent: accent,
                      onChanged: (v) => _updateSet(exerciseIndex, si, set.reps, v),
                    ),
                  ),
                  if (exercise.sets.length > 1)
                    InkWell(
                      onTap: () => _deleteSet(exerciseIndex, si),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 12, color: textSecondaryColor(context)),
                      ),
                    )
                  else
                    const SizedBox(width: 28),
                ],
              ),
            );
          }),
          // Add set button
          InkWell(
            onTap: () => _addSetToExercise(exerciseIndex),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor(context))),
              ),
              child: Center(
                child: Text(
                  '+ ADD SET',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    letterSpacing: 0.08,
                    color: accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
```

Add `Map<int, bool> _expandedExercises = {};` to state. Initialize as empty — all cards start collapsed.

Add `_addSetToExercise` method:
```dart
void _addSetToExercise(int exerciseIndex) {
  setState(() {
    final exercise = _exercises[exerciseIndex];
    final lastSet = exercise.sets.isNotEmpty ? exercise.sets.last : _ExerciseSetData(reps: 8, weight: 0);
    final newSets = List<_ExerciseSetData>.from(exercise.sets);
    newSets.add(_ExerciseSetData(reps: lastSet.reps, weight: lastSet.weight));
    _exercises[exerciseIndex] = exercise.copyWith(sets: newSets);
  });
}
```

### 4e. Add Exercise — Bottom Sheet

Replace the `_addExercise()` dialog with:

```dart
void _showAddExerciseSheet() {
  String selectedCategory = ExerciseLibrary.categoryNames.first;
  String? justAdded;

  showModalBottomSheet(
    context: context,
    backgroundColor: surfaceColor(context),  // was hardcoded 0xFF111111
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final exercises = ExerciseLibrary.exercisesByCategory[selectedCategory] ?? [];
          final onAccent = accent.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: borderColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '> ADD EXERCISE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: textPrimaryColor(context),
                          letterSpacing: 0.06,
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(ctx),
                        child: Icon(Icons.close, size: 16, color: textSecondaryColor(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Category tabs
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: ExerciseLibrary.categoryNames.map((cat) {
                      final active = cat == selectedCategory;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setSheetState(() => selectedCategory = cat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: active ? accent : backgroundColor(context),  // was 0xFF1c1c1c
                              border: Border.all(
                                color: active ? accent : borderColor(context),
                              ),
                            ),
                            child: Text(
                              cat,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: active ? onAccent : textSecondaryColor(context),  // was Colors.black
                                letterSpacing: 0.06,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                // Exercise grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 3.5,
                    ),
                    itemCount: exercises.length,
                    itemBuilder: (ctx, i) {
                      final name = exercises[i];
                      final isJust = justAdded == name;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _exercises.add(_ExerciseWithSets(
                              name: name,
                              sets: List.generate(3, (_) => _ExerciseSetData(reps: 8, weight: 0)),
                            ));
                          });
                          setSheetState(() => justAdded = name);
                          Future.delayed(const Duration(milliseconds: 600), () {
                            if (ctx.mounted) Navigator.pop(ctx);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isJust ? accent.withAlpha(32) : backgroundColor(context),  // was 0xFF141414
                            border: Border.all(
                              color: isJust ? accent : borderColor(context),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isJust ? accent : textPrimaryColor(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isJust)
                                Icon(Icons.check, size: 12, color: accent),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
```

### 4f. Body Layout

Restructure the `build` method:

```dart
@override
Widget build(BuildContext context) {
  final accent = context.watch<SettingsProvider>().accentColor;

  return Scaffold(
    backgroundColor: backgroundColor(context),
    body: Column(
      children: [
        _buildHeader(accent),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlanNameInput(accent),
                const SizedBox(height: 16),
                _buildColorPicker(accent),
                const SizedBox(height: 16),
                // Exercise list
                Expanded(
                  child: _exercises.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: _exercises.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildExerciseCard(_exercises[i], i, accent),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                _buildAddExerciseButton(accent),
                const SizedBox(height: 8),
                _buildSaveButton(accent),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
```

### 4g. Empty State

```dart
Widget _buildEmptyState() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '// NO EXERCISES ADDED',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: textSecondaryColor(context).withAlpha(96),
            letterSpacing: 0.06,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '// TAP [+ ADD EXERCISE] BELOW',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: textSecondaryColor(context).withAlpha(96),
            letterSpacing: 0.06,
          ),
        ),
      ],
    ),
  );
}
```

### 4h. Add Exercise & Save Buttons

```dart
Widget _buildAddExerciseButton(Color accent) {
  return InkWell(
    onTap: _showAddExerciseSheet,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border.all(color: accent.withAlpha(64)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add, size: 12, color: accent),
          const SizedBox(width: 8),
          Text(
            '[+ ADD EXERCISE]',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              letterSpacing: 0.1,
              color: accent,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSaveButton(Color accent) {
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _savePlan,
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      child: Text(
        '[SAVE PLAN]',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.1,
        ),
      ),
    ),
  );
}
```

### 4i. Update `_savePlan` Method

Pass `_selectedColor` when creating the `WorkoutPlan`:

```dart
final plan = WorkoutPlan(
  name: _nameController.text.trim(),
  exercises: exercises,
  planColor: _selectedColor,
);
```

---

## Phase 5: Edit Plan Screen Redesign

**File**: `lib/screens/edit_plan_screen.dart`

Apply the same visual patterns as the Create Plan screen (Phases 4a-4h) to Edit Plan.

### Step 5a: Add Private Helper Classes

Add `_ExerciseSetData` and `_ExerciseWithSets` classes (identical to create_plan_screen.dart):

```dart
class _ExerciseSetData {
  final int reps;
  final double weight;
  _ExerciseSetData({required this.reps, required this.weight});
  _ExerciseSetData copyWith({int? reps, double? weight}) =>
      _ExerciseSetData(reps: reps ?? this.reps, weight: weight ?? this.weight);
}

class _ExerciseWithSets {
  final String name;
  final List<_ExerciseSetData> sets;
  _ExerciseWithSets({required this.name, required this.sets});
  _ExerciseWithSets copyWith({String? name, List<_ExerciseSetData>? sets}) =>
      _ExerciseWithSets(name: name ?? this.name, sets: sets ?? this.sets);
}
```

### Step 5b: Update State Variables

```dart
class _EditPlanScreenState extends State<EditPlanScreen> {
  late TextEditingController _nameController;
  late List<_ExerciseWithSets> _exercises;
  Map<int, bool> _expandedExercises = {};
  int? _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan.name);
    _selectedColor = widget.plan.planColor;

    // Convert ExerciseTemplates to _ExerciseWithSets (3 default sets each)
    final plans = HiveService.getPlans();
    final freshPlan =
        plans.length > widget.planIndex ? plans[widget.planIndex] : null;

    _exercises = freshPlan?.exercises
            .map((e) => _ExerciseWithSets(
                  name: e.name,
                  sets: List.generate(
                    e.sets,
                    (_) => _ExerciseSetData(reps: 8, weight: 0),
                  ),
                ))
            .toList() ??
        [];
  }
```

### Step 5c: Build Method

Same structure as CreatePlanScreen — no AppBar, inline header:

```dart
@override
Widget build(BuildContext context) {
  final accent = context.watch<SettingsProvider>().accentColor;

  return Scaffold(
    backgroundColor: backgroundColor(context),
    body: Column(
      children: [
        _buildHeader(accent),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlanNameInput(accent),
                const SizedBox(height: 16),
                _buildColorPicker(accent),
                const SizedBox(height: 16),
                Expanded(
                  child: _exercises.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: _exercises.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildExerciseCard(_exercises[i], i, accent),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                _buildAddExerciseButton(accent),
                const SizedBox(height: 8),
                _buildSaveButton(accent),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildHeader(Color accent) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: borderColor(context))),
    ),
    child: Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          child: Icon(Icons.chevron_left, color: accent),
        ),
        const SizedBox(width: 8),
        Text(
          '> EDIT PLAN',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: accent,
            letterSpacing: 0.08,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: _savePlan,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              '[SAVE]',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: accent,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
```

### Step 5d: Widget Methods

Copy these methods identically from CreatePlanScreen:

- `_buildPlanNameInput` — from Phase 4b
- `_buildColorPicker` — from Phase 4c (pre-fills via `_selectedColor`)
- `_buildStepper` — from Phase 4d
- `_buildExerciseCard` — from Phase 4d (expandable, with steppers)
- `_buildAddExerciseButton` — from Phase 4h
- `_buildSaveButton` — from Phase 4h
- `_buildEmptyState` — from Phase 4g
- `_showAddExerciseSheet` — from Phase 4e (fixed version)

### Step 5e: `_savePlan` Method

Convert `_ExerciseWithSets` back to `ExerciseTemplate` and include color:

```dart
void _savePlan() {
  if (_nameController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('> Plan name cannot be empty',
            style: GoogleFonts.jetBrainsMono()),
        backgroundColor: errorColor(context),
      ),
    );
    return;
  }

  if (_exercises.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('> Add at least one exercise',
            style: GoogleFonts.jetBrainsMono()),
        backgroundColor: errorColor(context),
      ),
    );
    return;
  }

  final exercises = _exercises
      .map((e) => ExerciseTemplate(
            name: e.name,
            sets: e.sets.length,
          ))
      .toList();

  final plan = WorkoutPlan(
    name: _nameController.text.trim(),
    exercises: exercises,
    planColor: _selectedColor,
  );
  context.read<WorkoutPlanProvider>().updatePlan(widget.planIndex, plan);
  Navigator.pop(context);
}
```

### Step 5f: Set Row Helper Methods

Copy from CreatePlanScreen:
- `_updateSet` — updates reps/weight for a specific set
- `_deleteSet` — removes a set (with guard for last set)
- `_addSetToExercise` — adds a new set copying the last set's values
- `_duplicateSet` — copies an existing set (if needed)

---

## Phase 6: Update main.dart + StatsScreen + SettingsScreen for Bottom Nav

### 6a. Remove Back Buttons from StatsScreen & SettingsScreen

Both screens currently have a `leading: IconButton(onPressed: () => Navigator.pop(context))` that becomes broken when accessed via bottom nav (no route to pop).

**In `lib/screens/stats_screen.dart`** — Around line 56-58:
Replace:
```dart
leading: IconButton(
  icon: Icon(Icons.arrow_back, color: accent),
  onPressed: () => Navigator.pop(context),
),
```
with:
```dart
automaticallyImplyLeading: false,
```

**In `lib/screens/settings_screen.dart`** — Around line 45-48:
Same change:
```dart
automaticallyImplyLeading: false,
```

### 6b. Create AppShell Wrapper

**New file** (or inline in `main.dart`):

```dart
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'widgets/app_bottom_nav.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    HistoryScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}
```

### 6c. Update main.dart

In `lib/main.dart`, replace:
```dart
home: const HomeScreen(),
```
with:
```dart
home: const AppShell(),
```

Add the import at top:
```dart
import 'app_shell.dart';  // or wherever AppShell is defined
```

**Note**: `IndexedStack` preserves state across tab switches (scroll position, loaded data, etc.). The memory cost of keeping 4 `IndexedStack` children alive is negligible for this app's data size.

---

## Verification

After each phase:

```bash
flutter analyze
```

Must pass with 0 errors before moving to next phase. After Hive model changes (Phase 1):

```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
```

---

## Rollback

If something goes wrong:

```bash
git checkout -- .
```

Restores all files to pre-redesign state.
