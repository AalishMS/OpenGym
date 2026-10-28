import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/workout_session.dart';
import '../models/split_preference.dart';
import 'hive_service.dart';
import 'sync_service.dart';
import 'training_block_graph.dart';
import 'training_block_migration.dart';
import 'workout_progression_service.dart';

/// Fixed, validated replacement plus its original safety copy. Replaying a
/// pending replacement never allocates IDs or recomputes its intended values.
class TrainingBlockRestore {
  static final recoveryFailure = ValueNotifier<TrainingPreparationException?>(
    null,
  );
  static String? recoveryOwnerId;
  void _ready(String? owner) {
    if (recoveryFailure.value == null || recoveryOwnerId == owner) {
      recoveryFailure.value = null;
    }
  }

  final Future<void> Function(String phase)? onPhase;
  TrainingBlockRestore({this.onPhase});

  /// Explicit failures can undo a batch while its exclusive gate is held.
  /// A process death instead leaves the fixed desired graph for roll-forward.
  Future<void> rollbackUnderGate(String? ownerId) async {
    final file = File(snapshotPath(ownerId));
    final payload = Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
    if (payload['ownerId'] != ownerId) {
      throw StateError('Conflicting rollback owner.');
    }
    final original = TrainingBlockGraph.fromJson(
      Map<String, dynamic>.from(payload['original'] as Map),
    );
    await HiveService.clearAllPlans();
    await HiveService.clearAllSessions();
    await HiveService.clearSplitData();
    await HiveService.clearTrainingData();
    for (final row in original.splits) {
      await HiveService.putSplitRaw(row);
    }
    for (final row in original.blocks) {
      await HiveService.putTrainingBlockRaw(row);
    }
    for (final row in original.weeks) {
      await HiveService.putTrainingWeekRaw(row);
    }
    for (final row in original.plans) {
      await HiveService.putPlanRaw(row);
    }
    for (final row in original.sessions) {
      await HiveService.putSessionRaw(row);
    }
    for (final row in original.progress) {
      await HiveService.putWorkoutProgressRaw(row);
    }
    for (final dynamic row in payload['originalPreferences'] as List) {
      final value = Map<String, dynamic>.from(row as Map);
      await HiveService.putSplitPreferenceRaw(
        SplitPreference(
          userId: value['userId'] as String,
          activeSplitId: value['activeSplitId'] as String,
          updatedAt:
              value['updatedAt'] == null
                  ? null
                  : DateTime.parse(value['updatedAt'] as String),
          dirty: value['dirty'] as bool?,
        ),
      );
    }
    await Hive.box<dynamic>(
      HiveService.trainingOperationsBox,
    ).putAll(Map<String, dynamic>.from(payload['originalOperations'] as Map));
    await HiveService.flushAllWorkoutData();
    await (await SharedPreferences.getInstance()).remove(_pendingKey(ownerId));
    _ready(ownerId);
  }

  String _ownerKey(String? owner) =>
      owner == null ? 'offline' : Uri.encodeComponent(owner);
  String _pendingKey(String? owner) =>
      'training_restore_pending_${_ownerKey(owner)}';
  String snapshotPath(String? owner) =>
      '${File(Hive.box<WorkoutSession>(HiveService.sessionsBox).path!).parent.path}/training-restore-${_ownerKey(owner)}.json';

