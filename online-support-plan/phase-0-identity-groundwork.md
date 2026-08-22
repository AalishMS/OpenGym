# Phase 0 — Identity groundwork (local only, no backend)

**Goal:** give every plan/session a stable UUID + sync metadata, convert the CRUD seam from
**index-based** to **id-based**, and fix the append-only session bug and the wrong-record
delete/edit bug. **After this phase the app must behave identically offline** — no backend yet.

**Risk:** this re-keys the local Hive database. Follow the safety rules in the README. A JSON
safety backup is written to `shared_preferences` before re-keying.

**Preconditions:** on a branch (`git switch -c feature/online-support`); app builds and
`flutter analyze` is clean before you start.

---

## Step 0.1 — Add the `uuid` dependency

Edit `pubspec.yaml`. In `dependencies:` (after `share_plus: ^10.1.4`) add:

```yaml
  uuid: ^4.3.0
```

Then:

```bash
flutter pub get
```

---

## Step 0.2 — Replace `lib/models/workout_plan.dart` (add id/meta + copyWith)

Overwrite the **entire file** with:

```dart
import 'package:hive/hive.dart';
import 'exercise_template.dart';

part 'workout_plan.g.dart';

@HiveType(typeId: 3)
class WorkoutPlan extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final List<ExerciseTemplate> exercises;

  @HiveField(2)
  final int? planColor;

  // --- Sync / identity metadata ---
  // All nullable so pre-existing on-disk records (written before these fields
  // existed) still deserialize. Non-final so the sync engine can flip
  // dirty/updatedAt/deletedAt in place and persist with box.put(id, obj).
  // NOTE: field index 3 is intentionally unused (harmless gap).
  @HiveField(4)
  String? id;

  @HiveField(5)
  String? userId;

  @HiveField(6)
  DateTime? updatedAt;

  @HiveField(7)
  DateTime? deletedAt;

  @HiveField(8)
  bool? dirty;

  WorkoutPlan({
    required this.name,
    required this.exercises,
    this.planColor,
    this.id,
    this.userId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
  });

  WorkoutPlan copyWith({
    String? name,
    List<ExerciseTemplate>? exercises,
    int? planColor,
    String? id,
    String? userId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? dirty,
  }) =>
      WorkoutPlan(
        name: name ?? this.name,
        exercises: exercises ?? this.exercises,
        planColor: planColor ?? this.planColor,
        id: id ?? this.id,
        userId: userId ?? this.userId,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        dirty: dirty ?? this.dirty,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'planColor': planColor,
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        id: json['id'] as String?,
        name: json['name'] as String,
        exercises: (json['exercises'] as List)
            .map((e) => ExerciseTemplate.fromJson(e as Map<String, dynamic>))
            .toList(),
        planColor: json['planColor'] as int?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        deletedAt: json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
      );
}
```

> Behavior note: `copyWith` uses `planColor ?? this.planColor`, so it cannot *clear* a color back to
> null. The app never offers "no color" (colors come from a fixed palette), so this is acceptable.

---

## Step 0.3 — Replace `lib/models/workout_session.dart` (add id/meta, extend copyWith)

Overwrite the **entire file** with:

```dart
import 'package:hive/hive.dart';
import 'exercise.dart';

part 'workout_session.g.dart';

@HiveType(typeId: 4)
class WorkoutSession extends HiveObject {
  @HiveField(0)
  final DateTime date;

  @HiveField(1)
  final String planName;

  @HiveField(2)
  final List<Exercise> exercises;

  @HiveField(3)
  final int weekNumber;

  // --- Sync / identity metadata (nullable + non-final; see WorkoutPlan) ---
  @HiveField(4)
  String? id;

  @HiveField(5)
  String? userId;

  @HiveField(6)
  String? planId;

  @HiveField(7)
  DateTime? updatedAt;

  @HiveField(8)
  DateTime? deletedAt;

  @HiveField(9)
  bool? dirty;

  WorkoutSession({
    required this.date,
    required this.planName,
    required this.exercises,
    this.weekNumber = 1,
    this.id,
    this.userId,
    this.planId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'planName': planName,
        'planId': planId,
        'weekNumber': weekNumber,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        id: json['id'] as String?,
        date: DateTime.parse(json['date'] as String),
        planName: json['planName'] as String,
        planId: json['planId'] as String?,
        weekNumber: json['weekNumber'] as int? ?? 1,
        exercises: (json['exercises'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        deletedAt: json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
      );

  WorkoutSession copyWith({
    DateTime? date,
    String? planName,
    List<Exercise>? exercises,
    int? weekNumber,
    String? id,
    String? userId,
    String? planId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? dirty,
  }) {
    return WorkoutSession(
      date: date ?? this.date,
      planName: planName ?? this.planName,
      exercises: exercises ?? this.exercises,
      weekNumber: weekNumber ?? this.weekNumber,
      id: id ?? this.id,
      userId: userId ?? this.userId,
      planId: planId ?? this.planId,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
    );
  }
}
```

