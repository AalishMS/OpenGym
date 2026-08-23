# AGENTS.md - OpenGym Development Guide

This file provides guidance for AI agents working on the OpenGym Flutter project.

## Project Overview

- **Type**: Flutter mobile app (gym tracking)
- **State Management**: Provider with ChangeNotifier
- **Local Storage**: Hive (NoSQL)
- **Architecture**: Clean separation - models, providers, services, screens, widgets, theme

---

## Build & Development Commands

### Running the App
```bash
flutter run                           # Run on connected device
flutter run -d <device_id>           # Run on specific device
flutter build apk --release           # Build Android APK
flutter build apk --debug             # Build debug APK
```

### Analysis & Linting
```bash
flutter analyze                       # Run static analysis (required after every change)
flutter analyze --no-fatal-warnings  # Run but don't fail on warnings
```

### Testing
```bash
flutter test                          # Run all tests
flutter test test/widget_test.dart    # Run single test file
flutter test --name="Basic"           # Run tests matching name pattern
flutter test test/widget_test.dart --name="Basic widget test"
```

### Code Generation (Hive Models)
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```
**Required** whenever Hive model files (.dart) are modified. Run `flutter analyze` after.

### Releasing

The app self-updates from GitHub Releases, so a release is only installable if
the version is bumped correctly.

```bash
# 1. Bump BOTH parts, then stage pubspec.yaml explicitly
# 2. Tag must equal the pubspec version exactly, with a leading v
git add pubspec.yaml && git commit -m "chore: release 1.0.2+3"
git tag v1.0.2+3 && git push && git push --tags
```

- **Always increment the `+build` number**, never just the version name. It
  becomes the Android `versionCode`, it is what `UpdateService.isNewer`
  compares, and Android refuses to install an APK whose versionCode is not
  greater than the installed one. `1.0.2+2` after `1.0.1+2` builds and
  publishes fine but no phone can install it
- The build number must strictly increase across *all* releases - it is never
  reset when the version name changes
- The tag must match `version:` in pubspec character for character, `+build`
  included. `.github/workflows/release.yml` fails the build on a mismatch or a
  missing build number, but it cannot detect a reused one
- Never `git commit -am` here - it sweeps the generated plugin registrants'
  line-ending churn into the release commit (see Common Issues)
- Every APK must be signed with the same keystore (`android/key.properties`,
  git-ignored; CI writes it from repository secrets). A key change strands
  every installed copy, and the workflow refuses to publish a debug-signed APK
- One universal APK, never `--split-per-abi`: the updater picks the first
  `.apk` asset it finds, so multiple assets could hand out the wrong ABI
- The release must not be a draft or prerelease - the `/releases/latest`
  endpoint the app polls skips both


---

## Code Style Guidelines

### General Principles
- Fix all analyzer errors before committing/moving on
- Warnings are acceptable but should be minimized
- Always run `flutter analyze` after making changes

### Imports
```dart
// Order: dart: packages, pub packages, local imports
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/workout_plan.dart';
import '../services/hive_service.dart';
```
- Use relative imports for local files
- Group imports by type with blank lines between groups

### Naming Conventions
- **Files**: snake_case (e.g., `workout_plan.dart`, `workout_screen.dart`)
- **Classes**: PascalCase (e.g., `WorkoutPlan`, `WorkoutScreen`)
- **Methods/Variables**: camelCase (e.g., `loadPlans()`, `_plans`)
- **Constants**: camelCase with k prefix (e.g., `kDefaultReps`)
- **Private members**: prefix with underscore (e.g., `_plans`)

### Types
- Use explicit types for class fields and return types
- Use `final` by default, `var` only when mutation needed
- Use `double` for weights, `int` for reps/sets

### Widgets
- Use `const` constructors where possible
- Extract widgets into separate files in `lib/widgets/workout/` subdirectory
- Use terminal-style UI with JetBrains Mono font (`GoogleFonts.jetBrainsMono()`)

### Bracket Labels
Actionable text wears square brackets - it is the app's button vocabulary.
One rule, no exceptions:

- `[LABEL]` - no padding inside the brackets, and the label is uppercase:
  `[SAVE]`, `[CANCEL]`, `[LOAD SAMPLE DATA]`. Never `[ SAVE ]`
- `[+ LABEL]` - a leading glyph binds to the opening bracket, one space
  before the label: `[+ NEW PLAN]`, `[+ ADD SET]`. Never `[ + ADD SET ]`
- `[+]` - a bare glyph when the target is too small for words
- `[01]` - zero-padded index pills, on cards and tabs
- Passing a label to a wrapper that adds the brackets itself (`BracketButton`)
  means passing `'RESUME'`, not `' RESUME '`

Reach for `[DEL]` over `[DELETE]` only where the row is genuinely too tight
for the full word - the abbreviation is a space decision, not a style.

### Theme & Colors
- Use theme-aware color functions from `app_theme.dart`:
  - `backgroundColor(context)` - main background
  - `surfaceColor(context)` - card/surface background
  - `borderColor(context)` - borders
  - `textPrimaryColor(context)` - main text
  - `textSecondaryColor(context)` - secondary text
  - `accentColor(context)` - accent color from settings
  - `onAccentColor(context)` - text/icons drawn *on* the accent
  - `onColor(ground)` - text/icons drawn on any other coloured ground
- Never hardcode colors like `Colors.white` or `Colors.black` for UI
- Anything drawn on a coloured ground asks for its foreground:
  - accent ground (filled button, selected chip/tab, accent snackbar) →
    `onAccentColor(context)`
  - any other coloured ground (a plan's colour, `errorColor(context)`, an RPE
    swatch, a palette chip) → `onColor(thatGround)`
  - `onColor` is the single place in the app allowed to name black or white;
    a literal `Colors.black` foreground is a bug waiting for a dark accent
  - exception: alpha-only `ShaderMask` stops under `BlendMode.dstIn`, where
    black/white mean opaque/transparent rather than a colour — comment those
- Use `accent.withAlpha(value)` for splash/highlight effects

### Corner Radii
- Use the tokens from `lib/theme/radii.dart`, never a literal `BorderRadius`:
  - `AppRadius.card` - cards, panels, dialogs, bordered content boxes
  - `AppRadius.button` / `.field` - buttons, full-width tap targets, inputs
  - `AppRadius.chip` / `.control` - pills, tabs, steppers, small selectables
  - `AppRadius.badge` - index pills, swatches, anything under ~24px
  - `AppRadius.micro` - heatmap cells, drag handles, chart bar caps
  - `AppRadius.sheet` / `.cardTop` / `.cardBottom` / `.leftCap` / `.rightCap` -
    partial rounding for sheets, card headers/footers, joined segments
- Never leave a full-perimeter `BoxDecoration` (one with `Border.all`) unrounded
- Single-edge `Border(top:/bottom:/left:/right:)` decorations are hairline rules,
  not boxes - leave them square
- Any `InkWell` wrapping a rounded box needs the same token on its own
  `borderRadius:`, or the splash squares off the corner on press

### Error Handling
- Use try-catch for async operations
- Show user-friendly SnackBar messages for errors
- Log errors appropriately

---

## Key Files & Structure

```
lib/
├── main.dart                    # App entry point
├── models/                      # Hive models (set.dart, exercise.dart, etc.)
│   └── *.g.dart               # Generated adapters (do not edit)
├── providers/                  # State management (ChangeNotifier)
├── services/                   # Business logic (HiveService, PRTrackingService)
├── screens/                    # UI screens
├── widgets/                    # Reusable widgets
│   └── workout/               # Workout screen sub-widgets
├── theme/                      # Theme configuration
├── data/                       # Static data (exercise_library.dart)
└── utils/                      # Utilities (fade_page_route.dart)
```

---

## Provider Pattern

Providers extend `ChangeNotifier` and use `notifyListeners()`:
```dart
class MyProvider with ChangeNotifier {
  List<MyModel> _items = [];

