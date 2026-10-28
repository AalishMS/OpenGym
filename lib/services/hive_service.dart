import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/split.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/split_preference.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise_template.dart';
import '../models/exercise.dart';
import '../models/set.dart';
import '../models/set_template.dart';
import '../utils/split_identity.dart';
import 'training_block_graph.dart';
import 'training_block_restore.dart';
import 'training_block_migration.dart';
import 'sync_service.dart';

class HiveService {
  static const String trainingBlocksBox = 'training_blocks';
  static const String trainingWeeksBox = 'training_weeks';
  static const String workoutProgressBox = 'workout_progress';
  static const String trainingOperationsBox = 'training_operations';

  static Future<void> openTrainingBoxes() async {
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(TrainingBlockAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(TrainingWeekAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(WorkoutProgressAdapter());
    }
    await Hive.openBox<TrainingBlock>(trainingBlocksBox);
    await Hive.openBox<TrainingWeek>(trainingWeeksBox);
    await Hive.openBox<WorkoutProgress>(workoutProgressBox);
    await Hive.openBox<dynamic>(trainingOperationsBox);
  }

  static TrainingBlock? getTrainingBlockById(String id) =>
      Hive.box<TrainingBlock>(trainingBlocksBox).get(id);
  static TrainingWeek? getTrainingWeekById(String id) =>
      Hive.box<TrainingWeek>(trainingWeeksBox).get(id);
  static WorkoutProgress? getWorkoutProgressById(String id) =>
      Hive.box<WorkoutProgress>(workoutProgressBox).get(id);

  static List<Split> getAllSplitsRaw() => _splitsBox.values.toList();

  static List<TrainingBlock> getAllTrainingBlocksRaw() =>
      Hive.isBoxOpen(trainingBlocksBox)
          ? Hive.box<TrainingBlock>(trainingBlocksBox).values.toList()
          : [];
  static List<TrainingWeek> getAllTrainingWeeksRaw() =>
      Hive.isBoxOpen(trainingWeeksBox)
          ? Hive.box<TrainingWeek>(trainingWeeksBox).values.toList()
          : [];
  static List<WorkoutProgress> getAllWorkoutProgressRaw() =>
      Hive.isBoxOpen(workoutProgressBox)
          ? Hive.box<WorkoutProgress>(workoutProgressBox).values.toList()
          : [];

  static List<TrainingBlock> blocksForSplit(String splitId) =>
      getAllTrainingBlocksRaw()
          .where((b) => b.splitId == splitId && b.deletedAt == null)
          .toList()
        ..sort((a, b) {
          final order = a.position.compareTo(b.position);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
  static List<TrainingWeek> weeksForBlock(String splitId, String blockId) =>
      getAllTrainingWeeksRaw()
          .where(
            (w) =>
                w.splitId == splitId &&
                w.blockId == blockId &&
                w.deletedAt == null,
          )
          .toList()
        ..sort((a, b) {
          final order = a.number.compareTo(b.number);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
  static WorkoutProgress? progressForPlan(String splitId, String planId) {
    for (final p in getAllWorkoutProgressRaw()) {
      if (p.splitId == splitId && p.planId == planId && p.deletedAt == null) {
        return p;
      }
    }
    return null;
  }

  static List<WorkoutSession> sessionsForPlanWeek(
    String splitId,
    String planId,
    String weekId,
  ) =>
      getSessions(
        splitId: splitId,
      ).where((s) => s.planId == planId && s.trainingWeekId == weekId).toList();

  static Future<void> putTrainingBlockRaw(TrainingBlock block) =>
      Hive.box<TrainingBlock>(trainingBlocksBox).put(block.id, block);
  static Future<void> putTrainingWeekRaw(TrainingWeek week) =>
      Hive.box<TrainingWeek>(trainingWeeksBox).put(week.id, week);
  static Future<void> putWorkoutProgressRaw(WorkoutProgress progress) =>
      Hive.box<WorkoutProgress>(workoutProgressBox).put(progress.id, progress);

  /// Caller owns the existing mutation gate. Persist a fixed relabel intent
  /// before the week changes, so startup can finish all display snapshots.
  static Future<void> persistTrainingWeekRebase(
    TrainingWeek target, {
    required String? ownerId,
  }) async {
    await recoverTrainingWeekRebase(ownerId: ownerId);
    final current = getTrainingWeekById(target.id);
    if (current == null ||
        current.userId != ownerId ||
        target.userId != ownerId ||
        current.splitId != target.splitId ||
        current.blockId != target.blockId) {
      throw StateError('The rebased week is unavailable in this account.');
    }
    if (current.number == target.number) {
      await putTrainingWeekRaw(target);
      return;
    }
    final operations = Hive.box<dynamic>(trainingOperationsBox);
    await operations.put('weekRebase', {
      'ownerId': ownerId,
      'previousNumber': current.number,
      'week': target.toJson(),
      'dirty': target.dirty,
    });
    await operations.flush();
    await recoverTrainingWeekRebase(ownerId: ownerId);
  }

  static Future<void> recoverTrainingWeekRebase({
    required String? ownerId,
  }) async {
    final operations = Hive.box<dynamic>(trainingOperationsBox);
    final raw = operations.get('weekRebase');
    if (raw == null) return;
    final intent = Map<String, dynamic>.from(raw as Map);
    if (intent['ownerId'] != ownerId) {
      throw StateError('Pending week rebase belongs to another account.');
    }
    final target = TrainingWeek.fromJson(
      Map<String, dynamic>.from(intent['week'] as Map),
    ).copyWith(dirty: intent['dirty'] as bool?);
    final current = getTrainingWeekById(target.id);
    if (current == null ||
        current.userId != ownerId ||
        target.userId != ownerId ||
        current.splitId != target.splitId ||
        current.blockId != target.blockId ||
        (current.number != intent['previousNumber'] &&
            current.number != target.number)) {
      throw StateError(
        'The pending week rebase conflicts with saved structure.',
      );
    }
    // A later durable deletion wins; recovery never revives a parent or week.
    final value =
        current.deletedAt != null && target.deletedAt == null
            ? current
            : target;
    final split = getSplitById(value.splitId);
    final block = getTrainingBlockById(value.blockId);
    if (split == null ||
        block == null ||
        split.userId != ownerId ||
        block.userId != ownerId ||
        block.splitId != value.splitId) {
      throw StateError('The pending rebase parent is unavailable.');
    }
    await putTrainingWeekRaw(value);
    await Hive.box<TrainingWeek>(trainingWeeksBox).flush();
    // Re-read current rows so an unrelated saved edit is never overwritten by
    // recovery. Only the display snapshot changes; IDs, sets and timers stay.
    for (final session in getAllSessionsRaw().where(
      (s) => s.trainingWeekId == value.id && s.weekNumber != value.number,
    )) {
      if (session.userId != ownerId || session.splitId != value.splitId) {
        throw StateError('A pending session rebase has conflicting ownership.');
      }
      await putSessionRaw(
        session.copyWith(weekNumber: value.number, dirty: true),
      );
    }
    await _sessionsBox.flush();
    await operations.delete('weekRebase');
    await operations.flush();
  }

  static List<SplitPreference> getAllSplitPreferencesRaw() =>
      _splitPreferencesBox.values.toList();

  static TrainingBlockGraph readTrainingGraph({required String? ownerId}) =>
      TrainingBlockGraph(
        ownerId: ownerId,
        activeSplitId: getActiveSplitId(ownerId ?? 'local'),
        splits: getAllSplitsRaw(),
        plans: getAllPlansRaw(),
        sessions: getAllSessionsRaw(),
        blocks: getAllTrainingBlocksRaw(),
        weeks: getAllTrainingWeeksRaw(),
        progress: getAllWorkoutProgressRaw(),
      );

  static Future<void> flushAllWorkoutData() async {
    await flushTrainingData();
    await _plansBox.flush();
    await _splitsBox.flush();
    await _splitPreferencesBox.flush();
  }

  static Future<void> setActiveSplitForRecovery(
    String owner,
    String id,
    DateTime updatedAt,
  ) => putSplitPreferenceRaw(
    SplitPreference(
      userId: owner,
      activeSplitId: id,
      updatedAt: updatedAt,
      dirty: true,
    ),
  );

  static String validateTrainingName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 40) {
      throw ArgumentError('Use a block name of 1–40 characters.');
    }
    return name;
  }

  static Split validateTrainingSplit(String splitId, String? ownerId) {
    final split = getSplitById(splitId);
    if (split == null || split.deletedAt != null || split.userId != ownerId) {
      throw StateError('The split is unavailable in this account.');
    }
    return split;
  }

  static TrainingBlock validateTrainingBlock(
    String splitId,
    String blockId,
    String? ownerId,
  ) {
    validateTrainingSplit(splitId, ownerId);
    final block = Hive.box<TrainingBlock>(trainingBlocksBox).get(blockId);
    if (block == null ||
        block.deletedAt != null ||
        block.splitId != splitId ||
        block.userId != ownerId) {
      throw StateError('The training block is unavailable.');
    }
    return block;
  }

  /// A deliberately small roll-forward record: fixed IDs survive process death
  /// between the block and week writes. The caller already owns the mutation gate.
  static Future<void> persistTrainingCreation(
    TrainingBlock block,
    List<TrainingWeek> weeks,
  ) async {
    final box = Hive.box<dynamic>(trainingOperationsBox);
    final pending = box.get('create');
    if (pending != null) {
      final map = Map<String, dynamic>.from(pending as Map);
      if (map['ownerId'] != block.userId ||
          (map['block'] as Map)['splitId'] != block.splitId) {
        throw StateError('Finish the pending block creation first.');
      }
      await recoverTrainingOperation(ownerId: block.userId);
      return;
    }
    await box.put('create', {
      'ownerId': block.userId,
      'block': block.toJson(),
      'weeks': weeks.map((w) => w.toJson()).toList(),
    });
    await box.flush();
    await recoverTrainingOperation(ownerId: block.userId);
  }

  static Future<TrainingBlock?> recoverTrainingOperation({
    required String? ownerId,
  }) async {
    final operations = Hive.box<dynamic>(trainingOperationsBox);
    final raw = operations.get('create');
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    if (map['ownerId'] != ownerId) {
      throw StateError('Pending creation belongs to a different account.');
    }
    final block = TrainingBlock.fromJson(
      Map<String, dynamic>.from(map['block'] as Map),
    );
    validateTrainingSplit(block.splitId, ownerId);
    final existing = Hive.box<TrainingBlock>(trainingBlocksBox).get(block.id);
    if (existing?.deletedAt != null) {
      throw StateError('A deleted block cannot be restored.');
    }
    if (existing == null) {
      await putTrainingBlockRaw(block.copyWith(dirty: true));
    }
    for (final rawWeek in map['weeks'] as List) {
      final week = TrainingWeek.fromJson(
        Map<String, dynamic>.from(rawWeek as Map),
      );
      final saved = Hive.box<TrainingWeek>(trainingWeeksBox).get(week.id);
      if (saved?.deletedAt != null) {
        throw StateError('A deleted week cannot be restored.');
      }
      if (saved == null) await putTrainingWeekRaw(week.copyWith(dirty: true));
    }
    await flushTrainingData();
    await operations.delete('create');
    await operations.flush();
    return Hive.box<TrainingBlock>(trainingBlocksBox).get(block.id);
  }

  static Future<void> flushTrainingData() async {
    await Hive.box<TrainingBlock>(trainingBlocksBox).flush();
    await Hive.box<TrainingWeek>(trainingWeeksBox).flush();
    await Hive.box<WorkoutProgress>(workoutProgressBox).flush();
    await _sessionsBox.flush();
  }

  static Future<void> clearTrainingData() async {
    if (Hive.isBoxOpen(trainingBlocksBox)) {
      await Hive.box<TrainingBlock>(trainingBlocksBox).clear();
    }
    if (Hive.isBoxOpen(trainingWeeksBox)) {
      await Hive.box<TrainingWeek>(trainingWeeksBox).clear();
    }
    if (Hive.isBoxOpen(workoutProgressBox)) {
      await Hive.box<WorkoutProgress>(workoutProgressBox).clear();
    }
    if (Hive.isBoxOpen(trainingOperationsBox)) {
      await Hive.box<dynamic>(trainingOperationsBox).clear();
    }
  }

  static const String plansBox = 'workout_plans';
  static const String sessionsBox = 'workout_sessions';
  static const String splitsBox = 'splits';
  static const String splitPreferencesBox = 'split_preferences';
  static const _uuid = Uuid();
  static const String _migrationFlag = 'idkey_migration_v1_done';

  static Future<void> init() async {
    if (Hive.isBoxOpen(plansBox) &&
        Hive.isBoxOpen(sessionsBox) &&
        Hive.isBoxOpen(splitsBox) &&
        Hive.isBoxOpen(splitPreferencesBox) &&
        Hive.isBoxOpen(trainingBlocksBox) &&
        Hive.isBoxOpen(trainingWeeksBox) &&
        Hive.isBoxOpen(workoutProgressBox) &&
        Hive.isBoxOpen(trainingOperationsBox)) {
      return;
    }
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(SetAdapter().typeId)) {
      Hive.registerAdapter(SetAdapter());
    }
    if (!Hive.isAdapterRegistered(SetTemplateAdapter().typeId)) {
      Hive.registerAdapter(SetTemplateAdapter());
    }
    if (!Hive.isAdapterRegistered(ExerciseAdapter().typeId)) {
      Hive.registerAdapter(ExerciseAdapter());
    }
    if (!Hive.isAdapterRegistered(ExerciseTemplateAdapter().typeId)) {
      Hive.registerAdapter(ExerciseTemplateAdapter());
    }
    if (!Hive.isAdapterRegistered(WorkoutPlanAdapter().typeId)) {
      Hive.registerAdapter(WorkoutPlanAdapter());
    }
    if (!Hive.isAdapterRegistered(WorkoutSessionAdapter().typeId)) {
      Hive.registerAdapter(WorkoutSessionAdapter());
    }
    if (!Hive.isAdapterRegistered(TrainingBlockAdapter().typeId)) {
      Hive.registerAdapter(TrainingBlockAdapter());
    }
    if (!Hive.isAdapterRegistered(TrainingWeekAdapter().typeId)) {
      Hive.registerAdapter(TrainingWeekAdapter());
    }
    if (!Hive.isAdapterRegistered(WorkoutProgressAdapter().typeId)) {
      Hive.registerAdapter(WorkoutProgressAdapter());
    }
    if (!Hive.isAdapterRegistered(SplitAdapter().typeId)) {
      Hive.registerAdapter(SplitAdapter());
    }
    if (!Hive.isAdapterRegistered(SplitPreferenceAdapter().typeId)) {
      Hive.registerAdapter(SplitPreferenceAdapter());
    }

    await Hive.openBox<WorkoutPlan>(plansBox);
    await Hive.openBox<WorkoutSession>(sessionsBox);
    await Hive.openBox<Split>(splitsBox);
    await Hive.openBox<SplitPreference>(splitPreferencesBox);

    await Hive.openBox<TrainingBlock>(trainingBlocksBox);
    await Hive.openBox<TrainingWeek>(trainingWeeksBox);
    await Hive.openBox<WorkoutProgress>(workoutProgressBox);
    await Hive.openBox<dynamic>(trainingOperationsBox);
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

  static Split? getSplitById(String id) => _splitsBox.get(id);

  static SplitPreference? getSplitPreference(String userId) =>
      _splitPreferencesBox.get(userId);

  static String? getActiveSplitId(String userId) {
    final preference = getSplitPreference(userId);
    final split =
        preference == null ? null : getSplitById(preference.activeSplitId);
    if (split != null && split.deletedAt == null) return split.id;
    final splits = getSplits();
    return splits.isEmpty ? null : splits.first.id;
  }

  static Future<void> ensureOfflineSplitWorkspace() async {
    final splits = getSplits();
    if (splits.isEmpty) {
      final now = DateTime.now();
      final id = _uuid.v4();
      await putSplitRaw(
        Split(
          id: id,
          name: 'My Split',
          createdAt: now,
          updatedAt: now,
          dirty: true,
        ),
      );
    }
    final active = getSplits().first.id;
    for (final plan in getAllPlansRaw().where((p) => p.splitId == null)) {
      plan.splitId = active;
      await putPlanRaw(plan);
    }
    for (final session in getAllSessionsRaw().where((s) => s.splitId == null)) {
      session.splitId =
          session.planId == null
              ? active
              : getPlanById(session.planId!)?.splitId ?? active;
      await putSessionRaw(session);
    }
  }

  static Future<void> ensureSplitWorkspace(
    String userId, {
    bool provisional = false,
  }) async {
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
          // A first-adoption workspace may be created while fully offline.
          // Leave its timestamp unset so an existing server copy of the
          // deterministic default split wins the first reconciliation.
          updatedAt: provisional ? null : now,
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
          updatedAt: provisional ? null : now,
          dirty: true,
        ),
      );
    }

    for (final plan in _plansBox.values.where((p) => p.splitId == null)) {
      plan.splitId = activeId;
      plan.userId ??= userId;
      plan.updatedAt ??= now;
      plan.dirty = true;
      await _plansBox.put(plan.id, plan);
    }
    for (final session in _sessionsBox.values.where((s) => s.splitId == null)) {
      final plan = session.planId == null ? null : getPlanById(session.planId!);
      session.splitId = plan?.splitId ?? activeId;
      session.userId ??= userId;
      session.updatedAt ??= now;
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
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
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
    for (final b in getAllTrainingBlocksRaw().where(
      (b) => b.splitId == splitId && b.deletedAt == null,
    )) {
      await putTrainingBlockRaw(
        b.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      );
    }
    for (final w in getAllTrainingWeeksRaw().where(
      (w) => w.splitId == splitId && w.deletedAt == null,
    )) {
      await putTrainingWeekRaw(
        w.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      );
    }
    for (final p in getAllWorkoutProgressRaw().where(
      (p) => p.splitId == splitId && p.deletedAt == null,
    )) {
      await putWorkoutProgressRaw(
        p.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      );
    }
    final split = getSplitById(splitId);
    if (split != null) {
      split.deletedAt = now;
      split.updatedAt = now;
      split.dirty = true;
      await _splitsBox.put(splitId, split);
    }
  });

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
  static List<WorkoutPlan> getPlans({String? splitId}) {
    final plans =
        _plansBox.values
            .where(
              (p) =>
                  p.deletedAt == null &&
                  (splitId == null || p.splitId == splitId),
            )
            .toList();
    final indexed = plans.indexed.toList();
    indexed.sort((a, b) {
      final aPosition = a.$2.position;
      final bPosition = b.$2.position;
      if (aPosition == null && bPosition == null) {
        return a.$1.compareTo(b.$1);
      }
      if (aPosition == null) return 1;
      if (bPosition == null) return -1;
      final positionOrder = aPosition.compareTo(bPosition);
      if (positionOrder != 0) return positionOrder;
      return (a.$2.id ?? '').compareTo(b.$2.id ?? '');
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  /// Returns a plan by id INCLUDING tombstones (get-by-key ignores deletedAt).
  static WorkoutPlan? getPlanById(String id) => _plansBox.get(id);

  static Future<void> createPlan(
    WorkoutPlan plan, {
    String? startingWeekId,
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
    if (plan.splitId == null || !Hive.isBoxOpen(splitsBox)) {
      await upsertPlan(plan);
      return;
    }
    final split = getSplitById(plan.splitId!);
    if (split == null ||
        split.deletedAt != null ||
        (plan.userId != null && plan.userId != split.userId)) {
      throw StateError('The plan split is unavailable.');
    }
    plan.id ??= _uuid.v4();
    if (getPlanById(plan.id!) != null) {
      throw StateError('The plan already exists.');
    }
    plan.userId = split.userId;
    plan.updatedAt = DateTime.now();
    plan.dirty = true;
    var graph = TrainingBlockMigration.prepareGraph(
      readTrainingGraph(ownerId: split.userId)
          .ownedBy(split.userId)
          .copyWith(plans: [...getAllPlansRaw(), plan])
          .ensureNewStructure(split.id),
    );
    graph = graph.explicitPlanRevisions({plan.id!});
    if (startingWeekId != null) {
      final week =
          graph.weeks
              .where(
                (w) =>
                    w.id == startingWeekId &&
                    w.splitId == split.id &&
                    w.deletedAt == null,
              )
              .singleOrNull;
      if (week == null) throw StateError('The starting week is unavailable.');
      graph = graph.copyWith(
        progress: [
          for (final p in graph.progress)
            if (p.planId == plan.id)
              p.copyWith(
                activeWeekId: week.id,
                state: WorkoutProgressState.ready,
              )
            else
              p,
        ],
      );
    }
    await TrainingBlockRestore().replaceUnderGate(
      graph: graph,
      stampRecords: false,
    );
  });

  static Future<void> upsertPlan(WorkoutPlan plan) async {
    if (plan.splitId != null && Hive.isBoxOpen(splitsBox)) {
      final split = getSplitById(plan.splitId!);
      if (split == null ||
          split.deletedAt != null ||
          (plan.userId != null && plan.userId != split.userId)) {
        throw StateError('The plan split is unavailable in this account.');
      }
      plan.userId = split.userId;
    }
    plan.id ??= _uuid.v4();
    plan.updatedAt = DateTime.now();
    plan.dirty = true;
    await _plansBox.put(plan.id, plan);
  }

  /// Save a split's display order as one Hive batch.
  static Future<void> savePlanOrder(List<WorkoutPlan> plans) async {
    final now = DateTime.now();
    final updates = <String, WorkoutPlan>{};
    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      final id = plan.id;
      if (id == null) {
        throw StateError('A plan must be saved before reordering.');
      }
      updates[id] =
          plan.copyWith(position: index)
            ..updatedAt = now
            ..dirty = true;
    }
    await _plansBox.putAll(updates);
  }

  /// Raw primitives used by the preset installer while sync is gated.
  static Future<void> putPlansRaw(Map<String, WorkoutPlan> plans) =>
      _plansBox.putAll(plans);

  static Future<void> deletePlansRaw(Iterable<String> ids) =>
      _plansBox.deleteAll(ids);

  static Future<void> deleteSplitRaw(String id) => _splitsBox.delete(id);

  static Future<void> deleteSplitPreferenceRaw(String userId) =>
      _splitPreferencesBox.delete(userId);

  static Future<void> softDeletePlan(String id) =>
      SyncService.instance.runExclusiveLocalMutation(() async {
        final plan = getPlanById(id);
        if (plan == null) return;
        final now = plan.deletedAt ?? DateTime.now();
        if (plan.deletedAt == null) {
          await putPlanRaw(
            plan.copyWith(deletedAt: now, updatedAt: now, dirty: true),
          );
        }
        await tombstonePlanProgress(id, now);
      });

  static Future<void> tombstonePlanProgress(String planId, DateTime now) async {
    for (final p in getAllWorkoutProgressRaw().where(
      (p) => p.planId == planId && p.deletedAt == null,
    )) {
      await putWorkoutProgressRaw(
        p.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      );
    }
  }

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

  static Future<void> upsertSession(WorkoutSession session) async {
    final saved = session.id == null ? null : getSessionById(session.id!);
    if (saved?.completionTransition != null) {
      if (saved!.trainingWeekId != session.trainingWeekId ||
          saved.planId != session.planId ||
          saved.splitId != session.splitId) {
        throw StateError('A completed workout cannot change training slots.');
      }
      session = session.copyWith(
        completionTransition: saved.completionTransition,
      );
    }
    if (session.splitId != null && Hive.isBoxOpen(splitsBox)) {
      final split = getSplitById(session.splitId!);
      if (split == null ||
          split.deletedAt != null ||
          (session.userId != null && session.userId != split.userId)) {
        throw StateError('The workout split is unavailable in this account.');
      }
      session.userId = split.userId;
    }
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

  static String? trainingCacheOwner() {
    final owners =
        [
          ...getAllSplitsRaw().map((r) => r.userId),
          ...getAllPlansRaw().map((r) => r.userId),
          ...getAllSessionsRaw().map((r) => r.userId),
          ...getAllTrainingBlocksRaw().map((r) => r.userId),
          ...getAllTrainingWeeksRaw().map((r) => r.userId),
          ...getAllWorkoutProgressRaw().map((r) => r.userId),
        ].whereType<String>().toSet();
    if (owners.length > 1) {
      throw StateError('This cache contains different owners.');
    }
    return owners.firstOrNull;
  }

  static Future<void> softDeleteAllWorkoutData() => SyncService.instance
      .runExclusiveLocalMutation(() => clearWorkoutGraphUnderGate());
  static Future<void> softDeleteWorkoutDataForSplit(String splitId) =>
      SyncService.instance.runExclusiveLocalMutation(
        () => clearWorkoutGraphUnderGate(splitId: splitId),
      );

  static Future<void> clearWorkoutGraphUnderGate({String? splitId}) async {
    final owner = trainingCacheOwner();
    final graph = TrainingBlockMigration.prepareGraph(
      readTrainingGraph(ownerId: owner).ownedBy(owner),
    );
    final cleared = graph.clearWorkouts(splitId: splitId);
    await TrainingBlockRestore().replaceUnderGate(
      graph: cleared,
      stampRecords: false,
    );
  }

  static Future<void> replaceAllWorkoutData({
    required String? userId,
    required List<Split> splits,
    required String activeSplitId,
    required List<WorkoutPlan> plans,
    required List<WorkoutSession> sessions,
    List<TrainingBlock> blocks = const [],
    List<TrainingWeek> weeks = const [],
    List<WorkoutProgress> progress = const [],
    String? operationId,
    Map<String, dynamic> settings = const {},
  }) => TrainingBlockRestore().replace(
    graph: TrainingBlockGraph(
      ownerId: userId,
      activeSplitId: activeSplitId,
      splits: splits,
      plans: plans,
      sessions: sessions,
      blocks: blocks,
      weeks: weeks,
      progress: progress,
    ),
    settings: settings,
    operationId: operationId,
  );
}