---

## Step 0.4 — Regenerate Hive adapters

```bash
dart run build_runner build --delete-conflicting-outputs
```

**Verify the regenerated files changed correctly** (do not edit them by hand unless build_runner is
unavailable):

- `lib/models/workout_plan.g.dart` — the `write` method's first line should now be
  `writer..writeByte(6)` (was `3`) — because 6 fields are now serialized (0,1,2,4,6,7 — plus 5,8;
  count reflects the number of `writeByte(index)..write(value)` pairs the generator emits). The
  exact count depends on the generator; what matters is it **increased** and the `read` map now
  handles the new indices as nullable.
- `lib/models/workout_session.g.dart` — same idea, byte count increased for the new fields.

> If build_runner is unavailable in your environment, STOP and get it run — hand-editing generated
> adapters is error-prone. It is a normal `dev_dependency` already in `pubspec.yaml`
> (`hive_generator`, `build_runner`).

---

## Step 0.5 — Replace `lib/services/hive_service.dart` (keyed boxes + upsert + tombstones + migration)

Overwrite the **entire file** with:

```dart
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise_template.dart';
import '../models/exercise.dart';
import '../models/set.dart';

class HiveService {
  static const String plansBox = 'workout_plans';
  static const String sessionsBox = 'workout_sessions';
  static const _uuid = Uuid();
  static const String _migrationFlag = 'idkey_migration_v1_done';

  static Future<void> init() async {
    await Hive.initFlutter();

    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());

    await Hive.openBox<WorkoutPlan>(plansBox);
    await Hive.openBox<WorkoutSession>(sessionsBox);

    await _migrateToIdKeys();
  }

  static Box<WorkoutPlan> get _plansBox => Hive.box<WorkoutPlan>(plansBox);
  static Box<WorkoutSession> get _sessionsBox =>
      Hive.box<WorkoutSession>(sessionsBox);

  // ---------------------------------------------------------------------------
  // ONE-SHOT MIGRATION: int-keyed (box.add) -> id-keyed (box.put(id)) records,
  // backfill sync metadata, backfill session.planId from planName. Runs once,
  // guarded by a shared_preferences flag. Writes a JSON safety backup first.
  // ---------------------------------------------------------------------------
  static Future<void> _migrateToIdKeys() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationFlag) == true) return;

    try {
      final now = DateTime.now();

      // Safety backup (recovery net) BEFORE we clear/re-key anything.
      final plansBackup = _plansBox.values.map((p) => p.toJson()).toList();
      final sessionsBackup = _sessionsBox.values.map((s) => s.toJson()).toList();
      await prefs.setString('idkey_backup_plans', jsonEncode(plansBackup));
      await prefs.setString('idkey_backup_sessions', jsonEncode(sessionsBackup));

      // Plans: assign ids/meta, then re-key by id (iteration order preserved).
      final planValues = _plansBox.values.toList();
      final plansById = <String, WorkoutPlan>{};
      for (final p in planValues) {
        p.id ??= _uuid.v4();
        p.updatedAt ??= now;
        p.dirty = true;
        plansById[p.id!] = p;
      }
      await _plansBox.clear();
      await _plansBox.putAll(plansById);

      final planIdByName = <String, String>{
        for (final p in plansById.values) p.name.toLowerCase(): p.id!,
      };

      // Sessions: assign ids/meta, backfill planId, then re-key by id.
      final sessionValues = _sessionsBox.values.toList();
      final sessionsById = <String, WorkoutSession>{};
      for (final s in sessionValues) {
        s.id ??= _uuid.v4();
        s.updatedAt ??= now;
        s.dirty = true;
        s.planId ??= planIdByName[s.planName.toLowerCase()];
        sessionsById[s.id!] = s;
      }
      await _sessionsBox.clear();
      await _sessionsBox.putAll(sessionsById);

      await prefs.setBool(_migrationFlag, true);
      // ignore: avoid_print
      print('id-key migration OK: '
          '${plansById.length} plans, ${sessionsById.length} sessions.');
    } catch (e) {
      // Leave existing data intact; flag stays false so it retries next launch.
      // ignore: avoid_print
      print('id-key migration FAILED (will retry next launch): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Plan operations (id-based)
  // ---------------------------------------------------------------------------
  /// UI-facing list: tombstones (deletedAt != null) are hidden.
  static List<WorkoutPlan> getPlans() =>
      _plansBox.values.where((p) => p.deletedAt == null).toList();

  /// Returns a plan by id INCLUDING tombstones (get-by-key ignores deletedAt).
  static WorkoutPlan? getPlanById(String id) => _plansBox.get(id);

  static Future<void> addPlan(WorkoutPlan plan) => upsertPlan(plan);

  static Future<void> upsertPlan(WorkoutPlan plan) async {
    plan.id ??= _uuid.v4();
    plan.updatedAt = DateTime.now();
    plan.dirty = true;
    await _plansBox.put(plan.id, plan);
  }

  static Future<void> softDeletePlan(String id) async {
    final plan = _plansBox.get(id);
    if (plan == null) return;
    final now = DateTime.now();
    plan.deletedAt = now;
    plan.updatedAt = now;
    plan.dirty = true;
    await _plansBox.put(id, plan);
  }

  // ---------------------------------------------------------------------------
  // Session operations (id-based)
  // ---------------------------------------------------------------------------
  /// UI-facing list: tombstones hidden, sorted newest-first (unchanged order).
  static List<WorkoutSession> getSessions() =>
      _sessionsBox.values.where((s) => s.deletedAt == null).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  static WorkoutSession? getSessionById(String id) => _sessionsBox.get(id);

  static Future<void> addSession(WorkoutSession session) =>
      upsertSession(session);

  static Future<void> upsertSession(WorkoutSession session) async {
    session.id ??= _uuid.v4();
    session.updatedAt = DateTime.now();
    session.dirty = true;
    await _sessionsBox.put(session.id, session);
  }

  static Future<void> softDeleteSession(String id) async {
    final s = _sessionsBox.get(id);
    if (s == null) return;
    final now = DateTime.now();
    s.deletedAt = now;
    s.updatedAt = now;
    s.dirty = true;
    await _sessionsBox.put(id, s);
  }

  // ---------------------------------------------------------------------------
  // Analytics / name-based helpers — UNCHANGED logic (all read via getSessions
  // which now filters tombstones). Signatures preserved.
  // ---------------------------------------------------------------------------
  static WorkoutSession? getLastSessionForExercise(String exerciseName) {
    final sessions = getSessions();
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
          return session;
        }
      }
    }
    return null;
  }

  static Exercise? getLastExerciseData(String exerciseName) {
    final session = getLastSessionForExercise(exerciseName);
    if (session == null) return null;
    for (var exercise in session.exercises) {
      if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
        return exercise;
      }
    }
    return null;
  }

  static List<WorkoutSession> getSessionsForPlan(String planName) {
    return getSessions()
        .where((s) => s.planName.toLowerCase() == planName.toLowerCase())
        .toList();
  }

  static List<int> getWeeksForPlan(String planName) {
    final sessions = getSessionsForPlan(planName);
    final weeks = sessions.map((s) => s.weekNumber).toSet().toList();
    weeks.sort();
    return weeks;
  }

  static WorkoutSession? getSessionForPlanAndWeek(
      String planName, int weekNumber) {
    final sessions = getSessionsForPlan(planName);
    for (var session in sessions) {
      if (session.weekNumber == weekNumber) {
        return session;
      }
    }
    return null;
  }

  static Set? getLastSetForExercise(String exerciseName) {
    final exercise = getLastExerciseData(exerciseName);
    if (exercise == null || exercise.sets.isEmpty) return null;
    return exercise.sets.last;
  }

  static double getExercisePR(String exerciseName) {
    final sessions = getSessions();
    double maxWeight = 0;
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
          for (var set in exercise.sets) {
            if (set.weight > maxWeight) {
              maxWeight = set.weight;
            }
          }
        }
      }
    }
    return maxWeight;
  }

  static List<String> getAllExerciseNames() {
    final sessions = getSessions();
    final names = <String>{};
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        names.add(exercise.name);
      }
    }
    return names.toList()..sort();
  }

  static Map<String, double> getAllExercisePRs() {
    final names = getAllExerciseNames();
    final prs = <String, double>{};
    for (var name in names) {
      prs[name] = getExercisePR(name);
    }
    return prs;
  }

  static List<Map<String, dynamic>> getExerciseProgression(
      String exerciseName) {
    final sessions = getSessions();
    final progression = <Map<String, dynamic>>[];

    for (var session in sessions) {
      for (var exercise in session.exercises) {
        if (exercise.name.toLowerCase() == exerciseName.toLowerCase() &&
            exercise.sets.isNotEmpty) {
          double maxWeight = 0;
          int totalVolume = 0;
          for (var set in exercise.sets) {
            if (set.weight > maxWeight) maxWeight = set.weight;
            totalVolume += (set.weight * set.reps).round();
          }
          progression.add({
            'date': session.date,
            'maxWeight': maxWeight,
            'totalVolume': totalVolume,
            'week': session.weekNumber,
          });
        }
      }
    }
    progression.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return progression;
  }

  static int getWorkoutsThisWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startDate =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    return getSessions().where((s) => s.date.isAfter(startDate)).length;
  }

  static Map<int, int> getWorkoutFrequency(int weeksBack) {
    final frequency = <int, int>{};
    final now = DateTime.now();

    for (int i = 0; i < weeksBack; i++) {
      frequency[i] = 0;
    }

    for (var session in getSessions()) {
      final daysDiff = now.difference(session.date).inDays;
      final weekIndex = daysDiff ~/ 7;
      if (weekIndex < weeksBack) {
        frequency[weekIndex] = (frequency[weekIndex] ?? 0) + 1;
      }
    }

    return frequency;
  }

  // ---------------------------------------------------------------------------
  // Bulk / week helpers — now id-based.
  // ---------------------------------------------------------------------------
  static Future<void> renameSessionWeek(
      String planName, int oldWeek, int newWeek) async {
    final matches = getSessionsForPlan(planName)
        .where((s) => s.weekNumber == oldWeek)
        .toList();
    for (final s in matches) {
      await upsertSession(s.copyWith(weekNumber: newWeek)); // same id -> replace
    }
  }

  static Future<void> deleteSessionForPlanAndWeek(
      String planName, int weekNumber) async {
    final matches = _sessionsBox.values
        .where((s) =>
            s.deletedAt == null &&
            s.planName.toLowerCase() == planName.toLowerCase() &&
            s.weekNumber == weekNumber)
        .toList();
    for (final s in matches) {
      await softDeleteSession(s.id!);
    }
  }

  static Future<void> clearAllPlans() async {
    await _plansBox.clear();
  }

  static Future<void> clearAllSessions() async {
    await _sessionsBox.clear();
  }

  static Future<void> replaceAllPlans(List<WorkoutPlan> plans) async {
    await _plansBox.clear();
    final map = <String, WorkoutPlan>{};
    for (final p in plans) {
      p.id ??= _uuid.v4();
      p.updatedAt = DateTime.now();
      p.dirty = true;
      map[p.id!] = p;
    }
    await _plansBox.putAll(map);
  }

  static Future<void> replaceAllSessions(List<WorkoutSession> sessions) async {
    await _sessionsBox.clear();
    final map = <String, WorkoutSession>{};
    for (final s in sessions) {
      s.id ??= _uuid.v4();
      s.updatedAt = DateTime.now();
      s.dirty = true;
      map[s.id!] = s;
    }
    await _sessionsBox.putAll(map);
  }
}
```

