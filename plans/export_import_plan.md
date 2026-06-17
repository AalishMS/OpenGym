# Export/Import (Backup) Feature

## Date: 2026-06-13

## Summary
Add JSON-based export and import functionality for backing up and restoring all gym data (workout plans, workout sessions, and settings). Export produces a `.json` file shared via the system share sheet. Import reads a `.json` file via the system file picker, validates it fully, then atomically replaces all local data.

## File Format
- **Extension**: `.json`
- **Default file name**: `gymapp_backup_YYYY-MM-DD.json` (generated from current date at export time)
- **Format**: JSON with a `version` field for forward compatibility

## Schema

```json
{
  "version": 1,
  "exportedAt": "2026-06-13T10:30:00.000",
  "settings": {
    "themeMode": 1,
    "accentIndex": 0,
    "weightUnit": "kg",
    "autoFillLast": true,
    "highRefreshRate": true
  },
  "workoutPlans": [
    {
      "name": "PPL",
      "exercises": [
        { "name": "Bench Press", "sets": 3 }
      ]
    }
  ],
  "workoutSessions": [
    {
      "date": "2026-06-10T10:00:00.000",
      "planName": "PPL",
      "weekNumber": 1,
      "exercises": [
        {
          "name": "Bench Press",
          "note": null,
          "sets": [
            { "reps": 10, "weight": 80.0, "rpe": null, "note": null }
          ]
        }
      ]
    }
  ]
}
```

## Implementation Steps

### 1. Add toJson/fromJson to Model Classes
Each model class in `lib/models/` gets two methods:

| Class | TypeId | Fields to serialize |
|---|---|---|
| `Set` | 0 | reps, weight, rpe, note |
| `Exercise` | 1 | name, sets (list of `Set`), note |
| `ExerciseTemplate` | 2 | name, sets (int) |
| `WorkoutPlan` | 3 | name, exercises (list of `ExerciseTemplate`) |
| `WorkoutSession` | 4 | date, planName, exercises (list of `Exercise`), weekNumber |

- `toJson()` returns a `Map<String, dynamic>` suitable for `jsonEncode`.
- `fromJson(Map<String, dynamic>)` is a `factory` constructor. It **must** handle `null` values for optional fields (rpe, note) gracefully.
- **ExerciseTemplate** stores only `sets` (int), not a list — this is the template used in plan definitions.
- **Exercise** stores `sets` (list of `Set` with rep/weight data) — this is the completed exercise in a session.

### 2. Add Dependencies to pubspec.yaml
- `file_picker: ^8.1.6` — opens the native OS file picker filtered to `.json` files
- `share_plus: ^10.1.4` — opens the system share sheet to send the exported file
- `path_provider: ^2.3.0` — provides temp directory path for writing the export file before sharing

### 3. Create BackupService (`lib/services/backup_service.dart`)

The service is a static utility class (no state).

#### `ExportResult exportData({required List<WorkoutPlan> plans, required List<WorkoutSession> sessions, required Map<String, dynamic> settings})`
- Serializes all data into the JSON schema above.
- Returns an `ExportResult`:
  ```dart
  class ExportResult {
    final String jsonString;
    final String fileName; // e.g. "gymapp_backup_2026-06-13.json"
  }
  ```

#### `ImportResult importData(String jsonString)`
- **Step 1 — Parse**: Attempt `jsonDecode`. If it throws, return `ImportResult.invalid('File is not valid JSON')`.
- **Step 2 — Validate schema**: Check for required top-level keys (`version`, `workoutPlans`, `workoutSessions`, `settings`). Verify `version` is `1`. If unknown version, return `ImportResult.versionMismatch(version)`.
- **Step 3 — Validate content**: Deserialize `workoutPlans` into `List<WorkoutPlan>` and `workoutSessions` into `List<WorkoutSession>` using their `fromJson` factories. If any item fails, return `ImportResult.invalid('Invalid plan or session data')`.
- **Step 4 — Return parsed data**: If everything passes, return `ImportResult.success(plans, sessions, settingsMap)`.

**The service does NOT write to Hive.** It only parses and validates. Writing is handled by the caller (SettingsScreen) after user confirmation.

```dart
class ImportResult {
  final bool success;
  final String? errorMessage;
  final int? version;
  final List<WorkoutPlan>? plans;
  final List<WorkoutSession>? sessions;
  final Map<String, dynamic>? settings;

  ImportResult._({required this.success, this.errorMessage, this.version, this.plans, this.sessions, this.settings});

  factory ImportResult.success(List<WorkoutPlan> plans, List<WorkoutSession> sessions, Map<String, dynamic> settingsMap) =>
      ImportResult._(success: true, plans: plans, sessions: sessions, settings: settingsMap);

  factory ImportResult.invalid(String message) =>
      ImportResult._(success: false, errorMessage: message);

  factory ImportResult.versionMismatch(int version) =>
      ImportResult._(success: false, errorMessage: 'Unsupported backup version: $version', version: version);
}
```

### 4. Add HiveService Methods (`lib/services/hive_service.dart`)

