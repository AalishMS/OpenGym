# Workout Screen Header Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move the active workout plan name into the top AppBar beside the back button, remove the leading `>` prefix, color the title with the plan's custom color, and prevent the AppBar/header color from changing while scrolling.

**Architecture:** Keep the change localized to `lib/screens/workout_screen.dart`. Use `WorkoutPlanProvider` as the source of truth for the current plan so title color updates when plan data changes. Avoid model, Hive adapter, repository, or theme-wide changes.

**Tech Stack:** Flutter, Provider, Hive-backed `WorkoutPlan`, Material `AppBar`, existing theme helpers from `app_theme.dart`.

---

## Task 1: Resolve the Active Plan Safely

**Files:**
- Modify: `lib/screens/workout_screen.dart`

**Problem:**
Using `plans[widget.planIndex]` can throw `RangeError` if the plan list shrinks while the workout screen is open. It can also point to the wrong plan if indexes shift due to insertions or deletions.

**Implementation:**
Inside `build()`, read the provider once:

```dart
final planProvider = context.watch<WorkoutPlanProvider>();
final plans = planProvider.plans;
```

Resolve the active plan with a safe fallback chain:

```dart
final activePlan = plans.firstWhere(
  plan.key == widget.plan.key,
  orElse: () {
    if (widget.planIndex >= 0 && widget.planIndex < plans.length) {
      return plans[widget.planIndex];
    }
    return widget.plan;
  },
);
```

Resolve the active plan color:

```dart
final planColor =
    activePlan.planColor != null ? Color(activePlan.planColor!) : accent;
```

**Step 1:** Add the `planProvider` and `activePlan` variables inside `build()` after the existing color variable declarations.

**Step 2:** Run `flutter analyze` to verify no errors.

---

## Task 2: Move the Plan Name Into the AppBar

**Files:**
- Modify: `lib/screens/workout_screen.dart`

Replace the existing AppBar with one that includes the plan title:

```dart
appBar: AppBar(
  backgroundColor: surface,
  elevation: 0,
  scrolledUnderElevation: 0,
  surfaceTintColor: Colors.transparent,
  shadowColor: Colors.transparent,
  toolbarHeight: 60,
  leading: IconButton(
    icon: Icon(Icons.arrow_back, color: accent),
    onPressed: () {
      _autoSave();
      Navigator.pop(context);
    },
  ),
  title: _PlanHeader(
    planName: activePlan.name,
    planIndex: widget.planIndex,
    planColor: planColor,
  ),
  bottom: _buildPlanTabBar(accent, plans, activePlan),
),
```

**Step 1:** Replace the existing `appBar:` section in `build()`.

**Step 2:** Run `flutter analyze` to verify no errors.

---

## Task 3: Remove the Body-Level Plan Header

**Files:**
- Modify: `lib/screens/workout_screen.dart`

Delete the `_PlanHeader` widget call from the body `Column`:

```dart
// REMOVE this entire block:
_PlanHeader(
  planName: widget.plan.name,
  planIndex: widget.planIndex,
  accent: accent,
),
```

The body should start with:

```dart
body: Column(
  children: [
    Expanded(
      child: _GestureClaimingContainer(
        ...
      ),
    ),
    _buildWeekNavBar(),
  ],
),
```

**Step 1:** Remove the `_PlanHeader` call from the body children.

**Step 2:** Run `flutter analyze` to verify no errors.

---

## Task 4: Remove the `>` Prefix From the Plan Name

**Files:**
- Modify: `lib/screens/workout_screen.dart`

In `_PlanHeader.build()`, change the text from:

```dart
'> ${planName.toUpperCase()}'
```

to:

```dart
planName.toUpperCase()
```

Do NOT change `'> Auto-saving...'` in `_buildWeekNavBar` — that is a different, unrelated element.

**Step 1:** Edit the text string in `_PlanHeader`.

**Step 2:** Run `flutter analyze` to verify.

---

## Task 5: Update `_PlanHeader` for AppBar Layout

