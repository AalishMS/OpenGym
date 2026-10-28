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
import 'sync_service.dart';

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
      final sessions = HiveService.getAllSessionsRaw();
      final count = sessions.length;
      // Validate all supplied links before any graph mutation.
      _validateGraph(sessions, ownerId);
      final splits = HiveService.getAllSplitsRaw();
      final blocks = {
        for (final b in HiveService.getAllTrainingBlocksRaw()) b.id: b,
      };
      final weeks = {
        for (final w in HiveService.getAllTrainingWeeksRaw()) w.id: w,
      };
      for (final split in splits) {
        final legacy =
            sessions
                .where((s) => s.splitId == split.id && s.trainingWeekId == null)
                .toList();
        final blockId = legacyTrainingBlockId(split.id);
        final hasStructure = blocks.values.any(
          (b) => b.splitId == split.id && b.deletedAt == null,
        );
        if (legacy.isEmpty && hasStructure) continue;
        final deleted = split.deletedAt;
        final existing = blocks[blockId];
        if (existing?.deletedAt != null && deleted == null) {
          throw StateError('Legacy data refers to a deleted block.');
        }
        final block =
            existing ??
            TrainingBlock(
              id: blockId,
              splitId: split.id,
              name: 'Block 1',
              position: 0,
              createdAt: split.createdAt,
              updatedAt: split.updatedAt,
              deletedAt: deleted,
              userId: ownerId,
              dirty: true,
            );
        if (existing == null) {
          await HiveService.putTrainingBlockRaw(block);
          blocks[block.id] = block;
        }
        final numbers = legacy.map((s) => s.weekNumber).toSet();
        if (numbers.isEmpty && !weeks.values.any((w) => w.blockId == blockId)) {
          numbers.add(1);
        }
        for (final number in numbers.toList()..sort()) {
          final id = legacyTrainingWeekId(split.id, number);
          final existingWeek = weeks[id];
          if (existingWeek?.deletedAt != null && deleted == null) {
            throw StateError('Legacy data refers to a deleted week.');
          }
          // Deterministic legacy labels take precedence over random additions.
          // Preserve random IDs and all linked values while rebasing their label.
          final conflicts =
              weeks.values
                  .where(
                    (w) =>
                        w.blockId == blockId &&
                        w.number == number &&
                        w.id != id &&
                        w.deletedAt == null,
                  )
                  .toList()
                ..sort((a, b) => a.id.compareTo(b.id));
          for (final conflict in conflicts) {
            var max = number;
            for (final w in weeks.values.where(
              (w) => w.blockId == blockId && w.deletedAt == null,
            )) {
              if (w.number > max) max = w.number;
            }
            for (final n in numbers) {
              if (n > max) max = n;
            }
            final rebased = conflict.copyWith(number: max + 1, dirty: true);
            await HiveService.putTrainingWeekRaw(rebased);
            weeks[rebased.id] = rebased;
            for (final session in HiveService.getAllSessionsRaw().where(
              (s) => s.trainingWeekId == rebased.id,
            )) {
              await HiveService.putSessionRaw(
                session.copyWith(weekNumber: rebased.number, dirty: true),
              );
            }
          }
          if (existingWeek == null) {
            final week = TrainingWeek(
              id: id,
              splitId: split.id,
              blockId: blockId,
              number: number,
              createdAt: split.createdAt,
              updatedAt: split.updatedAt,
              deletedAt: deleted,
              userId: ownerId,
              dirty: true,
            );
            await HiveService.putTrainingWeekRaw(week);
            weeks[id] = week;
          }
        }
      }
      await HiveService.flushTrainingData();
      await checkpoint(_ownerKey(ownerId), journal, 'parents');
      final plans = HiveService.getAllPlansRaw();
      for (final old in HiveService.getAllSessionsRaw()) {
        if (old.trainingWeekId != null) continue;
        var planId = old.planId;
        if (planId == null) {
          final matches =
              plans
                  .where(
                    (p) =>
                        p.splitId == old.splitId &&
                        p.userId == ownerId &&
                        p.name == old.planName,
                  )
                  .toList();
          if (matches.length == 1) planId = matches.single.id;
        }
        await HiveService.putSessionRaw(
          old.copyWith(
            planId: planId,
            trainingWeekId: legacyTrainingWeekId(old.splitId!, old.weekNumber),
          ),
        );
      }
      await HiveService.flushTrainingData();
      await checkpoint(_ownerKey(ownerId), journal, 'links');
      for (final plan in plans.where((p) => p.deletedAt == null)) {
        final splitId = plan.splitId!;
        if (HiveService.progressForPlan(splitId, plan.id!) != null) continue;
        // Never resurrect a deleted progress record during late normalization.
        final progressId = workoutProgressId(splitId, plan.id!);
        if (HiveService.getAllWorkoutProgressRaw().any(
          (p) => p.id == progressId,
        )) {
          continue;
        }
        final split = HiveService.getSplitById(splitId)!;
        if (split.deletedAt != null) continue;
        final suppliedBlocks = HiveService.blocksForSplit(splitId);
        if (suppliedBlocks.isEmpty) throw StateError('No live training block.');
        final available = HiveService.weeksForBlock(
          splitId,
          suppliedBlocks.first.id,
        );
        if (available.isEmpty) throw StateError('No supplied training weeks.');
        final logs =
            HiveService.getSessions(splitId: splitId)
                .where(
                  (s) =>
                      s.planId == plan.id &&
                      available.any((w) => w.id == s.trainingWeekId),
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
        await HiveService.putWorkoutProgressRaw(
          WorkoutProgress(
            id: progressId,
            splitId: splitId,
            planId: plan.id!,
            activeWeekId: active,
            state: state,
            revision: initialProgressRevision(splitId, plan.id!),
            userId: ownerId,
            updatedAt: plan.updatedAt,
            dirty: true,
          ),
        );
      }
      await HiveService.flushTrainingData();
      await checkpoint(_ownerKey(ownerId), journal, 'progress');
      _validateGraph(HiveService.getAllSessionsRaw(), ownerId);
      if (HiveService.getAllSessionsRaw().length != count ||
          HiveService.getAllSessionsRaw().any(
            (s) => s.trainingWeekId == null,
          )) {
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

  void _validateGraph(List<WorkoutSession> sessions, String? ownerId) {
    final splits = {for (final s in HiveService.getAllSplitsRaw()) s.id: s};
    final blocks = {
      for (final b in HiveService.getAllTrainingBlocksRaw()) b.id: b,
    };
    final weeks = {
      for (final w in HiveService.getAllTrainingWeeksRaw()) w.id: w,
    };
    final plans = {for (final p in HiveService.getAllPlansRaw()) p.id: p};
    for (final plan in plans.values) {
      if (!splits.containsKey(plan.splitId)) {
        throw StateError('Plan has no owning split.');
      }
    }
    for (final b in blocks.values) {
      final parent = splits[b.splitId];
      if (parent == null ||
          parent.userId != b.userId ||
          (parent.deletedAt != null && b.deletedAt == null)) {
        throw StateError('Conflicting block parent.');
      }
    }
    for (final w in weeks.values) {
      final parent = blocks[w.blockId];
      if (w.number < 1 ||
          parent == null ||
          parent.splitId != w.splitId ||
          parent.userId != w.userId ||
          (parent.deletedAt != null && w.deletedAt == null)) {
        throw StateError('Conflicting week parent.');
      }
    }
    for (final s in sessions) {
      if (s.id == null || !splits.containsKey(s.splitId) || s.weekNumber < 1) {
        throw StateError('Invalid legacy session week or split.');
      }
      final plan = plans[s.planId];
      if (plan != null &&
          (plan.splitId != s.splitId || plan.userId != ownerId)) {
        throw StateError('Conflicting session plan.');
      }
      if (s.trainingWeekId != null) {
        final week = weeks[s.trainingWeekId];
        if (week == null ||
            week.splitId != s.splitId ||
            week.number != s.weekNumber ||
            (week.deletedAt != null && s.deletedAt == null)) {
          throw StateError('Conflicting session week.');
        }
      }
    }
    for (final p in HiveService.getAllWorkoutProgressRaw()) {
      final plan = plans[p.planId];
      final week = weeks[p.activeWeekId];
      if (plan == null ||
          plan.splitId != p.splitId ||
          week == null ||
          week.splitId != p.splitId ||
          (p.deletedAt == null &&
              (week.deletedAt != null || plan.deletedAt != null))) {
        throw StateError('Conflicting workout progress.');
      }
    }
  }
}