These methods must be transactional — all-or-nothing. Use clear-then-add within a single operation.

```dart
/// Clears all plans and inserts [plans] in a single batch.
static Future<void> replaceAllPlans(List<WorkoutPlan> plans) async {
  final box = Hive.box<WorkoutPlan>('workoutPlans');
  await box.clear();
  for (final plan in plans) {
    await box.add(plan);
  }
}

/// Same transactional semantics for sessions.
static Future<void> replaceAllSessions(List<WorkoutSession> sessions) async {
  final box = Hive.box<WorkoutSession>('workoutSessions');
  await box.clear();
  for (final session in sessions) {
    await box.add(session);
  }
}
```

**Implementation note**: Hive's `clear()` + looped `add()` is not truly atomic. To guarantee atomicity, either:
- Use `box.putAll()` with generated keys if IDs are known, or
- Accept the risk (Hive crashes are rare) and document that a failed import may leave data in a partial state. This plan recommends accepting the trade-off since validation occurs before any write begins.

### 5. Update SettingsScreen (`lib/screens/settings_screen.dart`)

#### 5a. Add imports
```dart
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/backup_service.dart';
```

#### 5b. Insert tiles in the DATA section

Both tiles go in the `Consumer<SettingsProvider>` builder's `children` list, **between** LOAD SAMPLE DATA and CLEAR ALL DATA:

```dart
_buildSettingsTile(
  icon: Icons.upload,
  title: 'EXPORT DATA',
  subtitle: 'Backup all plans, sessions, and settings',
  onTap: () => _exportData(context),
  accent: accent,
  textPrimary: textPrimary,
  textSecondary: textSecondary,
  border: border,
),
_buildSettingsTile(
  icon: Icons.download,
  title: 'IMPORT DATA',
  subtitle: 'Restore from a backup file (replaces all data)',
  onTap: () => _importData(context),
  accent: accent,
  textPrimary: textPrimary,
  textSecondary: textSecondary,
  border: border,
),
```

**Parameters explained**:
- `accent` → from `settings.accentColor` (in scope via `Consumer<SettingsProvider>`)
- `textPrimary`, `textSecondary` → from `textPrimaryColor(context)`, `textSecondaryColor(context)` (in scope)
- `border` → from `borderColor(context)` (in scope)
- No `isDestructive` or `error` — these tiles are neutral actions (the destructive nature is revealed in the dialog)
- Icons inherit `accent` color from `_buildSettingsTile`'s internal logic (`Icon(icon, color: accent)`)

#### 5c. Add `_exportData(BuildContext context)` method

```dart
void _exportData(BuildContext context) {
  final surface = surfaceColor(context);
  final border = borderColor(context);
  final textSecondary = textSecondaryColor(context);
  final settings = context.read<SettingsProvider>();
  final accent = settings.accentColor;

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
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
              '> EXPORT DATA?',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This will create a backup file containing all your plans, '
              'sessions, and settings. Your current data will NOT be affected.',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    '[CANCEL]',
                    style: GoogleFonts.jetBrainsMono(color: textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final planProvider = context.read<WorkoutPlanProvider>();
                      final sessionProvider = context.read<WorkoutSessionProvider>();
                      final result = BackupService.exportData(
                        plans: planProvider.plans,
                        sessions: sessionProvider.sessions,
                        settings: {
                          'themeMode': settings.themeMode,
                          'accentIndex': settings.accentIndex,
                          'weightUnit': settings.weightUnit,
                          'autoFillLast': settings.autoFillLast,
                          'highRefreshRate': settings.highRefreshRate,
                        },
                      );
                      final dir = await getTemporaryDirectory();
                      final file = File('${dir.path}/${result.fileName}');
                      await file.writeAsString(result.jsonString);
                      await Share.shareXFiles(
                        [XFile(file.path)],
                        text: 'OpenGym Backup',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '> Backup exported successfully',
                              style: GoogleFonts.jetBrainsMono(),
                            ),
                            backgroundColor: accent,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '> Export failed: ${e.toString()}',
                              style: GoogleFonts.jetBrainsMono(),
                            ),
                            backgroundColor: errorColor(context),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                  ),
                  child: Text('[EXPORT]', style: GoogleFonts.jetBrainsMono()),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
```

**Dialog pattern**: Non-destructive — accent-colored title and button (export does not modify data).

**Success SnackBar**: `backgroundColor: accent`.
**Error SnackBar**: `backgroundColor: errorColor(context)`.

#### 5d. Add `_importData(BuildContext context)` method

**Flow**:
1. Open file picker (`FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'])`)
2. If user cancels picker → do nothing
3. Read the file content as string
4. Call `BackupService.importData(jsonString)`
5. If `ImportResult` is not success → show error SnackBar and stop
6. If success → show destructive confirmation dialog (see below)
7. User confirms → write all data → reload providers → show success SnackBar

**Destructive confirmation dialog** (for step 6):

