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
  // RAW accessors for the sync engine.
  // getAll*Raw: include tombstones (deletedAt != null) — sync must push deletes.
  // put*Raw: write WITHOUT touching dirty/updatedAt — used when applying a
  //          record pulled from the server (it is already authoritative).
  // ---------------------------------------------------------------------------
  static List<WorkoutPlan> getAllPlansRaw() => _plansBox.values.toList();

  static List<WorkoutSession> getAllSessionsRaw() =>
      _sessionsBox.values.toList();

  static List<WorkoutPlan> getDirtyPlans() =>
      _plansBox.values.where((p) => p.dirty == true).toList();

  static List<WorkoutSession> getDirtySessions() =>
      _sessionsBox.values.where((s) => s.dirty == true).toList();

  static Future<void> putPlanRaw(WorkoutPlan plan) async {
    await _plansBox.put(plan.id, plan);
  }

  static Future<void> putSessionRaw(WorkoutSession session) async {
    await _sessionsBox.put(session.id, session);
  }

  /// Clear the dirty flag after a successful push, without bumping updatedAt.
  static Future<void> clearPlanDirty(String id) async {
    final p = _plansBox.get(id);
    if (p == null) return;
    p.dirty = false;
    await _plansBox.put(id, p);
  }

  static Future<void> clearSessionDirty(String id) async {
    final s = _sessionsBox.get(id);
    if (s == null) return;
    s.dirty = false;
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