> `clearAllPlans`/`clearAllSessions` still hard-clear (used by "Clear all data" / import). Note for
> Phase 3: a local hard-clear does **not** create tombstones, so it won't propagate as deletes to
> the cloud — that's acceptable for a deliberate destructive reset; document it in the UI copy later.

---

## Step 0.6 — Replace the repositories

`lib/repositories/workout_plan_repository.dart` (overwrite entire file):

```dart
import '../models/workout_plan.dart';
import '../services/hive_service.dart';

class WorkoutPlanRepository {
  List<WorkoutPlan> getPlans() => HiveService.getPlans();

  WorkoutPlan? getPlanById(String id) => HiveService.getPlanById(id);

  Future<void> addPlan(WorkoutPlan plan) => HiveService.addPlan(plan);

  Future<void> upsertPlan(WorkoutPlan plan) => HiveService.upsertPlan(plan);

  Future<void> softDeletePlan(String id) => HiveService.softDeletePlan(id);
}
```

`lib/repositories/workout_session_repository.dart` (overwrite entire file):

```dart
import '../models/workout_session.dart';
import '../services/hive_service.dart';

class WorkoutSessionRepository {
  List<WorkoutSession> getSessions() => HiveService.getSessions();

  WorkoutSession? getSessionById(String id) => HiveService.getSessionById(id);

  Future<void> upsertSession(WorkoutSession session) =>
      HiveService.upsertSession(session);

  Future<void> softDeleteSession(String id) =>
      HiveService.softDeleteSession(id);

  List<WorkoutSession> getSessionsForPlan(String planName) =>
      HiveService.getSessionsForPlan(planName);

  List<int> getWeeksForPlan(String planName) =>
      HiveService.getWeeksForPlan(planName);

  WorkoutSession? getSessionForPlanAndWeek(String planName, int weekNumber) =>
      HiveService.getSessionForPlanAndWeek(planName, weekNumber);

  WorkoutSession? getLastSessionForExercise(String exerciseName) =>
      HiveService.getLastSessionForExercise(exerciseName);
}
```

