# OpenGym Project Documentation

## Project Overview
OpenGym is a clean, focused gym tracker built with Flutter. It helps people
create workout plans, log sets, reps, weight, RPE, and notes, then use history,
personal records, and charts to understand their progress. The app works
offline first and supports account-based sync across devices.

The product is designed for a broad gym audience. Its visual identity comes
from clear hierarchy, calm surfaces, restrained color, and small recognizable
details. The `> OpenGym` wordmark remains the core brand signature. Broad
terminal styling, bracketed actions, and technical-insider language are no
longer part of the direction. See `DESIGN.md` for the current product and visual
principles.

## Architecture
- **State Management**: Provider pattern with ChangeNotifier
- **Database/Storage**: Hive (local NoSQL database with Flutter adapter)
- **Key Dependencies**:
  - `provider: ^6.1.1` - State management
  - `hive: ^2.2.3` - Local database
  - `hive_flutter: ^1.1.0` - Hive Flutter integration
  - `shared_preferences: ^2.2.2` - App settings persistence
  - `fl_chart: ^0.66.0` - Charts for statistics
  - `google_fonts: ^6.0.0` - Custom fonts

## Project Structure

| File/Folder | Description |
|-------------|-------------|
| `lib/main.dart` | App entry point, initializes Hive, sets up providers and MaterialApp theme |
| `lib/models/` | Hive data models with adapters |
| `lib/providers/` | State management classes using Provider pattern |
| `lib/repositories/` | Repository layer (WorkoutPlanRepository, WorkoutSessionRepository, StatsRepository) |
| `lib/screens/` | UI screens/pages |
| `lib/services/` | Business logic services (HiveService, PRTrackingService, SampleDataSeeder) |
| `lib/data/exercise_library.dart` | Pre-defined exercise database by category |

## Models

### Set (typeId: 0)
Represents a single set with weight, reps, and optional RPE/note.
- `int reps` - Number of repetitions
- `double weight` - Weight lifted in kg
- `int? rpe` - Rate of Perceived Exertion (1-10)
- `String? note` - Optional note for the set

### Exercise (typeId: 1)
Represents an exercise within a workout session.
- `String name` - Exercise name
- `List<Set> sets` - List of sets performed
- `String? note` - Optional note for the exercise

### ExerciseTemplate (typeId: 2)
Represents an exercise template in a workout plan.
- `String name` - Exercise name
- `int sets` - Target number of sets

### WorkoutPlan (typeId: 3)
A workout plan containing multiple exercises.
- `String name` - Plan name (e.g., "Push Day")
- `List<ExerciseTemplate> exercises` - List of exercises in the plan

### WorkoutSession (typeId: 4)
A completed or in-progress workout session.
- `DateTime date` - When the workout occurred
- `String planName` - Name of the plan this session follows
- `List<Exercise> exercises` - Exercises performed with actual sets
- `int weekNumber` - Week number in the program

## Services

### HiveService
Central service for all Hive database operations. Exposes:
- **Plan Operations**: `getPlans()`, `addPlan()`, `updatePlan()`, `deletePlan()`
- **Session Operations**: `getSessions()`, `addSession()`, `deleteSession()`, `updateSession()`
- **Query Methods**: `getSessionsForPlan()`, `getWeeksForPlan()`, `getSessionForPlanAndWeek()`
- **Statistics**: `getExercisePR()`, `getAllExerciseNames()`, `getAllExercisePRs()`, `getExerciseProgression()`, `getWorkoutsThisWeek()`, `getWorkoutFrequency()`
- **Utilities**: `clearAllPlans()`, `clearAllSessions()`, `renameSessionWeek()`, `deleteSessionForPlanAndWeek()`

### Repositories
Repository layer wrapping HiveService for clean architecture:
- **WorkoutPlanRepository** - Wraps plan CRUD: `getPlans()`, `addPlan()`, `updatePlan()`, `deletePlan()`
- **WorkoutSessionRepository** - Wraps session CRUD + queries: `getSessions()`, `addSession()`, `deleteSession()`, `updateSession()`, `getSessionsForPlan()`, `getWeeksForPlan()`, `getSessionForPlanAndWeek()`, `getLastSessionForExercise()`
- **StatsRepository** - Wraps statistics methods: `getExercisePR()`, `getAllExerciseNames()`, `getAllExercisePRs()`, `getExerciseProgression()`, `getWorkoutsThisWeek()`, `getWorkoutFrequency()`

