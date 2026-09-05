import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/split.dart';
import '../models/split_preference.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise_template.dart';
import '../models/exercise.dart';
import '../models/set.dart';
import '../models/set_template.dart';
import '../utils/split_identity.dart';

class HiveService {
  static const String plansBox = 'workout_plans';
  static const String sessionsBox = 'workout_sessions';
  static const String splitsBox = 'splits';
  static const String splitPreferencesBox = 'split_preferences';
  static const _uuid = Uuid();
  static const String _migrationFlag = 'idkey_migration_v1_done';

  static Future<void> init() async {
    await Hive.initFlutter();

    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    Hive.registerAdapter(SplitAdapter());
    Hive.registerAdapter(SplitPreferenceAdapter());

    await Hive.openBox<WorkoutPlan>(plansBox);
    await Hive.openBox<WorkoutSession>(sessionsBox);
    await Hive.openBox<Split>(splitsBox);
    await Hive.openBox<SplitPreference>(splitPreferencesBox);

    await _migrateToIdKeys();
  }

  static Box<WorkoutPlan> get _plansBox => Hive.box<WorkoutPlan>(plansBox);
  static Box<WorkoutSession> get _sessionsBox =>
      Hive.box<WorkoutSession>(sessionsBox);
  static Box<Split> get _splitsBox => Hive.box<Split>(splitsBox);
  static Box<SplitPreference> get _splitPreferencesBox =>
      Hive.box<SplitPreference>(splitPreferencesBox);

  // ---------------------------------------------------------------------------
  // Split workspace operations
  // ---------------------------------------------------------------------------
  static List<Split> getSplits() =>
      _splitsBox.values.where((s) => s.deletedAt == null).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  static List<Split> getAllSplitsRaw() => _splitsBox.values.toList();

  static Split? getSplitById(String id) => _splitsBox.get(id);

  static SplitPreference? getSplitPreference(String userId) =>
      _splitPreferencesBox.get(userId);

  static List<SplitPreference> getAllSplitPreferencesRaw() =>
      _splitPreferencesBox.values.toList();

  static String? getActiveSplitId(String userId) {
    final preference = getSplitPreference(userId);
    final split =
        preference == null ? null : getSplitById(preference.activeSplitId);
    if (split != null && split.deletedAt == null) return split.id;
    final splits = getSplits();
    return splits.isEmpty ? null : splits.first.id;
  }

  static Future<void> ensureSplitWorkspace(String userId) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final migrationKey = 'split_scope_migration_$userId';
    final needsMigration = prefs.getBool(migrationKey) != true;
    if (needsMigration) {
      await prefs.setString(
        'split_scope_backup_plans_$userId',
        jsonEncode(_plansBox.values.map((plan) => plan.toJson()).toList()),
      );
      await prefs.setString(
        'split_scope_backup_sessions_$userId',
        jsonEncode(
          _sessionsBox.values.map((session) => session.toJson()).toList(),
        ),
      );
    }
    var activeSplits = getSplits();
    if (activeSplits.isEmpty) {
      final defaultId = defaultSplitIdForUser(userId);
      final existing = getSplitById(defaultId);
      if (existing == null) {
        final split = Split(
          id: defaultId,
          name: 'My Split',
          userId: userId,
          createdAt: now,
          updatedAt: now,
          dirty: true,
        );
        await _splitsBox.put(split.id, split);
      }
      activeSplits = getSplits();
    }
    if (activeSplits.isEmpty) return;

    var activeId = getActiveSplitId(userId);
    activeId ??= activeSplits.first.id;
    final preference = getSplitPreference(userId);
    if (preference == null || preference.activeSplitId != activeId) {
      await putSplitPreference(
        SplitPreference(
          userId: userId,
          activeSplitId: activeId,
          updatedAt: now,
          dirty: true,
        ),
      );
    }

