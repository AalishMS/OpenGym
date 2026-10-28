import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../utils/training_block_identity.dart';
import 'hive_service.dart';
import 'training_block_graph.dart';
import 'sync_service.dart';
import 'workout_progression_service.dart';

class TrainingPreparationException implements Exception {
  final Object cause;
  final String? safetySnapshotPath;
  const TrainingPreparationException(this.cause, {this.safetySnapshotPath});

  @override
  String toString() =>
      'Your training data could not be prepared. Retry or export the safety copy. ($cause)';
}

/// The same normalization is used on startup, late legacy delivery, and import.
/// It only inserts missing structure/progress and fills missing session links.
/// It never treats a historical completion as a new progression event.
class TrainingBlockMigration {
  String _ownerKey(String? ownerId) =>
      ownerId == null ? 'offline' : Uri.encodeComponent(ownerId);

  String snapshotPath(String? ownerId) {
    final root =
        File(Hive.box<WorkoutSession>(HiveService.sessionsBox).path!).parent;
    return '${root.path}/training-safety-${_ownerKey(ownerId)}.json';
  }

  Future<void> normalize({required String? ownerId}) => SyncService.instance
      .runExclusiveLocalMutation(() => normalizeUnderGate(ownerId: ownerId));

  /// Used by callers which already own the exclusive local mutation gate.
  Future<void> normalizeUnderGate({required String? ownerId}) async {
    String? path;
    try {
      await HiveService.openTrainingBoxes();
      _validateOwner(ownerId);
      path = snapshotPath(ownerId);
      final prefs = await SharedPreferences.getInstance();
      final key = 'training_migration_${_ownerKey(ownerId)}';
      final saved = prefs.getString(key);
      final journal =
          saved == null
              ? <String, dynamic>{'path': path}
              : Map<String, dynamic>.from(jsonDecode(saved) as Map);
      final file = File(path);
      // A completed normalization may be followed by late legacy inputs.
      // Snapshot those before touching them; pending recovery keeps its original.
      final needsLinks = HiveService.getAllSessionsRaw().any(
        (s) => s.trainingWeekId == null,
      );
      if (!await file.exists() ||
          (journal['phase'] == 'complete' && needsLinks)) {
        final temporary = File('$path.pending');
        await temporary.writeAsString(
          jsonEncode({
            'ownerId': ownerId,
            'splits':
                HiveService.getAllSplitsRaw()
                    .map(
                      (s) => {
                        ...s.toJson(),
                        'userId': s.userId,
                        'dirty': s.dirty,
                      },
                    )
                    .toList(),
            'plans':
                HiveService.getAllPlansRaw()
                    .map(
                      (p) => {
                        ...p.toJson(),
                        'userId': p.userId,
                        'dirty': p.dirty,
                      },
                    )
                    .toList(),
            'sessions':
                HiveService.getAllSessionsRaw()
                    .map(
                      (s) => {
                        ...s.toJson(),
                        'userId': s.userId,
                        'dirty': s.dirty,
                      },
                    )
                    .toList(),
            'blocks':
                HiveService.getAllTrainingBlocksRaw()
                    .map((b) => {...b.toJson(), 'dirty': b.dirty})
                    .toList(),
            'weeks':
                HiveService.getAllTrainingWeeksRaw()
                    .map((w) => {...w.toJson(), 'dirty': w.dirty})
                    .toList(),
            'progress':
                HiveService.getAllWorkoutProgressRaw()
                    .map((p) => {...p.toJson(), 'dirty': p.dirty})
                    .toList(),
            'operations': Hive.box<dynamic>(
              HiveService.trainingOperationsBox,
            ).toMap().map((key, value) => MapEntry(key.toString(), value)),
          }),
          flush: true,
        );
        await temporary.rename(path);
      }
      await checkpoint(_ownerKey(ownerId), journal, 'snapshot');
      await HiveService.recoverTrainingWeekRebase(ownerId: ownerId);
      final count = HiveService.getAllSessionsRaw().length;
      final prepared = prepareGraph(_readGraph(ownerId));
      for (final block in prepared.blocks) {
        final old = HiveService.getTrainingBlockById(block.id);
        if (old == null ||
            jsonEncode(old.toJson()) != jsonEncode(block.toJson())) {
          await HiveService.putTrainingBlockRaw(block);
        }
      }
      for (final week in prepared.weeks) {
        final old = HiveService.getTrainingWeekById(week.id);
        if (old != null && old.number != week.number) {
          await HiveService.persistTrainingWeekRebase(week, ownerId: ownerId);
        } else if (old == null ||
            jsonEncode(old.toJson()) != jsonEncode(week.toJson())) {
          await HiveService.putTrainingWeekRaw(week);
        }
      }
      await HiveService.flushTrainingData();
      await checkpoint(_ownerKey(ownerId), journal, 'parents');
      for (final plan in prepared.plans) {
        final old = HiveService.getPlanById(plan.id!);
        if (old == null ||
            jsonEncode(old.toJson()) != jsonEncode(plan.toJson())) {
          await HiveService.putPlanRaw(plan);
        }
      }
      for (final session in prepared.sessions) {
        final old = HiveService.getSessionById(session.id!);
        if (old == null ||
            jsonEncode(old.toJson()) != jsonEncode(session.toJson())) {
          await HiveService.putSessionRaw(session);
        }
      }
      await HiveService.flushTrainingData();
      await checkpoint(_ownerKey(ownerId), journal, 'links');
      for (final value in prepared.progress) {
        final old = HiveService.getWorkoutProgressById(value.id);
        if (old == null ||
            jsonEncode(old.toJson()) != jsonEncode(value.toJson())) {
          await HiveService.putWorkoutProgressRaw(value);
        }
      }
      await HiveService.flushTrainingData();
      await checkpoint(_ownerKey(ownerId), journal, 'progress');
      _readGraph(ownerId).validate();
      if (HiveService.getAllSessionsRaw().length != count) {
        throw StateError('Training verification failed.');
      }
      await HiveService.flushTrainingData();
      await checkpoint(_ownerKey(ownerId), journal, 'verification');
      await HiveService.recoverTrainingOperation(ownerId: ownerId);
      await checkpoint(_ownerKey(ownerId), journal, 'complete');
    } catch (error) {
      throw TrainingPreparationException(error, safetySnapshotPath: path);
    }
  }