---

## Step 0.7 — Replace the providers

`lib/providers/workout_plan_provider.dart` (overwrite entire file):

```dart
import 'package:flutter/foundation.dart';
import '../models/workout_plan.dart';
import '../repositories/workout_plan_repository.dart';

class WorkoutPlanProvider with ChangeNotifier {
  final WorkoutPlanRepository _repository = WorkoutPlanRepository();
  List<WorkoutPlan> _plans = [];

  List<WorkoutPlan> get plans => _plans;

  WorkoutPlanProvider() {
    loadPlans();
  }

  void loadPlans() {
    _plans = _repository.getPlans();
    notifyListeners();
  }

  Future<void> addPlan(WorkoutPlan plan) async {
    await _repository.addPlan(plan);
    loadPlans();
  }

  Future<void> updatePlan(WorkoutPlan plan) async {
    await _repository.upsertPlan(plan);
    loadPlans();
  }

  Future<void> deletePlan(String id) async {
    await _repository.softDeletePlan(id);
    loadPlans();
  }
}
```

`lib/providers/workout_session_provider.dart` (overwrite entire file):

```dart
import 'package:flutter/foundation.dart';
import '../models/workout_session.dart';
import '../models/exercise.dart';
import '../repositories/workout_session_repository.dart';

class WorkoutSessionProvider with ChangeNotifier {
  final WorkoutSessionRepository _repository = WorkoutSessionRepository();
  List<WorkoutSession> _sessions = [];
  WorkoutSession? _currentSession;
  int _currentWeek = 1;

  List<WorkoutSession> get sessions => _sessions;
  WorkoutSession? get currentSession => _currentSession;
  int get currentWeek => _currentWeek;

  WorkoutSessionProvider() {
    loadSessions();
  }

  void loadSessions() {
    _sessions = _repository.getSessions();
    notifyListeners();
  }

  void setCurrentWeek(int week) {
    _currentWeek = week;
    notifyListeners();
  }

  /// Upsert-by-id. This is the core fix for the append-only bug: repeated
  /// autosaves of the same (plan, week) session replace ONE row instead of
  /// appending new ones. The session carries its own stable id.
  Future<void> upsertSession(WorkoutSession session) async {
    await _repository.upsertSession(session);
    loadSessions();
  }

  /// Kept for API symmetry with the History edit screen.
  Future<void> updateSession(WorkoutSession session) async {
    await _repository.upsertSession(session);
    loadSessions();
  }

  Future<void> deleteSession(String id) async {
    await _repository.softDeleteSession(id);
    loadSessions();
  }

  List<int> getWeeksForPlan(String planName) =>
      _repository.getWeeksForPlan(planName);

  WorkoutSession? getSessionForPlanAndWeek(String planName, int week) =>
      _repository.getSessionForPlanAndWeek(planName, week);
}
```