### Other Services
- `PRTrackingService` - Checks for new personal records
- `SampleDataSeeder` - Loads sample workout plans and sessions for testing

## Providers

| Provider | Manages |
|----------|---------|
| `WorkoutPlanProvider` | List of workout plans (CRUD operations) |
| `WorkoutSessionProvider` | Workout sessions, current session state, week tracking |
| `ProgressionProvider` | Exercise progression suggestions based on previous performance |
| `SettingsProvider` | Theme mode, accent color, weight unit, auto-fill settings |

## Screens

| Screen | Description |
|--------|-------------|
| `HomeScreen` | Main screen showing workout plans list, quick access to start workout |
| `PlanEditorScreen` | Create (`.create()`) or edit (`.edit(plan)`) a plan: exercises, per-set targets, reorder, plan color |
| `WorkoutScreen` | Active workout session with sets/reps/weight logging, week tabs |
| `HistoryScreen` | View past workout sessions |
| `StatsScreen` | Charts and statistics (PRs, workout frequency, progression) |
| `SettingsScreen` | App settings (theme, colors, weight unit, data management) |

## Developer Rules
- Always read opencode.md at the start of every session
- Always run `flutter analyze` after every file change
- Fix all errors (not warnings) before moving to the next task
- Update opencode.md with any significant changes (new features, bug fixes, refactoring)
- Commit and push changes to git after each task completion
- If Hive models change, run:
  ```
  flutter pub run build_runner build --delete-conflicting-outputs
  ```
  then re-run `flutter analyze`
- Never change the overall architecture or Provider setup
- Hot reload works for UI changes
- Full restart required after Hive model changes
- Always work one task at a time, confirm it compiles before continuing

## Known Issues
- None reported yet

## Recent Changes
- Compacted set entry across workout, plan, and history editing: 44px visual
  fields retain 48px tap areas, previous results use larger text, and workout
  cards use a plus icon with an accessible Add set label. Logged set details
  now open in a compact bottom sheet with Kg/Reps, RPE, notes, inline validation,
  and separate Delete/Cancel/Save actions; drafts only persist on Save.
- Polished set entry across workout and plan editing:
  - Replaced bracketed terminal labels with clear sentence-case controls and
    improved sans-serif typography for headers, previous results, and inputs
  - Matched Kg and Reps field sizing, surfaced RPE as a colored `@value`, and
    removed redundant New PR copy from exercise rows and dialogs
  - Kept exercise card spacing symmetrical while preserving the shared custom
    number keyboard and aligned four-column layout
- Refined the Home header hierarchy:
  - Reduced the active split from the page-title role to the compact secondary
    title role and scaled its chevron to match
  - Tightened vertical spacing and capped long split names sooner so the
    `> OpenGym` wordmark remains the clear visual anchor
- Added the first visual-identity foundation milestone:
  - Centralized a Manrope interface type scale and kept JetBrains Mono behind a
    training-data helper for aligned numerical values
  - Added shared primary, secondary, text, destructive, and accessible icon
    action components; retired the dashboard's bracket-decorated button
  - Consolidated the exact `> OpenGym` wordmark across startup, login, the Home
    header, and desktop navigation
  - Updated bottom and side navigation labels to sentence case while preserving
    destinations, responsive switching, touch targets, and selected semantics
  - Verified the login surface visually in light and dark themes and expanded
    typography, button, wordmark, navigation, and contrast coverage
- Modernized the complete split interface without changing split behavior:
  - Replaced the Home header's outlined split control with a larger plain-text
    split name and chevron
  - Removed terminal prefixes, brackets, forced uppercase, and monospaced type
    from split menus, dialogs, actions, statuses, and feedback
  - Preserved switching, validation, split limits, rename/delete safeguards,
    accessibility semantics, reduced motion, and responsive behavior
- Refreshed the app identity in project documentation:
  - Positioned OpenGym as a simple, clean, and capable gym tracker for a broad
    audience
  - Replaced the terminal motif with a quiet visual direction built around
    clarity, restrained color, and focused training data
  - Preserved the `> OpenGym` wordmark as the app's main visual signature
  - Updated contributor guidance so future UI work uses familiar labels and
    approachable interaction patterns