  List<MyModel> get items => _items;

  void loadItems() {
    _items = HiveService.getItems();
    notifyListeners();
  }
}
```

Access in widgets:
```dart
final provider = context.watch<MyProvider>();
final items = context.read<MyProvider>().items;
```

---

## Hive Models

Models use annotations and generate adapters:
```dart
@HiveType(typeId: 0)
class MyModel extends HiveObject {
  @HiveField(0)
  final String field;

  MyModel({required this.field});
}
```

**Important**: After modifying models, regenerate adapters and analyze.

---

## Workflow Rules

1. Read `opencode.md` at session start
2. Run `flutter analyze` after every file change
3. Fix all errors before proceeding
4. Work one task at a time, verify compile before continuing
5. Full restart required after Hive model changes (not just hot reload)
6. Commit changes after task completion

---

## Common Issues

- **Gesture conflicts**: Use angle-based disambiguation for horizontal vs vertical swipe
- **Week tab scroll**: Use `ScrollController` with `addPostFrameCallback` for initial position
- **Model changes**: Always run `build_runner` then `flutter analyze`
- **Generated plugin registrants**: the five files under `linux/flutter/`,
  `macos/Flutter/`, and `windows/flutter/` re-dirty themselves with
  whitespace-only (LF vs CRLF) diffs on every `pub get`, `analyze`, or build.
  They abort `git pull` and break `git stash pop`. Confirm the diff is empty
  under `git diff --ignore-all-space --stat`, then
  `git checkout -- linux/ macos/ windows/` and continue - Flutter regenerates
  them on the next build. Stage files explicitly rather than using
  `git commit -am`, and don't use `git stash` to get a clean analyzer baseline