```dart
final surface = surfaceColor(context);
final border = borderColor(context);
final textSecondary = textSecondaryColor(context);
final error = errorColor(context);
final settings = context.read<SettingsProvider>();
final accent = settings.accentColor;

showDialog(
  context: context,
  builder: (ctx) => Dialog(
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
            '> IMPORT BACKUP?',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: error, // DESTRUCTIVE — red title
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This will REPLACE ALL of your current data including:\n'
            '• All workout plans\n'
            '• All workout history\n'
            '• App settings (theme, accent color, units)\n\n'
            'This action cannot be undone.',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '[CANCEL]',
                  style: GoogleFonts.jetBrainsMono(color: textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await HiveService.replaceAllPlans(result.plans!);
                    await HiveService.replaceAllSessions(result.sessions!);
                    final s = result.settings!;
                    settings.setThemeMode(s['themeMode'] as int);
                    settings.setAccentColor(s['accentIndex'] as int);
                    settings.setWeightUnit(s['weightUnit'] as String);
                    context.read<WorkoutPlanProvider>().loadPlans();
                    context.read<WorkoutSessionProvider>().loadSessions();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '> Backup imported successfully',
                            style: GoogleFonts.jetBrainsMono(),
                          ),
                          backgroundColor: accent,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '> Import failed: ${e.toString()}',
                            style: GoogleFonts.jetBrainsMono(),
                          ),
                          backgroundColor: error,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: error, // DESTRUCTIVE — red button
                  foregroundColor: Colors.white,
                ),
                child: Text('[IMPORT]', style: GoogleFonts.jetBrainsMono()),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
```

**Dialog pattern**: **Destructive** — `error`-colored title, `error`-colored button, warning text lists exactly what gets replaced (including settings).

**Success SnackBar**: `backgroundColor: accent`.
**Error SnackBar**: `backgroundColor: errorColor(context)`.

## UI Design — Summary

| Element | Export | Import |
|---------|--------|--------|
| Settings tile icon | `Icons.upload` (accent) | `Icons.download` (accent) |
| Tile title | `'EXPORT DATA'` | `'IMPORT DATA'` |
| Tile subtitle | `'Backup all plans, sessions, and settings'` | `'Restore from a backup file (replaces all data)'` |
| Dialog title | `'> EXPORT DATA?'` (accent) | `'> IMPORT BACKUP?'` (error) |
| Dialog body | Explains data is safe | Warns all data + settings replaced, irreversible |
| Cancel button | `[CANCEL]` (textSecondary) | `[CANCEL]` (textSecondary) |
| Action button | `[EXPORT]` (accent bg, black text) | `[IMPORT]` (error bg, white text) |
| Success SnackBar | accent background | accent background |
| Error SnackBar | errorColor background | errorColor background |

## Data Flow

```
Export:
  Hive Boxes → BackupService.exportData() → JSON string → temp file → share_plus share sheet
                                                                       ↓
                                                  User emails/saves/AirDrops file to computer

Import:
  file_picker → read file → BackupService.importData() → parse & validate
      ↓ success                                   ↓ invalid
  Show destructive confirmation dialog      Show error SnackBar
      ↓ confirmed
  HiveService.replaceAllPlans() (batch)
  HiveService.replaceAllSessions() (batch)
  SettingsProvider.applySettings()
  WorkoutPlanProvider.loadPlans()
  WorkoutSessionProvider.loadSessions()
  Show success SnackBar
```

## Error Handling

| Scenario | Behavior | SnackBar color |
|----------|----------|----------------|
| Export serialization fails | Catch → SnackBar with error message | `errorColor(context)` |
| Export file write fails | Catch → SnackBar with error message | `errorColor(context)` |
| Share fails | Catch → SnackBar with error message | `errorColor(context)` |
| User cancels file picker | Silent — no action | N/A |
| File is not valid JSON | SnackBar: "Invalid backup file" | `errorColor(context)` |
| Version mismatch | SnackBar: "Unsupported backup version: X" | `errorColor(context)` |
| Plans/sessions fail validation | SnackBar: "Invalid backup file" | `errorColor(context)` |
| Import write to Hive fails | SnackBar with error details | `errorColor(context)` |
| Import succeeds | SnackBar: "Backup imported successfully" | `accent` |
| Export succeeds | SnackBar: "Backup exported successfully" | `accent` |

All SnackBars use the default shape from the theme's `snackBarTheme` (zero-radius, border-colored border, floating behavior) but override the `backgroundColor` as specified above.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Partial import if Hive write fails mid-way | Validation occurs before any write. Plans and sessions are written sequentially. If the app crashes during the write, data may be partially replaced — this is accepted as a rare edge case. |
| User accidentally imports wrong file | Destructive confirmation dialog explicitly warns: "This will REPLACE ALL of your current data." Import is a two-step process (pick → confirm). |
| Accent color/theme changes unexpectedly after import | Dialog body explicitly lists "App settings (theme, accent color, units)" as data that will be replaced. |
| Large backup file causes memory issues | JSON is read entirely into memory. For a gym tracking app this is negligible (typical backup < 1 MB). Acceptable. |
| User imports a file they edited by hand with invalid data | `fromJson` constructors validate structure. `BackupService.importData` catches parse errors and returns a descriptive error. |