**Files:**
- Modify: `lib/screens/workout_screen.dart`

**Step 1: Update field and constructor:**

Replace existing `accent` field with `planColor`:

```dart
final String planName;
final int planIndex;
final Color planColor;

const _PlanHeader({
  required this.planName,
  required this.planIndex,
  required this.planColor,
});
```

**Step 2: Update `build()` layout:**

Replace the container with a plain `Text` inside the `GestureDetector`:

```dart
@override
Widget build(BuildContext context) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragEnd: (details) {
      final provider = context.read<WorkoutPlanProvider>();
      final plans = provider.plans;
      if (details.primaryVelocity != null) {
        if (details.primaryVelocity!.abs() > 250) {
          if (details.primaryVelocity! < 0) {
            if (planIndex < plans.length - 1) {
              Navigator.pushReplacement(
                context,
                FadePageRoute(
                  page: WorkoutScreen(
                    plan: plans[planIndex + 1],
                    planIndex: planIndex + 1,
                  ),
                ),
              );
            }
          } else {
            if (planIndex > 0) {
              Navigator.pushReplacement(
                context,
                FadePageRoute(
                  page: WorkoutScreen(
                    plan: plans[planIndex - 1],
                    planIndex: planIndex - 1,
                  ),
                ),
              );
            }
          }
        }
      }
    },
    child: Text(
      planName.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: planColor,
      ),
    ),
  );
}
```

Remove the following from the old `_PlanHeader`:
- `width: double.infinity`
- `padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)`
- `color: surfaceColor(context)`

**Step 3:** Run `flutter analyze` to verify.

---

## Task 6: Update `_buildPlanTabBar` Signature

**Files:**
- Modify: `lib/screens/workout_screen.dart`

**Step 1: Change method signature:**

From:

```dart
PreferredSizeWidget? _buildPlanTabBar(Color accent)
```

To:

```dart
PreferredSizeWidget? _buildPlanTabBar(
  Color accent,
  List<WorkoutPlan> plans,
  WorkoutPlan activePlan,
)
```

**Step 2: Remove internal provider watch:**

Delete these lines from inside `_buildPlanTabBar`:

```dart
final planProvider = context.watch<WorkoutPlanProvider>();
final plans = planProvider.plans;
```

**Step 3: Update selected-tab logic:**

From:

```dart
final isSelected = index == widget.planIndex;
```

To:

```dart
final isSelected = plan.key == activePlan.key || index == widget.planIndex;
```

**Step 4:** Run `flutter analyze` to verify.

---

## Task 7: Verification

**Step 1:** Run `flutter analyze`.

Expected: No new errors. Existing info-level const warnings are acceptable.

**Step 2:** Manual verification checklist:
- [ ] AppBar shows back button + plan name
- [ ] No separate body-level plan name row below plan slider
- [ ] No leading `>` before plan name
- [ ] Plan name color uses `WorkoutPlan.planColor` (or falls back to accent)
- [ ] Scrolling does not change AppBar/header color
- [ ] Swiping plan title horizontally switches plans
- [ ] Plan tab bar highlights correct tab based on plan key
- [ ] Opening a workout screen after editing plan color shows updated title color

---

## Task 8: Update opencode.md

**Files:**
- Modify: `opencode.md`

Add a recent changes entry:

```markdown
- Updated workout screen header:
  - Moved active plan name into the AppBar beside the back button
  - Removed the leading `>` from the plan title
  - Colored the title using each plan's custom `planColor`
  - Disabled Material 3 AppBar scrolled-under tint/elevation on the workout screen
  - Resolved active plan by `plan.key` instead of fragile index, with safe fallbacks
```

---

## Files to Change

- `lib/screens/workout_screen.dart`
- `opencode.md`

## Files Not to Change

- `lib/models/workout_plan.dart`
- `lib/models/workout_plan.g.dart`
- `lib/providers/workout_plan_provider.dart`
- `lib/theme/app_theme.dart`

## Commands

```bash
flutter analyze
```

No Hive model changes are required, so `build_runner` is not needed.