  /// Flush phase metadata separately from the safety copy. Overridable by
  /// storage integrations which need a different journal backend.
  Future<void> checkpoint(
    String owner,
    Map<String, dynamic> journal,
    String phase,
  ) async {
    journal['phase'] = phase;
    await (await SharedPreferences.getInstance()).setString(
      'training_migration_$owner',
      jsonEncode(journal),
    );
  }

  static TrainingBlockGraph prepareGraph(TrainingBlockGraph input) {
    input.validate(
      allowLegacyLinks: true,
      allowLiveChildrenOfDeletedParents: true,
    );
    final splits = {for (final s in input.splits) s.id: s};
    final plans = {for (final p in input.plans) p.id!: p.copyWith()};
    final blocks = {for (final b in input.blocks) b.id: b.copyWith()};
    final weeks = {for (final w in input.weeks) w.id: w.copyWith()};
    final sessions = {for (final s in input.sessions) s.id!: s.copyWith()};
    final progress = {for (final p in input.progress) p.id: p.copyWith()};
    DateTime stamp(DateTime? child, DateTime? parent, DateTime deletion) =>
        child != null && child.isAfter(parent ?? deletion)
            ? child
            : parent ?? deletion;
    // A parent tombstone is a durable outcome, including after interruption.
    for (final p in plans.values.toList()) {
      final parent = splits[p.splitId]!;
      if (parent.deletedAt != null && p.deletedAt == null) {
        plans[p.id!] = p.copyWith(
          deletedAt: parent.deletedAt,
          updatedAt: stamp(p.updatedAt, parent.updatedAt, parent.deletedAt!),
          dirty: true,
        );
      }
    }
    for (final b in blocks.values.toList()) {
      final parent = splits[b.splitId]!;
      if (parent.deletedAt != null && b.deletedAt == null) {
        blocks[b.id] = b.copyWith(
          deletedAt: parent.deletedAt,
          updatedAt: stamp(b.updatedAt, parent.updatedAt, parent.deletedAt!),
          dirty: true,
        );
      }
    }
    for (final w in weeks.values.toList()) {
      final parent = blocks[w.blockId]!;
      if (parent.deletedAt != null && w.deletedAt == null) {
        weeks[w.id] = w.copyWith(
          deletedAt: parent.deletedAt,
          updatedAt: stamp(w.updatedAt, parent.updatedAt, parent.deletedAt!),
          dirty: true,
        );
      }
    }
    for (final s in sessions.values.toList()) {
      final parent = splits[s.splitId]!;
      final week = weeks[s.trainingWeekId];
      final deleted = parent.deletedAt ?? week?.deletedAt;
      if (deleted != null && s.deletedAt == null) {
        sessions[s.id!] = s.copyWith(
          deletedAt: deleted,
          updatedAt: stamp(s.updatedAt, parent.updatedAt, deleted),
          dirty: true,
        );
      }
    }
    for (final p in progress.values.toList()) {
      final parent = plans[p.planId]!;
      final week = weeks[p.activeWeekId]!;
      final deleted = parent.deletedAt ?? week.deletedAt;
      if (deleted != null && p.deletedAt == null) {
        progress[p.id] = p.copyWith(
          deletedAt: deleted,
          updatedAt: stamp(p.updatedAt, parent.updatedAt, deleted),
          dirty: true,
        );
      }
    }
    for (final split in splits.values) {
      final legacy =
          sessions.values
              .where((s) => s.splitId == split.id && s.trainingWeekId == null)
              .toList();
      final existing =
          blocks.values.where((b) => b.splitId == split.id).toList();
      if (legacy.isEmpty && existing.isNotEmpty) continue;
      final id = legacyTrainingBlockId(split.id);
      if (blocks[id]?.deletedAt != null && split.deletedAt == null) {
        throw const FormatException(
          'A deleted legacy block cannot be restored.',
        );
      }
      blocks.putIfAbsent(
        id,
        () => TrainingBlock(
          id: id,
          splitId: split.id,
          name: 'Block 1',
          position: 0,
          createdAt: split.createdAt,
          deletedAt: split.deletedAt,
          userId: input.ownerId,
          dirty: true,
        ),
      );
      final numbers = legacy.map((s) => s.weekNumber).toSet();
      if (numbers.isEmpty && !weeks.values.any((w) => w.blockId == id)) {
        numbers.add(1);
      }
      for (final number in numbers.toList()..sort()) {
        final weekId = legacyTrainingWeekId(split.id, number);
        if (weeks[weekId]?.deletedAt != null && split.deletedAt == null) {
          throw const FormatException(
            'A deleted legacy week cannot be restored.',
          );
        }
        final conflicts =
            weeks.values
                .where(
                  (w) =>
                      w.blockId == id &&
                      w.number == number &&
                      w.id != weekId &&
                      w.deletedAt == null,
                )
                .toList()
              ..sort((a, b) => a.id.compareTo(b.id));
        for (final conflict in conflicts) {
          var highest = number;
          for (final w in weeks.values.where(
            (w) => w.blockId == id && w.deletedAt == null,
          )) {
            if (w.number > highest) highest = w.number;
          }
          for (final n in numbers) {
            if (n > highest) highest = n;
          }
          final rebased = conflict.copyWith(number: highest + 1, dirty: true);
          weeks[rebased.id] = rebased;
          for (final s
              in sessions.values
                  .where((s) => s.trainingWeekId == rebased.id)
                  .toList()) {
            sessions[s.id!] = s.copyWith(
              weekNumber: rebased.number,
              dirty: true,
            );
          }
        }
        weeks.putIfAbsent(
          weekId,
          () => TrainingWeek(
            id: weekId,
            splitId: split.id,
            blockId: id,
            number: number,
            createdAt: split.createdAt,
            deletedAt: split.deletedAt,
            userId: input.ownerId,
            dirty: true,
          ),
        );
      }
    }
    for (final s in sessions.values.toList()) {
      if (s.trainingWeekId != null) continue;
      var planId = s.planId;
      if (planId == null) {
        final matches =
            plans.values
                .where((p) => p.splitId == s.splitId && p.name == s.planName)
                .toList();
        if (matches.length == 1) planId = matches.single.id;
      }
      sessions[s.id!] = s.copyWith(
        planId: planId,
        trainingWeekId: legacyTrainingWeekId(s.splitId!, s.weekNumber),
      );
    }
    int blockOrder(TrainingBlock a, TrainingBlock b) {
      final order = a.position.compareTo(b.position);
      return order == 0 ? a.id.compareTo(b.id) : order;
    }

    int weekOrder(TrainingWeek a, TrainingWeek b) {
      final order = a.number.compareTo(b.number);
      return order == 0 ? a.id.compareTo(b.id) : order;
    }

    for (final plan in plans.values.where((p) => p.deletedAt == null)) {
      if (progress.values.any((p) => p.planId == plan.id)) continue;
      final split = splits[plan.splitId]!;
      if (split.deletedAt != null) continue;
      final suppliedBlocks =
          blocks.values
              .where((b) => b.splitId == plan.splitId && b.deletedAt == null)
              .toList()
            ..sort(blockOrder);
      if (suppliedBlocks.isEmpty) {
        throw const FormatException('No live training block.');
      }
      final available =
          weeks.values
              .where(
                (w) =>
                    w.blockId == suppliedBlocks.first.id && w.deletedAt == null,
              )
              .toList()
            ..sort(weekOrder);
      if (available.isEmpty) {
        throw const FormatException('No supplied training week.');
      }
      final availableIds = available.map((w) => w.id).toSet();
      final logs =
          sessions.values
              .where(
                (s) =>
                    s.planId == plan.id &&
                    s.splitId == plan.splitId &&
                    s.deletedAt == null &&
                    availableIds.contains(s.trainingWeekId),
              )
              .toList();
      final drafts =
          logs.where((s) => !s.isCompleted).toList()..sort((a, b) {
            if (a.isTimerRunning != b.isTimerRunning) {
              return a.isTimerRunning ? -1 : 1;
            }
            return compareSessionRecency(b, a);
          });
      var active = available.first.id;
      var state = WorkoutProgressState.ready;
      if (drafts.isNotEmpty) {
        active = drafts.first.trainingWeekId!;
      } else {
        final done = logs.where((s) => s.isCompleted).toList();
        if (done.isNotEmpty) {
          final highest = done
              .map((s) => s.weekNumber)
              .reduce((a, b) => a > b ? a : b);
          final next = available.where((w) => w.number > highest).toList();
          active = next.isEmpty ? available.last.id : next.first.id;
          if (next.isEmpty) state = WorkoutProgressState.awaitingBoundary;
        }
      }
      final id = workoutProgressId(plan.splitId!, plan.id!);
      progress[id] = WorkoutProgress(
        id: id,
        splitId: plan.splitId!,
        planId: plan.id!,
        activeWeekId: active,
        state: state,
        revision: initialProgressRevision(plan.splitId!, plan.id!),
        userId: input.ownerId,
        dirty: true,
      );
    }
    final graph = input.copyWith(
      plans: plans.values.toList(),
      sessions: sessions.values.toList(),
      blocks: blocks.values.toList(),
      weeks: weeks.values.toList(),
      progress: progress.values.toList(),
    );
    graph.validate();
    return WorkoutProgressionService.reconcileGraph(graph);
  }