> The old `startWorkout` / `saveWorkout` append path is removed; `workout_screen.dart` is switched
> to `upsertSession` in Step 0.10. If any other file references `startWorkout`/`saveWorkout`,
> `flutter analyze` will flag it — fix those call-sites to use `upsertSession`.

---

## Step 0.8 — `home_screen.dart` call-sites (2 edits)

**Edit A — delete plan (around line 366).** REPLACE:

```dart
                  context.read<WorkoutPlanProvider>().deletePlan(index);
```

with:

```dart
                  context.read<WorkoutPlanProvider>().deletePlan(plan.id!);
```

**Edit B — color picker save (around lines 466–471).** REPLACE:

```dart
                          onPressed: () {
                            final updated = WorkoutPlan(
                              name: plan.name,
                              exercises: plan.exercises,
                              planColor: selectedColor,
                            );
                            context.read<WorkoutPlanProvider>().updatePlan(planIndex, updated);
                            Navigator.pop(ctx);
                          },
```

with:

```dart
                          onPressed: () {
                            final updated = plan.copyWith(planColor: selectedColor);
                            context.read<WorkoutPlanProvider>().updatePlan(updated);
                            Navigator.pop(ctx);
                          },
```

> The "Duplicate plan" flow (around lines 326–334) builds a `WorkoutPlan` with **no** `id`, so
> `addPlan` → `upsertPlan` assigns a fresh id automatically. **Leave it as-is.**
> `_showColorPickerDialog`'s `planIndex` parameter is now unused; you may leave it or remove it —
> `flutter analyze` will only warn if it's an unused local, not an unused parameter.