    for (final plan in _plansBox.values.where((p) => p.splitId == null)) {
      plan.splitId = activeId;
      plan.userId ??= userId;
      plan.updatedAt = now;
      plan.dirty = true;
      await _plansBox.put(plan.id, plan);
    }
    for (final session in _sessionsBox.values.where((s) => s.splitId == null)) {
      final plan = session.planId == null ? null : getPlanById(session.planId!);
      session.splitId = plan?.splitId ?? activeId;
      session.userId ??= userId;
      session.updatedAt = now;
      session.dirty = true;
      await _sessionsBox.put(session.id, session);
    }
    if (needsMigration) await prefs.setBool(migrationKey, true);
  }

  static Future<void> upsertSplit(Split split) async {
    final now = DateTime.now();
    final value = split.copyWith(updatedAt: now, dirty: true);
    await _splitsBox.put(value.id, value);
  }

  static Future<void> putSplitRaw(Split split) =>
      _splitsBox.put(split.id, split);

  static Future<void> putSplitPreference(SplitPreference preference) =>
      _splitPreferencesBox.put(preference.userId, preference);

  static Future<void> putSplitPreferenceRaw(SplitPreference preference) =>
      _splitPreferencesBox.put(preference.userId, preference);

  static List<Split> getDirtySplits({required bool deleted}) =>
      _splitsBox.values
          .where((s) => s.dirty == true && (s.deletedAt != null) == deleted)
          .toList();

  static List<SplitPreference> getDirtySplitPreferences() =>
      _splitPreferencesBox.values.where((p) => p.dirty == true).toList();

  static Future<void> clearSplitDirty(String id) async {
    final split = getSplitById(id);
    if (split == null) return;
    split.dirty = false;
    await _splitsBox.put(id, split);
  }

  static Future<void> clearSplitPreferenceDirty(String userId) async {
    final preference = getSplitPreference(userId);
    if (preference == null) return;
    preference.dirty = false;
    await _splitPreferencesBox.put(userId, preference);
  }

  static Future<void> setActiveSplit(String userId, String splitId) async {
    final split = getSplitById(splitId);
    if (split == null || split.deletedAt != null) {
      throw StateError('The selected split is unavailable.');
    }
    await putSplitPreference(
      SplitPreference(
        userId: userId,
        activeSplitId: splitId,
        updatedAt: DateTime.now(),
        dirty: true,
      ),
    );
  }

  static Future<void> softDeleteSplit({
    required String userId,
    required String splitId,
    required String replacementSplitId,
  }) async {
    if (splitId == replacementSplitId) {
      throw StateError('Choose a different replacement split.');
    }
    final active = getSplits();
    if (active.length <= 1) {
      throw StateError('The last split cannot be deleted.');
    }
    if (getSplitPreference(userId)?.activeSplitId == splitId) {
      await setActiveSplit(userId, replacementSplitId);
    }
    final now = DateTime.now();
    for (final plan in _plansBox.values.where(
      (p) => p.splitId == splitId && p.deletedAt == null,
    )) {
      plan.deletedAt = now;
      plan.updatedAt = now;
      plan.dirty = true;
      await _plansBox.put(plan.id, plan);
    }
    for (final session in _sessionsBox.values.where(
      (s) => s.splitId == splitId && s.deletedAt == null,
    )) {
      session.deletedAt = now;
      session.updatedAt = now;
      session.dirty = true;
      await _sessionsBox.put(session.id, session);
    }
    final split = getSplitById(splitId);
    if (split != null) {
      split.deletedAt = now;
      split.updatedAt = now;
      split.dirty = true;
      await _splitsBox.put(splitId, split);
    }
  }

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
      final sessionsBackup =
          _sessionsBox.values.map((s) => s.toJson()).toList();
      await prefs.setString('idkey_backup_plans', jsonEncode(plansBackup));
      await prefs.setString(
        'idkey_backup_sessions',
        jsonEncode(sessionsBackup),
      );

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
      print(
        'id-key migration OK: '
        '${plansById.length} plans, ${sessionsById.length} sessions.',
      );
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
  static List<WorkoutPlan> getPlans({String? splitId}) =>
      _plansBox.values
          .where(
            (p) =>
                p.deletedAt == null &&
                (splitId == null || p.splitId == splitId),
          )
          .toList();

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
  static List<WorkoutSession> getSessions({String? splitId}) =>
      _sessionsBox.values
          .where(
            (s) =>
                s.deletedAt == null &&
                (splitId == null || s.splitId == splitId),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// User-facing history. Drafts remain available through [getSessions] for
  /// sync, backup, restoration, and split cleanup.
  static List<WorkoutSession> getCompletedSessions({String? splitId}) =>
      getSessions(
        splitId: splitId,
      ).where((session) => session.isCompleted).toList();

  /// There may be only one running timer account-wide, across all splits.
  static WorkoutSession? getRunningSession({String? excludingId}) {
    for (final session in getSessions()) {
      if (session.id != excludingId && session.isTimerRunning) return session;
    }
    return null;
  }

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
  // Historical analytics read completed sessions only. Plan/week restoration
  // below intentionally keeps using the all-session query so drafts reopen.
  // ---------------------------------------------------------------------------
  static WorkoutSession? getLastSessionForExercise(
    String exerciseName,
    String? splitId,
  ) {
    final sessions = getCompletedSessions(splitId: splitId);
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
          return session;
        }
      }
    }
    return null;
  }

  static Exercise? getLastExerciseData(String exerciseName, String? splitId) {
    final session = getLastSessionForExercise(exerciseName, splitId);
    if (session == null) return null;
    for (var exercise in session.exercises) {
      if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
        return exercise;
      }
    }
    return null;
  }

  static List<WorkoutSession> getSessionsForPlan(
    String planName,
    String? splitId,
  ) {
    return getSessions(
      splitId: splitId,
    ).where((s) => s.planName.toLowerCase() == planName.toLowerCase()).toList();
  }

  static List<int> getWeeksForPlan(String planName, String? splitId) {
    final sessions = getSessionsForPlan(planName, splitId);
    final weeks = sessions.map((s) => s.weekNumber).toSet().toList();
    weeks.sort();
    return weeks;
  }

  static WorkoutSession? getSessionForPlanAndWeek(
    String planName,
    int weekNumber,
    String? splitId,
  ) {
    final sessions = getSessionsForPlan(planName, splitId);
    for (var session in sessions) {
      if (session.weekNumber == weekNumber) {
        return session;
      }
    }
    return null;
  }

  static Set? getLastSetForExercise(String exerciseName, String? splitId) {
    final exercise = getLastExerciseData(exerciseName, splitId);
    if (exercise == null || exercise.sets.isEmpty) return null;
    return exercise.sets.last;
  }

  static double getExercisePR(String exerciseName, String? splitId) {
    final sessions = getCompletedSessions(splitId: splitId);
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

  static List<String> getAllExerciseNames(String? splitId) {
    final sessions = getCompletedSessions(splitId: splitId);
    final names = <String>{};
    for (var session in sessions) {
      for (var exercise in session.exercises) {
        names.add(exercise.name);
      }
    }
    return names.toList()..sort();
  }

  static Map<String, double> getAllExercisePRs(String? splitId) {
    final names = getAllExerciseNames(splitId);
    final prs = <String, double>{};
    for (var name in names) {
      prs[name] = getExercisePR(name, splitId);
    }
    return prs;
  }

  static List<Map<String, dynamic>> getExerciseProgression(
    String exerciseName,
    String? splitId,
  ) {
    final sessions = getCompletedSessions(splitId: splitId);
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
      (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
    );
    return progression;
  }

  static int getWorkoutsThisWeek(String? splitId) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startDate = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );

    return getCompletedSessions(
      splitId: splitId,
    ).where((s) => s.date.isAfter(startDate)).length;
  }

  static Map<int, int> getWorkoutFrequency(int weeksBack, String? splitId) {
    final frequency = <int, int>{};
    final now = DateTime.now();

    for (int i = 0; i < weeksBack; i++) {
      frequency[i] = 0;
    }

    for (var session in getCompletedSessions(splitId: splitId)) {
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
    String planName,
    int oldWeek,
    int newWeek,
    String? splitId,
  ) async {
    final matches =
        getSessionsForPlan(
          planName,
          splitId,
        ).where((s) => s.weekNumber == oldWeek).toList();
    for (final s in matches) {
      await upsertSession(
        s.copyWith(weekNumber: newWeek),
      ); // same id -> replace
    }
  }

  static Future<void> deleteSessionForPlanAndWeek(
    String planName,
    int weekNumber,
    String? splitId,
  ) async {
    final matches =
        _sessionsBox.values
            .where(
              (s) =>
                  s.deletedAt == null &&
                  s.planName.toLowerCase() == planName.toLowerCase() &&
                  (splitId == null || s.splitId == splitId) &&
                  s.weekNumber == weekNumber,
            )
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

  static Future<void> clearSplitData() async {
    await _splitsBox.clear();
    await _splitPreferencesBox.clear();
  }

  static Future<void> softDeleteAllWorkoutData() async {
    final now = DateTime.now();
    for (final plan in _plansBox.values.where((p) => p.deletedAt == null)) {
      plan.deletedAt = now;
      plan.updatedAt = now;
      plan.dirty = true;
      await _plansBox.put(plan.id, plan);
    }
    for (final session in _sessionsBox.values.where(
      (s) => s.deletedAt == null,
    )) {
      session.deletedAt = now;
      session.updatedAt = now;
      session.dirty = true;
      await _sessionsBox.put(session.id, session);
    }
  }

  static Future<void> softDeleteWorkoutDataForSplit(String splitId) async {
    final now = DateTime.now();
    for (final plan in _plansBox.values.where(
      (p) => p.splitId == splitId && p.deletedAt == null,
    )) {
      plan.deletedAt = now;
      plan.updatedAt = now;
      plan.dirty = true;
      await _plansBox.put(plan.id, plan);
    }
    for (final session in _sessionsBox.values.where(
      (s) => s.splitId == splitId && s.deletedAt == null,
    )) {
      session.deletedAt = now;
      session.updatedAt = now;
      session.dirty = true;
      await _sessionsBox.put(session.id, session);
    }
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

  static Future<void> replaceAllWorkoutData({
    required String userId,
    required List<Split> splits,
    required String activeSplitId,
    required List<WorkoutPlan> plans,
    required List<WorkoutSession> sessions,
  }) async {
    final now = DateTime.now();
    final importedSplitIds = splits.map((split) => split.id).toSet();
    final importedPlanIds =
        plans.map((plan) => plan.id).whereType<String>().toSet();
    final importedSessionIds =
        sessions.map((session) => session.id).whereType<String>().toSet();

    for (final old in _plansBox.values.where(
      (plan) => !importedPlanIds.contains(plan.id),
    )) {
      old.deletedAt = now;
      old.updatedAt = now;
      old.dirty = true;
      await _plansBox.put(old.id, old);
    }
    for (final plan in plans) {
      plan.id ??= _uuid.v4();
      plan.userId = userId;
      plan.updatedAt = now;
      plan.deletedAt = null;
      plan.dirty = true;
      await _plansBox.put(plan.id, plan);
    }

    for (final old in _sessionsBox.values.where(
      (session) => !importedSessionIds.contains(session.id),
    )) {
      old.deletedAt = now;
      old.updatedAt = now;
      old.dirty = true;
      await _sessionsBox.put(old.id, old);
    }
    for (final session in sessions) {
      session.id ??= _uuid.v4();
      session.userId = userId;
      session.updatedAt = now;
      session.deletedAt = null;
      session.dirty = true;
      await _sessionsBox.put(session.id, session);
    }

    for (final split in splits) {
      final imported = split.copyWith(
        userId: userId,
        updatedAt: now,
        dirty: true,
      );
      await _splitsBox.put(imported.id, imported);
    }
    await setActiveSplit(userId, activeSplitId);
    for (final old in _splitsBox.values.where(
      (split) =>
          !importedSplitIds.contains(split.id) && split.deletedAt == null,
    )) {
      old.deletedAt = now;
      old.updatedAt = now;
      old.dirty = true;
      await _splitsBox.put(old.id, old);
    }
  }
}