  static int compareSessionRecency(WorkoutSession a, WorkoutSession b) {
    final update = (a.updatedAt ?? a.date).compareTo(b.updatedAt ?? b.date);
    if (update != 0) return update;
    final date = a.date.compareTo(b.date);
    return date == 0 ? (a.id ?? '').compareTo(b.id ?? '') : date;
  }

  void _validateOwner(String? ownerId) {
    final owners = [
      ...HiveService.getAllSplitsRaw().map((s) => s.userId),
      ...HiveService.getAllPlansRaw().map((p) => p.userId),
      ...HiveService.getAllSessionsRaw().map((s) => s.userId),
      ...HiveService.getAllTrainingBlocksRaw().map((b) => b.userId),
      ...HiveService.getAllTrainingWeeksRaw().map((w) => w.userId),
      ...HiveService.getAllWorkoutProgressRaw().map((p) => p.userId),
    ];
    if (owners.any((owner) => owner != ownerId)) {
      throw StateError('This cache belongs to a different account.');
    }
  }

  static TrainingBlockGraph _readGraph(String? owner) => TrainingBlockGraph(
    ownerId: owner,
    splits: HiveService.getAllSplitsRaw(),
    plans: HiveService.getAllPlansRaw(),
    sessions: HiveService.getAllSessionsRaw(),
    blocks: HiveService.getAllTrainingBlocksRaw(),
    weeks: HiveService.getAllTrainingWeeksRaw(),
    progress: HiveService.getAllWorkoutProgressRaw(),
  );
}