---

## Step 0.9 — `edit_plan_screen.dart` call-sites (2 edits)

**Edit A — load the fresh plan by id (around lines 45–47).** REPLACE:

```dart
    final plans = HiveService.getPlans();
    final freshPlan =
        plans.length > widget.planIndex ? plans[widget.planIndex] : null;
```

with:

```dart
    final freshPlan = widget.plan.id != null
        ? HiveService.getPlanById(widget.plan.id!)
        : widget.plan;
```

**Edit B — save carries the existing id (around lines 428–433).** REPLACE:

```dart
    final plan = WorkoutPlan(
      name: _nameController.text.trim(),
      exercises: exercises,
      planColor: _selectedColor,
    );
    context.read<WorkoutPlanProvider>().updatePlan(widget.planIndex, plan);
```

with:

```dart
    final plan = WorkoutPlan(
      id: widget.plan.id,
      name: _nameController.text.trim(),
      exercises: exercises,
      planColor: _selectedColor,
    );
    context.read<WorkoutPlanProvider>().updatePlan(plan);
```

> `widget.planIndex` may now be unused in this screen. That's fine (unused field, not an error). If
> you prefer, remove the `planIndex` parameter from `EditPlanScreen` and update its call-site in
> `home_screen.dart` (`EditPlanScreen(plan: plan, planIndex: index)` → `EditPlanScreen(plan: plan)`).
> Optional cleanup — not required for correctness.

---

## Step 0.10 — `workout_screen.dart` (append-bug fix + id matching)

**Edit A — `_autoSave` (around lines 118–136).** This removes the append path and upserts one
row per (plan, week), stamping identity. REPLACE:

```dart
  Future<void> _autoSave() async {
    final session = _getOrCreateSession();
    final hasSets = session.exercises.any((e) => e.sets.isNotEmpty);

    if (hasSets) {
      final prs = PRTrackingService.checkForNewPRs(session.exercises);

      context.read<WorkoutSessionProvider>().startWorkout(
            session.planName,
            session.exercises,
            weekNumber: _currentWeek,
          );
      await context.read<WorkoutSessionProvider>().saveWorkout();

      if (prs.isNotEmpty && mounted) {
        _showPRDialog(prs);
      }
    }
  }
```

with:

```dart
  Future<void> _autoSave() async {
    var session = _getOrCreateSession();
    final hasSets = session.exercises.any((e) => e.sets.isNotEmpty);

    if (hasSets) {
      final prs = PRTrackingService.checkForNewPRs(session.exercises);

      // Stamp identity so repeated autosaves upsert ONE row per (plan, week).
      // upsertSession assigns a UUID on first save and reuses it thereafter.
      session = session.copyWith(
        planId: widget.plan.id,
        planName: widget.plan.name,
        weekNumber: _currentWeek,
      );
      _weekSessions[_currentWeek] = session; // keep the id-stamped instance
      await context.read<WorkoutSessionProvider>().upsertSession(session);

      if (prs.isNotEmpty && mounted) {
        _showPRDialog(prs);
      }
    }
  }
```