- Added the Stage B data foundation for split-scoped workspaces:
  - `Split` (Hive typeId 6) and account-wide `SplitPreference` (typeId 7) are cached locally and synchronized with Supabase
  - Plans and sessions carry `splitId`; legacy local records are backed up and assigned to the deterministic `My Split` after authentication
  - Sync pulls split metadata first, pushes active parent splits before plans/sessions, pushes preferences before deleted splits, and retains tombstones
  - Plan/session providers reload when the active split changes; stats, PRs, progression, history lookups, and active workouts are split-scoped
  - Backup format v3 includes every split and the active selection; v1/v2 imports are upgraded into `My Split`
  - Clear-all preserves split profiles, while sample data replaces data only in the active split and links sessions to their sample plans
- Unified set entry across Workout, Create/Edit Plan, and history editing:
  - Replaced weight/reps steppers with aligned Set / Prev / Kg / Reps columns in `SetEntryTable`
  - Added an in-app keypad with decimal weights (two decimal places), digit deletion, nonnegative ±2.5 kg adjustments, Next/Done navigation, and Close/back dismissal
  - The active field is highlighted; the focused set and its previous result stay above the keypad
  - Workout Prev uses the latest earlier occurrence in the same plan and split; plan editing can consult exercise history across plans within its split. Missing results display a dash, and targets remain separately labeled hints
  - Workout edits update the draft immediately and autosave on keypad dismissal, so PR dialogs cannot interrupt digit entry
  - Preserved set notes, colored RPE annotations, and delete actions through set details; set detail dialogs share the same numeric input
  - Added keypad, responsive layout, history lookup, plan persistence, and workout autosave regression coverage
- Changed first-run appearance defaults to light mode with the cyan accent while preserving existing users' saved choices
- Reduced plan-color noise with identity markers:
  - Home cards now use a compact colored rail beside the plan name instead of a full-width stripe and colored statistics
  - Workout titles return to the theme's primary text color and carry the same compact plan marker
  - Home's create-plan action and the workout's add-exercise action use the same theme-aware surface as exercise cards
  - Added widget coverage for marker colors, neutral title treatment, and responsive card layout
- Improved the plan editor's add-exercise sheet:
  - Exercise rows now toggle between add and remove, so a selection can be undone before closing the sheet
  - Replaced the cramped two-column grid with full-width rows, a live selected count, clearer action labels, stronger typography, and a more legible search/category layout
  - Added a widget regression test for selecting and unselecting an exercise
- Added per-set plan targets:
  - New `SetTemplate` model (typeId: 5) holding prescribed `reps`/`weight`
  - `ExerciseTemplate.setTargets` is optional and read through `targetAt(index)`, so pre-existing plans need no migration
  - Targets are display-only: a session is never seeded from them, or `PRTrackingService` would report PRs for weights nobody lifted
  - The workout screen's set row hints at the target beside the live value until the set is touched, matching the plan entry by exercise name (not index)
- Replaced duplicated create/edit plan screens with one `PlanEditorScreen`:
  - Create and edit flows now share the same UI and persistence path
  - Per-set plan targets save through `ExerciseTemplate.setTargets`
  - Add-exercise sheet supports search, multi-add, and duplicate prevention
  - Obsolete `create_plan_screen.dart`, `edit_plan_screen.dart`, and `exercise_with_sets.dart` were removed
- Rebuilt the plan editor's exercise card to the workout screen's spec:
  - `setValueStyle`, `setUnitStyle` and `StepperBox` moved into `set_row.dart` and are now shared by both screens; `SetHeaderRow` takes a `trailingGap`
  - Set values lead the row at 17/bold with quiet steppers beside them, and tapping a value opens `WorkoutDialogs.showEditPlanSetDialog` to type it
  - Collapsed cards state their own prescription, so a plan reads without expanding every card
  - Add-set and delete moved to a card footer; delete now goes through `showDeleteExerciseDialog` instead of removing an exercise silently
- Fixed online sync startup race:
  - Concurrent `SyncService.syncNow()` calls now share the active sync future instead of returning early
  - Post-login adoption waits for in-flight pull data before providers reload
  - Verified local web push, pull, offline drain, RLS, LWW, tombstone, and no duplicate session row checks against Supabase
- Updated workout screen exercise interactions:
  - Tapping an exercise name now opens the rename dialog.
  - Long-press drag remains reserved for exercise reordering.
  - Displayed RPE values are color-coded by exertion level.