  /// Only known, owner-scoped recovery artifacts; never scan arbitrary files.
  Future<void> removeOwnerRecovery(String? ownerId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final path in [
      snapshotPath(ownerId),
      TrainingBlockMigration().snapshotPath(ownerId),
    ]) {
      for (final candidate in [path, '$path.pending']) {
        final file = File(candidate);
        if (await file.exists()) await file.delete();
      }
    }
    await prefs.remove(_pendingKey(ownerId));
    await prefs.remove('training_migration_${_ownerKey(ownerId)}');
    _ready(ownerId);
  }

  Future<void> replace({
    required TrainingBlockGraph graph,
    Map<String, dynamic> settings = const {},
    String? operationId,
    bool stampRecords = true,
  }) => SyncService.instance.runExclusiveLocalMutation(
    () => replaceUnderGate(
      graph: graph,
      settings: settings,
      operationId: operationId,
      stampRecords: stampRecords,
    ),
  );

  Future<void> replaceUnderGate({
    required TrainingBlockGraph graph,
    Map<String, dynamic> settings = const {},
    String? operationId,
    bool stampRecords = true,
  }) async {
    try {
      await _replaceUnderGate(
        graph: graph,
        settings: settings,
        operationId: operationId,
        stampRecords: stampRecords,
      );
      _ready(graph.ownerId);
    } catch (error) {
      if ((await SharedPreferences.getInstance()).containsKey(
        _pendingKey(graph.ownerId),
      )) {
        recoveryOwnerId = graph.ownerId;
        recoveryFailure.value = TrainingPreparationException(
          error,
          safetySnapshotPath: snapshotPath(graph.ownerId),
        );
      }
      rethrow;
    }
  }

  Future<void> _replaceUnderGate({
    required TrainingBlockGraph graph,
    required Map<String, dynamic> settings,
    required String? operationId,
    required bool stampRecords,
  }) async {
    graph.validate();
    validateSettings(settings);
    final owner = graph.ownerId;
    final prefs = await SharedPreferences.getInstance();
    final cachedOwner = prefs.getString('lastUserId');
    if (cachedOwner != null && cachedOwner != owner) {
      throw StateError('The account changed before replacement.');
    }
    final id = operationId ?? const Uuid().v4();
    final file = File(snapshotPath(owner));
    if (await file.exists()) {
      final saved = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      if (saved['operationId'] == id) {
        if (saved['ownerId'] != owner) {
          throw StateError('The replacement belongs to another account.');
        }
        await _apply(saved);
        return;
      }
    }
    await recover(ownerId: owner);
    final original = HiveService.readTrainingGraph(ownerId: owner);
    original.validate(
      allowLegacyLinks: true,
      allowLiveChildrenOfDeletedParents: true,
      allowUnowned: true,
    );
    var imported = WorkoutProgressionService.reconcileGraph(graph);
    // Tombstone identities are never revived on the server. Copying a backup
    // over a deleted graph creates a new graph, retaining all visible values.
    bool resurrects(Iterable<dynamic> old, Iterable<dynamic> next) {
      final deleted = {
        for (final dynamic row in old)
          if (row.deletedAt != null) row.id,
      };
      return next.any(
        (dynamic row) => row.deletedAt == null && deleted.contains(row.id),
      );
    }

    if (resurrects(original.splits, graph.splits) ||
        resurrects(original.plans, graph.plans) ||
        resurrects(original.sessions, graph.sessions) ||
        resurrects(original.blocks, graph.blocks) ||
        resurrects(original.weeks, graph.weeks) ||
        resurrects(original.progress, graph.progress)) {
      imported = imported.remap(ownerId: owner);
    }
    final now = DateTime.now();
    if (stampRecords) {
      imported = imported.copyWith(
        splits: [
          for (final r in imported.splits)
            r.copyWith(updatedAt: now, dirty: true),
        ],
        plans: [
          for (final r in imported.plans)
            r.copyWith(updatedAt: now, dirty: true),
        ],
        sessions: [
          for (final r in imported.sessions)
            r.copyWith(updatedAt: now, dirty: true),
        ],
        blocks: [
          for (final r in imported.blocks)
            r.copyWith(updatedAt: now, dirty: true),
        ],
        weeks: [
          for (final r in imported.weeks)
            r.copyWith(updatedAt: now, dirty: true),
        ],
        progress: [
          for (final r in imported.progress)
            r.copyWith(updatedAt: now, dirty: true),
        ],
      );
    }
    List<T> merge<T>(
      List<T> old,
      List<T> next,
      String Function(T) key,
      T Function(T) tombstone,
    ) {
      final result = {for (final row in next) key(row): row};
      for (final row in old) {
        result.putIfAbsent(key(row), () => tombstone(row));
      }
      return result.values.toList();
    }

    final desired = imported.copyWith(
      splits: merge(
        original.splits,
        imported.splits,
        (r) => r.id,
        (r) =>
            r.deletedAt != null
                ? r
                : r.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      ),
      plans: merge(
        original.plans,
        imported.plans,
        (r) => r.id!,
        (r) =>
            r.deletedAt != null
                ? r
                : r.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      ),
      sessions: merge(
        original.sessions,
        imported.sessions,
        (r) => r.id!,
        (r) =>
            r.deletedAt != null
                ? r
                : r.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      ),
      blocks: merge(
        original.blocks,
        imported.blocks,
        (r) => r.id,
        (r) =>
            r.deletedAt != null
                ? r
                : r.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      ),
      weeks: merge(
        original.weeks,
        imported.weeks,
        (r) => r.id,
        (r) =>
            r.deletedAt != null
                ? r
                : r.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      ),
      progress: merge(
        original.progress,
        imported.progress,
        (r) => r.id,
        (r) =>
            r.deletedAt != null
                ? r
                : r.copyWith(deletedAt: now, updatedAt: now, dirty: true),
      ),
    );
    desired.validate();
    final payload = <String, dynamic>{
      'ownerId': owner,
      'operationId': id,
      'path': file.path,
      'original': original.toJson(),
      'desired': desired.toJson(),
      'settings': settings,
      'preferenceUpdatedAt': now.toIso8601String(),
      'originalPreferences':
          HiveService.getAllSplitPreferencesRaw()
              .map(
                (p) => {
                  'userId': p.userId,
                  'activeSplitId': p.activeSplitId,
                  'updatedAt': p.updatedAt?.toIso8601String(),
                  'dirty': p.dirty,
                },
              )
              .toList(),
      'desiredOperations': <String, dynamic>{},
      'originalOperations': Hive.box<dynamic>(
        HiveService.trainingOperationsBox,
      ).toMap().map((key, value) => MapEntry(key.toString(), value)),
      'originalSettings': {
        for (final key in [
          'theme_mode',
          'accent_color',
          'weight_unit',
          'auto_fill_last',
        ])
          key: prefs.get(key),
      },
    };
    await File(
      '${file.path}.pending',
    ).writeAsString(jsonEncode(payload), flush: true);
    await File('${file.path}.pending').rename(file.path);
    await checkpoint(payload, 'snapshot');
    await _apply(payload);
  }

  Future<void> recover({required String? ownerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey(ownerId));
    if (raw == null) return;
    final journal = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (journal['ownerId'] != ownerId ||
        journal['path'] != snapshotPath(ownerId)) {
      throw StateError('Conflicting replacement recovery scope.');
    }
    final payload = Map<String, dynamic>.from(
      jsonDecode(await File(snapshotPath(ownerId)).readAsString()) as Map,
    );
    if (payload['ownerId'] != ownerId ||
        payload['operationId'] != journal['operationId']) {
      throw StateError('Conflicting replacement safety copy.');
    }
    await _apply(payload);
    _ready(ownerId);
  }

  Future<void> _apply(Map<String, dynamic> payload) async {
    final owner = payload['ownerId'] as String?;
    final graph = TrainingBlockGraph.fromJson(
      Map<String, dynamic>.from(payload['desired'] as Map),
    );
    graph.validate();
    if (graph.ownerId != owner) {
      throw StateError('Conflicting replacement owner.');
    }
    // This fixed replacement supersedes prior creation/relabel intents. The
    // original operations remain in the safety payload for explicit rollback.
    final operations = Hive.box<dynamic>(HiveService.trainingOperationsBox);
    await operations.clear();
    await operations.putAll(
      Map<String, dynamic>.from(
        payload['desiredOperations'] as Map? ?? const {},
      ),
    );
    await operations.flush();

    for (final split in graph.splits) {
      await HiveService.putSplitRaw(split);
    }
    for (final block in graph.blocks) {
      await HiveService.putTrainingBlockRaw(block);
    }
    for (final week in graph.weeks) {
      await HiveService.putTrainingWeekRaw(week);
    }
    await HiveService.flushAllWorkoutData();
    await checkpoint(payload, 'parents');
    for (final plan in graph.plans) {
      await HiveService.putPlanRaw(plan);
    }
    await HiveService.flushAllWorkoutData();
    await checkpoint(payload, 'plans');
    for (final session in graph.sessions) {
      await HiveService.putSessionRaw(session);
    }
    await HiveService.flushAllWorkoutData();
    await checkpoint(payload, 'sessions');
    for (final progress in graph.progress) {
      await HiveService.putWorkoutProgressRaw(progress);
    }
    await HiveService.flushAllWorkoutData();
    await checkpoint(payload, 'progress');
    if (graph.activeSplitId case final active?) {
      await HiveService.setActiveSplitForRecovery(
        owner ?? 'local',
        active,
        DateTime.parse(payload['preferenceUpdatedAt'] as String),
      );
    }
    final settings = Map<String, dynamic>.from(payload['settings'] as Map);
    validateSettings(settings);
    final prefs = await SharedPreferences.getInstance();
    Future<void> written(Future<bool> write) async {
      if (!await write) throw StateError('Could not save restored settings.');
    }

    if (settings.containsKey('themeMode')) {
      await written(prefs.setInt('theme_mode', settings['themeMode'] as int));
    }
    if (settings.containsKey('accentIndex')) {
      await written(
        prefs.setInt('accent_color', settings['accentIndex'] as int),
      );
    }
    if (settings.containsKey('weightUnit')) {
      await written(
        prefs.setString('weight_unit', settings['weightUnit'] as String),
      );
    }
    if (settings.containsKey('autoFillLast')) {
      await written(
        prefs.setBool('auto_fill_last', settings['autoFillLast'] as bool),
      );
    }
    await checkpoint(payload, 'settings');
    await HiveService.flushAllWorkoutData();
    HiveService.readTrainingGraph(ownerId: owner).validate();
    await checkpoint(payload, 'complete');
    await prefs.remove(_pendingKey(owner));
  }

  Future<void> checkpoint(Map<String, dynamic> journal, String phase) async {
    await (await SharedPreferences.getInstance()).setString(
      _pendingKey(journal['ownerId'] as String?),
      jsonEncode({
        'ownerId': journal['ownerId'],
        'operationId': journal['operationId'],
        'path': journal['path'],
        'phase': phase,
      }),
    );
    await onPhase?.call(phase);
  }

  static void validateSettings(Map<String, dynamic> values) {
    if (values.containsKey('themeMode') &&
        (values['themeMode'] is! int ||
            (values['themeMode'] as int) < 0 ||
            (values['themeMode'] as int) > 2)) {
      throw const FormatException('Invalid backup theme.');
    }
    if (values.containsKey('accentIndex') &&
        (values['accentIndex'] is! int ||
            (values['accentIndex'] as int) < 0 ||
            (values['accentIndex'] as int) > 7)) {
      throw const FormatException('Invalid backup accent.');
    }
    if (values.containsKey('weightUnit') &&
        !['kg', 'lb'].contains(values['weightUnit'])) {
      throw const FormatException('Invalid backup weight unit.');
    }
    if (values.containsKey('autoFillLast') && values['autoFillLast'] is! bool) {
      throw const FormatException('Invalid backup auto-fill setting.');
    }
  }
}
