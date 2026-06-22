# Gym Tracker - Project Documentation

## Project Overview
A mobile gym tracking app built with Flutter that allows users to create workout plans, log exercises with sets/reps/weight, track personal records, and view workout statistics. Designed for gym-goers who want to track their training progress over time.

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
| `CreatePlanScreen` | Form to create new workout plans with exercises and sets |
| `EditPlanScreen` | Edit existing workout plans |
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
- Fixed light mode: Replaced hardcoded terminalX constants with theme-aware functions across ALL screens and widgets:
  - screen files: create_plan_screen, edit_plan_screen, history_screen, settings_screen  
  - widget files: workout/exercise_card, workout/workout_dialogs
  - Replaced: terminalSurface→surfaceColor, terminalBorder→borderColor, terminalTextSecondary→textSecondaryColor, terminalError→errorColor, terminalBackground→backgroundColor
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