- Updated workout screen header:
  - Moved active plan name into the AppBar beside the back button
  - Removed the leading `>` from the plan title
  - Colored the title using each plan's custom `planColor`
  - Disabled Material 3 AppBar scrolled-under tint/elevation on the workout screen
  - Resolved active plan by `plan.key` instead of fragile index, with safe fallbacks

## Recent Changes (Previous)
- Fixed light mode: Replaced legacy theme constants with theme-aware functions across all screens and widgets:
  - screen files: create_plan_screen, edit_plan_screen, history_screen, settings_screen  
  - widget files: workout/exercise_card, workout/workout_dialogs
  - Mapped the old surface, border, secondary text, error, and background constants to their theme-aware equivalents
  - All screens now respect light/dark theme setting
- Fixed week tab navbar scroll position: Added ScrollController to jump to selected week on initial load (WidgetsBinding.instance.addPostFrameCallback in initState)
- Fixed gesture conflicts in workout_screen.dart:
  - Week swipe: Implemented early directional claiming with angle-based disambiguation (abs(dx)/abs(dy) > 1.5 for horizontal, abs(dy)/abs(dx) > 1.0 for vertical) once movement > 10px
  - Swipe triggers only when horizontal claimed AND total dx > 40px at onEnd
  - Created _ExposingHorizontalDragGestureRecognizer subclass to expose protected resolve() method
  - Plan swipe: Moved plan name from AppBar to body as _PlanHeader widget with its own GestureDetector
- Removed `targetReps` and `targetSets` from ExerciseTemplate, replaced with single `sets` field
- Added auto-generation of empty sets when starting a session from a plan
- Added "+" button in workout screen to add new exercises during session
- Added duplicate set button in create_plan_screen
- Fixed edit_plan_screen exercises not loading issue
- Added "Load Sample Data" button that clears and refreshes sample data

## Repository Layer Refactoring
- Added `lib/repositories/` folder with three repository classes:
  - `WorkoutPlanRepository` - wraps plan CRUD operations
  - `WorkoutSessionRepository` - wraps session CRUD + query methods
  - `StatsRepository` - wraps statistics methods
- Updated providers and services to use repositories instead of calling HiveService directly:
  - `WorkoutPlanProvider` → uses `WorkoutPlanRepository`
  - `WorkoutSessionProvider` → uses `WorkoutSessionRepository`
  - `ProgressionProvider` → uses `WorkoutSessionRepository`
  - `stats_screen.dart` → uses `StatsRepository` + `WorkoutSessionRepository`
  - `PRTrackingService` → uses `StatsRepository`
- `flutter analyze` passes with no errors

## Priority 2 Refactoring
- Split workout_screen.dart (1739→704 lines) into separate widget files:
  - lib/widgets/workout/arrow_button.dart
  - lib/widgets/workout/set_row.dart
  - lib/widgets/workout/exercise_card.dart
  - lib/widgets/workout/workout_dialogs.dart
- All dialogs extracted as static methods in WorkoutDialogs class
- `flutter analyze` passes with no errors

## UI Quality Pass (Latest)
- Added active/pressed states (splashColor + highlightColor) to all InkWell interactive elements
- Increased text readability: minimum 8px → 10px, chart labels 10px → 11px
- Fixed workout screen: reduced week navbar height (48→40px), increased action button spacing
- Enhanced settings screen color picker with checkmark indicator for selected color
- Fixed spacing and visual feedback across all screens
- `flutter analyze` passes with no errors (only info-level const warnings)

## Export/Import (Backup) Feature
- Added JSON-based export/import for backing up and restoring all gym data
- **Models**: Added `toJson()`/`factory fromJson()` to all 5 model classes (Set, Exercise, ExerciseTemplate, WorkoutPlan, WorkoutSession)
- **BackupService** (`lib/services/backup_service.dart`): Static utility for serialization (exportData) and parse/validate (importData) with version checking
- **HiveService**: Added `replaceAllPlans()` and `replaceAllSessions()` for batch atomic data replacement
- **SettingsScreen**: Added EXPORT DATA (non-destructive dialog → share sheet) and IMPORT DATA (file picker → validate → destructive confirmation → write) tiles
- **Dependencies added**: `file_picker`, `share_plus`
- **Web support**: Export uses `XFile.fromData()` (no `path_provider`); import handles `PlatformFile.bytes` for web
- **`flutter analyze` passes with 0 errors**