> Why this yields a stable id without extra bookkeeping: for an **existing** week,
> `_loadSessionForCurrentWeek()` caches the persisted session (which already has an id) into
> `_weekSessions`. For a **new** week, `upsertSession` assigns the id in place on the cached
> instance (fields are non-final), and the line above writes that instance back into
> `_weekSessions`, so the next autosave reuses the same id → one row.

**Edit B — active-plan match (around line 512).** REPLACE:

```dart
      (plan) => plan.key == widget.plan.key,
```

with:

```dart
      (plan) => plan.id == widget.plan.id,
```

**Edit C — tab selected match (around line 657).** REPLACE:

```dart
            final isSelected =
                plan.key == activePlan.key || index == widget.planIndex;
```

with:

```dart
            final isSelected =
                plan.id == activePlan.id || index == widget.planIndex;
```

> Do NOT change `_getOrCreateSession`, `_updateSession`, `_loadSessionForCurrentWeek`, or the
> name-based `HiveService.getSessionForPlanAndWeek(...)` calls — they still work as-is. The `.key`
> → `.id` change only affects how the active plan is matched among the live plan list.

---

## Step 0.11 — `history_screen.dart` (fixes the wrong-record bug)

**Edit A — delete by id (around line 108).** REPLACE:

```dart
                                    provider.deleteSession(index);
```

with:

```dart
                                    provider.deleteSession(session.id!);
```

**Edit B — navigate to edit without an index (around lines 130–133).** REPLACE:

```dart
                      builder: (_) => EditSessionScreen(
                        session: session,
                        sessionIndex: index,
                      ),
```

with:

```dart
                      builder: (_) => EditSessionScreen(
                        session: session,
                      ),
```

**Edit C — `EditSessionScreen` drops `sessionIndex` (around lines 380–392).** REPLACE:

```dart
class EditSessionScreen extends StatefulWidget {
  final WorkoutSession session;
  final int sessionIndex;

  const EditSessionScreen({
    super.key,
    required this.session,
    required this.sessionIndex,
  });
```

with:

```dart
class EditSessionScreen extends StatefulWidget {
  final WorkoutSession session;

  const EditSessionScreen({
    super.key,
    required this.session,
  });
```

**Edit D — `_save` updates by id (around lines 419–423).** REPLACE:

```dart
  void _save() {
    _session = _session.copyWith(planName: _planNameController.text);
    context
        .read<WorkoutSessionProvider>()
        .updateSession(widget.sessionIndex, _session);
```

with:

```dart
  void _save() {
    _session = _session.copyWith(planName: _planNameController.text);
    context.read<WorkoutSessionProvider>().updateSession(_session);
```

> `_session` starts as `widget.session.copyWith()`, and `copyWith` now carries `id` forward, so the
> update replaces the correct record by id regardless of list sort order — **this is the
> wrong-record bug fix.**

---

## Step 0.12 — `backup_service.dart` (bump to v2, keep v1 import)

Overwrite `lib/services/backup_service.dart` entirely with:

```dart
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';

class ExportResult {
  final String jsonString;
  final String fileName;

  ExportResult({required this.jsonString, required this.fileName});
}

class ImportResult {
  final bool success;
  final String? errorMessage;
  final int? version;
  final List<WorkoutPlan>? plans;
  final List<WorkoutSession>? sessions;
  final Map<String, dynamic>? settings;

  ImportResult._(
      {required this.success,
      this.errorMessage,
      this.version,
      this.plans,
      this.sessions,
      this.settings});

  factory ImportResult.success(List<WorkoutPlan> plans,
          List<WorkoutSession> sessions, Map<String, dynamic> settingsMap) =>
      ImportResult._(
          success: true,
          plans: plans,
          sessions: sessions,
          settings: settingsMap);

  factory ImportResult.invalid(String message) =>
      ImportResult._(success: false, errorMessage: message);

  factory ImportResult.versionMismatch(int version) => ImportResult._(
      success: false,
      errorMessage: 'Unsupported backup version: $version',
      version: version);
}

class BackupService {
  static const int _currentVersion = 2;
  static const _uuid = Uuid();

  static ExportResult exportData({
    required List<WorkoutPlan> plans,
    required List<WorkoutSession> sessions,
    required Map<String, dynamic> settings,
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final data = {
      'version': _currentVersion,
      'exportedAt': now.toIso8601String(),
      'settings': settings,
      'workoutPlans': plans.map((p) => p.toJson()).toList(),
      'workoutSessions': sessions.map((s) => s.toJson()).toList(),
    };

    return ExportResult(
      jsonString: const JsonEncoder.withIndent('  ').convert(data),
      fileName: 'gymapp_backup_$dateStr.json',
    );
  }

  static ImportResult importData(String jsonString) {
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return ImportResult.invalid('File is not valid JSON');
    }

    final version = parsed['version'];
    if (version is! int) {
      return ImportResult.invalid('File is not valid JSON');
    }
    // Accept v1 (no ids) and v2 (with ids). v1 records are upgraded on import.
    if (version != 1 && version != _currentVersion) {
      return ImportResult.versionMismatch(version);
    }

    final plansRaw = parsed['workoutPlans'];
    final sessionsRaw = parsed['workoutSessions'];
    final settingsRaw = parsed['settings'];
    if (plansRaw is! List || sessionsRaw is! List || settingsRaw is! Map) {
      return ImportResult.invalid('Invalid plan or session data');
    }
    final settingsMap = settingsRaw.cast<String, dynamic>();

    try {
      final now = DateTime.now();
      final plans = plansRaw
          .map((p) => WorkoutPlan.fromJson(p as Map<String, dynamic>))
          .map((p) {
        p.id ??= _uuid.v4(); // v1 upgrade: assign id if missing
        p.updatedAt ??= now;
        p.dirty = true; // imported records need to sync up
        return p;
      }).toList();
      final sessions = sessionsRaw
          .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
          .map((s) {
        s.id ??= _uuid.v4();
        s.updatedAt ??= now;
        s.dirty = true;
        return s;
      }).toList();
      return ImportResult.success(plans, sessions, settingsMap);
    } catch (_) {
      return ImportResult.invalid('Invalid plan or session data');
    }
  }
}
```

> The import UI calls `HiveService.replaceAllPlans/replaceAllSessions` (updated in Step 0.5), which
> re-key by id and mark `dirty`. No settings-screen change needed for Phase 0.

---

## Step 0.13 — Analyze, fix stragglers, and run tests

```bash
flutter analyze
```

Fix every error. Likely stragglers and how to resolve:

- **`startWorkout`/`saveWorkout` not defined** — a call-site still uses the old append API. Switch
  it to build a `WorkoutSession` (with `planId`/`planName`/`weekNumber`) and call
  `upsertSession(session)`.
- **`updateSession`/`deleteSession`/`updatePlan`/`deletePlan` argument type** — a call-site still
  passes an `int` index. Pass the model (`upsertSession`/`updatePlan`) or the `String id`
  (`deleteSession`/`deletePlan`).
- **`sessionIndex` not defined** — a leftover reference to the removed `EditSessionScreen` field.
- **`widget_test.dart` fails to compile** — if it constructs `EditSessionScreen(... sessionIndex:)`
  or calls removed provider methods, update it to the new signatures.

Then:

```bash
flutter test
```

---

## Verification checklist (must all pass before commit)

Test BOTH a fresh install and an in-place upgrade:

- [ ] **Fresh install** (uninstall first, or clear app data): app starts, no crash, empty state OK.
- [ ] **In-place upgrade** with existing data: launch once; check logs for
      `id-key migration OK: N plans, M sessions.` Plans/sessions still visible; grid order unchanged.
- [ ] **Create / edit / duplicate / delete a plan** — all work; deleted plan disappears and does not
      reappear on restart (tombstone hidden).
- [ ] **Autosave a workout, add sets, leave and return, add more** → History shows **ONE** session
      for that (plan, week), not duplicates. (Core append-bug check.)
- [ ] **Delete a specific workout from History** (with several present, ideally where insertion
      order ≠ date order) → the **correct** one is removed. (Wrong-record bug check.)
- [ ] **Edit a workout from History** → the edit lands on the correct record after restart.
- [ ] **Export → Import** round-trips: export a v2 file, Clear All Data, import it → data returns.
- [ ] **Import a v1 file** (an older `gymapp_backup_*.json` from before this phase, if you have one)
      → imports without a version error and records get ids.
- [ ] `flutter analyze` clean; `flutter test` green.

**If migration fails:** the log prints `id-key migration FAILED …` and leaves data intact (it
retries next launch). The pre-migration JSON is in `shared_preferences` under `idkey_backup_plans` /
`idkey_backup_sessions` for manual recovery.

## Suggested commit

```
feat(phase-0): stable ids + sync metadata, id-based CRUD, fix append/wrong-record bugs
```

Do not commit unless the human asks.
