import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import '../models/training_block.dart';

import '../models/completion_transition.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../utils/training_block_identity.dart';
import 'hive_service.dart';
import 'supabase_service.dart';
import 'sync_service.dart';
import 'training_block_graph.dart';
import 'workout_completion_service.dart';

/// Session evidence and progress are separate durable writes. A successful
/// completion stays successful when its progress write needs recovery.
class WorkoutProgressionService {
  final String? Function() _owner;
  final DateTime Function() _clock;
  final Future<void> Function(WorkoutSession) _writeSession;
  final Future<void> Function(WorkoutProgress) _writeProgress;
  static const _uuid = Uuid();

  WorkoutProgressionService({
    String? Function()? ownerId,
    DateTime Function()? clock,
    Future<void> Function(WorkoutSession)? writeSession,
    Future<void> Function(WorkoutProgress)? writeProgress,
  }) : _owner = ownerId ?? (() => SupabaseService.currentUserId),
       _clock = clock ?? DateTime.now,
       _writeSession = writeSession ?? HiveService.putSessionRaw,
       _writeProgress = writeProgress ?? HiveService.putWorkoutProgressRaw;

  static WorkoutProgress? applyCompletion(
    WorkoutProgress progress,
    WorkoutSession completed,
  ) {
    if (!completed.isCompleted ||
        completed.completionTransition == null ||
        progress.deletedAt != null ||
        progress.state != WorkoutProgressState.ready ||
        progress.planId != completed.planId ||
        progress.splitId != completed.splitId ||
        progress.userId != completed.userId) {
      return null;
    }
    final event = CompletionTransition.fromJson(
      completed.completionTransition!,
    );
    if (event.resultRevision != completed.id ||
        event.sourceWeekId != completed.trainingWeekId ||
        progress.revision != event.expectedRevision ||
        progress.activeWeekId != event.sourceWeekId) {
      return null;
    }
    return progress.copyWith(
      activeWeekId: event.nextWeekId ?? event.sourceWeekId,
      availableWeekIds:
          {
            ...?progress.availableWeekIds,
            event.sourceWeekId,
            if (event.nextWeekId != null) event.nextWeekId!,
          }.toList(),
      state:
          event.nextWeekId == null
              ? WorkoutProgressState.awaitingBoundary
              : WorkoutProgressState.ready,
      revision: event.resultRevision,
      updatedAt: event.committedAt,
      dirty: true,
    );
  }

  /// Reconcile only recorded events. Multiple passes handle evidence chains
  /// whose clocks sort out of causal order; each pass is bounded by log count.
  static TrainingBlockGraph reconcileGraph(TrainingBlockGraph graph) {
    final progress = {for (final p in graph.progress) p.id: p};
    final weeks = {for (final w in graph.weeks) w.id: w};
    final evidence =
        graph.sessions
            .where((s) => s.isCompleted && s.completionTransition != null)
            .toList()
          ..sort((a, b) {
            final left = CompletionTransition.fromJson(a.completionTransition!);
            final right = CompletionTransition.fromJson(
              b.completionTransition!,
            );
            final order = left.committedAt.compareTo(right.committedAt);
            return order == 0 ? a.id!.compareTo(b.id!) : order;
          });
    for (var pass = 0; pass < evidence.length; pass++) {
      var changed = false;
      for (final session in evidence) {
        final event = CompletionTransition.fromJson(
          session.completionTransition!,
        );
        final source = weeks[event.sourceWeekId];
        final target = weeks[event.nextWeekId];
        if (source == null ||
            (event.nextWeekId != null &&
                (target == null ||
                    target.blockId != source.blockId ||
                    target.number <= source.number))) {
          continue;
        }
        for (final p in progress.values.toList().where(
          (p) => p.planId == session.planId && p.splitId == session.splitId,
        )) {
          final next = applyCompletion(p, session);
          if (next != null) {
            progress[p.id] = next;
            changed = true;
          }
        }
      }
      if (!changed) break;
    }
    return graph.copyWith(progress: progress.values.toList());
  }

  Future<void> replay() =>
      SyncService.instance.runExclusiveLocalMutation(replayUnderGate);

  Future<void> replayUnderGate() async {
    await recoverBoundaryUnderGate(ownerId: _owner());
    final before = HiveService.readTrainingGraph(ownerId: _owner());
    before.validate();
    final next = reconcileGraph(before);
    final originals = {for (final p in before.progress) p.id: p};
    for (final p in next.progress) {
      if (p.revision != originals[p.id]!.revision) await _writeProgress(p);
    }
  }

  WorkoutSession _session(String id) {
    final session = HiveService.getSessionById(id);
    if (session == null ||
        session.deletedAt != null ||
        session.userId != _owner() ||
        session.splitId == null) {
      throw StateError('The workout is unavailable in this account.');
    }
    HiveService.validateTrainingSplit(session.splitId!, _owner());
    return session;
  }

  TrainingWeek? _nextInBlock(WorkoutProgress progress) {
    final source = HiveService.getTrainingWeekById(progress.activeWeekId);
    if (source == null || source.deletedAt != null) {
      throw StateError('The active week is unavailable.');
    }
    final weeks = HiveService.weeksForBlock(progress.splitId, source.blockId);
    final block = HiveService.getTrainingBlockById(source.blockId)!;
    final limit = block.plannedWeekCount ?? weeks.last.number;
    return weeks
        .where((w) => w.number == source.number + 1 && w.number <= limit)
        .firstOrNull;
  }

  Future<TrainingWeek?> _ensureNextInBlock(WorkoutProgress progress) async {
    final source = HiveService.getTrainingWeekById(progress.activeWeekId)!;
    final block = HiveService.validateTrainingBlock(
      progress.splitId,
      source.blockId,
      _owner(),
    );
    final weeks = HiveService.weeksForBlock(progress.splitId, source.blockId);
    final limit = block.plannedWeekCount ?? weeks.last.number;
    if (source.number >= limit) return null;
    final supplied = _nextInBlock(progress);
    if (supplied != null) return supplied;
    final now = _clock();
    final week = TrainingWeek(
      id: lazyTrainingWeekId(
        progress.splitId,
        source.blockId,
        source.number + 1,
      ),
      splitId: progress.splitId,
      blockId: source.blockId,
      number: source.number + 1,
      createdAt: now,
      updatedAt: now,
      userId: _owner(),
      dirty: true,
    );
    final existing = HiveService.getTrainingWeekById(week.id);
    if (existing != null) {
      if (existing.deletedAt != null ||
          existing.blockId != source.blockId ||
          existing.number != week.number) {
        throw StateError('The next training week changed. Open it again.');
      }
      return existing;
    }
    // Allocate before writing completion evidence. An interruption leaves an
    // invisible slot, never a completed workout or another plan's next week.
    await HiveService.putTrainingWeekRaw(week);
    await HiveService.flushTrainingData();
    return week;
  }

  Future<WorkoutCompletionResult> complete(String sessionId) =>
      SyncService.instance.runExclusiveLocalMutation(() async {
        final draft = _session(sessionId);
        if (draft.isCompleted) {
          var pending = false;
          try {
            await replayUnderGate();
          } catch (_) {
            pending = true;
          }
          return WorkoutCompletionResult(
            session: draft,
            personalRecords: const [],
            progressPending: pending,
          );
        }
        await replayUnderGate();
        final plan =
            draft.planId == null
                ? null
                : HiveService.getPlanById(draft.planId!);
        final progress =
            draft.planId == null
                ? null
                : HiveService.progressForPlan(draft.splitId!, draft.planId!);
        final now = _clock();
        final active =
            plan != null &&
            plan.deletedAt == null &&
            progress != null &&
            progress.state == WorkoutProgressState.ready &&
            progress.activeWeekId == draft.trainingWeekId;
        final event =
            active
                ? CompletionTransition(
                  expectedRevision: progress.revision,
                  sourceWeekId: progress.activeWeekId,
                  nextWeekId:
                      draft.hasStarted
                          ? (await _ensureNextInBlock(progress))?.id
                          : null,
                  resultRevision: draft.id!,
                  committedAt: now,
                )
                : null;
        final result = await WorkoutCompletionService.complete(
          draft,
          now: now,
          upsert:
              (completed) => _writeSession(
                completed.copyWith(
                  completionTransition: event?.toJson(),
                  updatedAt: now,
                  dirty: true,
                ),
              ),
        );
        final saved = result.session.copyWith(
          completionTransition: event?.toJson(),
          updatedAt: now,
          dirty: true,
        );
        var pending = false;
        if (event != null) {
          try {
            await _writeProgress(applyCompletion(progress!, saved)!);
          } catch (_) {
            pending = true;
          }
        }
        return WorkoutCompletionResult(
          session: saved,
          personalRecords: result.personalRecords,
          progressPending: pending,
        );
      });

  Future<void> continueCompleted({
    required String sessionId,
    required String expectedRevision,
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
    await replayUnderGate();
    final session = _session(sessionId);
    final progress =
        session.planId == null
            ? null
            : HiveService.progressForPlan(session.splitId!, session.planId!);
    if (!session.isCompleted ||
        progress == null ||
        progress.revision != expectedRevision ||
        progress.state != WorkoutProgressState.ready ||
        progress.activeWeekId != session.trainingWeekId ||
        HiveService.sessionsForPlanWeek(
          progress.splitId,
          progress.planId,
          progress.activeWeekId,
        ).any((s) => !s.isCompleted)) {
      throw StateError('The completed slot changed. Open it again.');
    }
    final next = await _ensureNextInBlock(progress);
    await _writeProgress(
      progress.copyWith(
        activeWeekId: next?.id ?? progress.activeWeekId,
        availableWeekIds:
            {
              ...?progress.availableWeekIds,
              progress.activeWeekId,
              if (next != null) next.id,
            }.toList(),
        state:
            next == null
                ? WorkoutProgressState.awaitingBoundary
                : WorkoutProgressState.ready,
        revision: _uuid.v4(),
        updatedAt: _clock(),
        dirty: true,
      ),
    );
  });

  /// The weeks a workout has reached: supplied, active, or holding one of
  /// [sessions] (the plan's live logs and drafts).
  static Set<String> reachedWeekIds(
    WorkoutProgress? progress,
    Iterable<WorkoutSession> sessions,
  ) => {
    ...?progress?.availableWeekIds,
    if (progress != null) progress.activeWeekId,
    for (final s in sessions)
      if (s.trainingWeekId != null) s.trainingWeekId!,
  };

  /// Removes [weekId] from one workout: its logs and drafts there are
  /// tombstoned and the tab is no longer supplied. The shared week row stays,
  /// since other workouts may use it, so reaching the slot again reuses it.
  /// Deleting the active week moves progress to the nearest earlier reached
  /// week, else the nearest later one, at a fresh revision so no older
  /// completion evidence can replay over the choice.
  Future<void> removeWeek({required String planId, required String weekId}) =>
      SyncService.instance.runExclusiveLocalMutation(() async {
        await replayUnderGate();
        final plan = HiveService.getPlanById(planId);
        if (plan == null ||
            plan.deletedAt != null ||
            plan.userId != _owner() ||
            plan.splitId == null) {
          throw StateError('The plan is unavailable.');
        }
        final splitId = plan.splitId!;
        HiveService.validateTrainingSplit(splitId, _owner());
        final order = [
          for (final block in HiveService.blocksForSplit(splitId))
            for (final week in HiveService.weeksForBlock(splitId, block.id))
              week.id,
        ];
        final progress = HiveService.progressForPlan(splitId, planId);
        final sessions =
            HiveService.sessionsForPlanWeek(
              splitId,
              planId,
              weekId,
            ).where((s) => s.userId == _owner()).toList();
        final reached =
            reachedWeekIds(
              progress,
              HiveService.getSessions(
                splitId: splitId,
              ).where((s) => s.planId == planId && s.userId == _owner()),
            ).where(order.contains).toSet();
        if (!reached.contains(weekId)) {
          throw StateError('The week has nothing to delete.');
        }
        final remaining = order.where(
          (id) => id != weekId && reached.contains(id),
        );
        if (remaining.isEmpty) {
          throw StateError("The workout's only week cannot be deleted.");
        }
        for (final session in sessions) {
          await HiveService.softDeleteSession(session.id!);
        }
        if (progress == null ||
            (progress.activeWeekId != weekId &&
                !(progress.availableWeekIds?.contains(weekId) ?? false))) {
          return;
        }
        final index = order.indexOf(weekId);
        final active =
            progress.activeWeekId != weekId
                ? progress.activeWeekId
                : remaining.lastWhere(
                  (id) => order.indexOf(id) < index,
                  orElse: () => remaining.first,
                );
        final moved = active != progress.activeWeekId;
        await _writeProgress(
          progress.copyWith(
            activeWeekId: active,
            availableWeekIds:
                progress.availableWeekIds == null
                    ? null
                    : {
                      ...progress.availableWeekIds!.where((id) => id != weekId),
                      active,
                    }.toList(),
            state: moved ? WorkoutProgressState.ready : progress.state,
            revision: _uuid.v4(),
            updatedAt: _clock(),
            dirty: true,
          ),
        );
      });

  Future<void> chooseBoundary({
    required String planId,
    required String expectedRevision,
    required String destinationWeekId,
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
    await replayUnderGate();
    final plan = HiveService.getPlanById(planId);
    if (plan == null ||
        plan.deletedAt != null ||
        plan.userId != _owner() ||
        plan.splitId == null) {
      throw StateError('The plan is unavailable.');
    }
    HiveService.validateTrainingSplit(plan.splitId!, _owner());
    final progress = HiveService.progressForPlan(plan.splitId!, planId);
    if (progress == null ||
        progress.revision != expectedRevision ||
        progress.state != WorkoutProgressState.awaitingBoundary) {
      throw StateError('Training progress changed. Open it again.');
    }
    final source = HiveService.getTrainingWeekById(progress.activeWeekId)!;
    var next = _nextInBlock(progress);
    if (next == null) {
      final blocks = HiveService.blocksForSplit(progress.splitId);
      final index = blocks.indexWhere((b) => b.id == source.blockId);
      if (index >= 0 && index + 1 < blocks.length) {
        next =
            HiveService.weeksForBlock(
              progress.splitId,
              blocks[index + 1].id,
            ).firstOrNull;
      }
    }
    if (next == null || next.id != destinationWeekId) {
      throw StateError('The available destination changed. Choose again.');
    }
    await _writeProgress(
      progress.copyWith(
        activeWeekId: next.id,
        availableWeekIds:
            {
              ...?progress.availableWeekIds,
              progress.activeWeekId,
              next.id,
            }.toList(),
        state: WorkoutProgressState.ready,
        revision: _uuid.v4(),
        updatedAt: _clock(),
        dirty: true,
      ),
    );
  });
  WorkoutProgress _boundaryProgress(String planId, String expectedRevision) {
    final plan = HiveService.getPlanById(planId);
    if (plan == null ||
        plan.deletedAt != null ||
        plan.userId != _owner() ||
        plan.splitId == null) {
      throw StateError('The plan is unavailable.');
    }
    HiveService.validateTrainingSplit(plan.splitId!, _owner());
    final p = HiveService.progressForPlan(plan.splitId!, planId);
    if (p == null ||
        p.revision != expectedRevision ||
        p.state != WorkoutProgressState.awaitingBoundary) {
      throw StateError('Training progress changed. Open it again.');
    }
    return p;
  }

  Future<TrainingWeek> extendBoundary({
    required String planId,
    required String expectedRevision,
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
    final pending = Hive.box<dynamic>(
      HiveService.trainingOperationsBox,
    ).get('boundary');
    if (pending is Map &&
        pending['action'] == 'append' &&
        pending['planId'] == planId &&
        pending['expectedRevision'] == expectedRevision) {
      final recovered = await recoverBoundaryUnderGate(
        ownerId: _owner(),
        writeProgress: _writeProgress,
      );
      if (recovered != null) {
        return HiveService.getTrainingWeekById(
          (recovered['weeks'] as List).first['id'] as String,
        )!;
      }
    }
    await replayUnderGate();
    final progress = _boundaryProgress(planId, expectedRevision);
    final supplied = await _ensureNextInBlock(progress);
    if (supplied != null) {
      await _writeProgress(
        progress.copyWith(
          activeWeekId: supplied.id,
          availableWeekIds:
              {
                ...?progress.availableWeekIds,
                progress.activeWeekId,
                supplied.id,
              }.toList(),
          state: WorkoutProgressState.ready,
          revision: _uuid.v4(),
          updatedAt: _clock(),
          dirty: true,
        ),
      );
      return supplied;
    }
    final source = HiveService.getTrainingWeekById(progress.activeWeekId)!;
    final now = _clock();
    final retained =
        HiveService.weeksForBlock(
          progress.splitId,
          source.blockId,
        ).where((w) => w.number == source.number + 1).firstOrNull;
    final week =
        retained ??
        TrainingWeek(
          id: lazyTrainingWeekId(
            progress.splitId,
            source.blockId,
            source.number + 1,
          ),
          splitId: progress.splitId,
          blockId: source.blockId,
          number: source.number + 1,
          createdAt: now,
          updatedAt: now,
          userId: _owner(),
          dirty: true,
        );
    final block = HiveService.getTrainingBlockById(source.blockId)!;
    final extended = block.copyWith(
      plannedWeekCount: week.number,
      updatedAt: now,
      dirty: true,
    );
    await _persistBoundary('append', progress, [week], block: extended);
    await recoverBoundaryUnderGate(
      ownerId: _owner(),
      writeProgress: _writeProgress,
    );
    return week;
  });

  Future<TrainingBlock> createBoundary({
    required String planId,
    required String expectedRevision,
    required String name,
    required int weekCount,
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
    final trimmed = HiveService.validateTrainingName(name);
    if (weekCount < 1 || weekCount > 52) {
      throw ArgumentError('Choose 1–52 weeks.');
    }
    final pending = Hive.box<dynamic>(
      HiveService.trainingOperationsBox,
    ).get('boundary');
    if (pending is Map &&
        pending['action'] == 'create' &&
        pending['planId'] == planId &&
        pending['expectedRevision'] == expectedRevision) {
      if ((pending['block'] as Map)['name'] != trimmed ||
          ((pending['block'] as Map)['plannedWeekCount'] ??
                  (pending['weeks'] as List).length) !=
              weekCount) {
        throw StateError(
          'Retry the original block before changing its details.',
        );
      }
      final recovered = await recoverBoundaryUnderGate(
        ownerId: _owner(),
        writeProgress: _writeProgress,
      );
      if (recovered != null) {
        return HiveService.getTrainingBlockById(
          (recovered['block'] as Map)['id'] as String,
        )!;
      }
    }
    await replayUnderGate();
    final progress = _boundaryProgress(planId, expectedRevision);
    final source = HiveService.getTrainingWeekById(progress.activeWeekId)!;
    final blocks = HiveService.blocksForSplit(progress.splitId);
    if (_nextInBlock(progress) != null || blocks.last.id != source.blockId) {
      throw StateError(
        'A destination was added. Choose it before creating another block.',
      );
    }
    final now = _clock();
    final block = TrainingBlock(
      id: _uuid.v4(),
      splitId: progress.splitId,
      name: trimmed,
      plannedWeekCount: weekCount,
      position:
          blocks.map((b) => b.position).reduce((a, b) => a > b ? a : b) + 1,
      createdAt: now,
      updatedAt: now,
      userId: _owner(),
      dirty: true,
    );
    final weeks = [
      TrainingWeek(
        id: lazyTrainingWeekId(progress.splitId, block.id, 1),
        splitId: progress.splitId,
        blockId: block.id,
        number: 1,
        createdAt: now,
        updatedAt: now,
        userId: _owner(),
        dirty: true,
      ),
    ];
    await _persistBoundary('create', progress, weeks, block: block);
    await recoverBoundaryUnderGate(
      ownerId: _owner(),
      writeProgress: _writeProgress,
    );
    return block;
  });

  Future<void> _persistBoundary(
    String action,
    WorkoutProgress before,
    List<TrainingWeek> weeks, {
    TrainingBlock? block,
  }) async {
    final target = before.copyWith(
      activeWeekId: weeks.first.id,
      availableWeekIds:
          {
            ...?before.availableWeekIds,
            before.activeWeekId,
            weeks.first.id,
          }.toList(),
      state: WorkoutProgressState.ready,
      revision: _uuid.v4(),
      updatedAt: _clock(),
      dirty: true,
    );
    final operations = Hive.box<dynamic>(HiveService.trainingOperationsBox);
    await operations.put('boundary', {
      'ownerId': _owner(),
      'action': action,
      'planId': before.planId,
      'expectedRevision': before.revision,
      'sourceWeekId': before.activeWeekId,
      'block': block?.toJson(),
      'weeks': weeks.map((w) => w.toJson()).toList(),
      'progress': target.toJson(),
    });
    await operations.flush();
  }

  /// One fixed boundary allocation and move. The progress compare prevents a
  /// pending choice from overwriting a later explicit choice at the same slot.
  static Future<Map<String, dynamic>?> recoverBoundaryUnderGate({
    required String? ownerId,
    Future<void> Function(WorkoutProgress)? writeProgress,
  }) async {
    final operations = Hive.box<dynamic>(HiveService.trainingOperationsBox);
    final raw = operations.get('boundary');
    if (raw == null) return null;
    final intent = Map<String, dynamic>.from(raw as Map);
    if (intent['ownerId'] != ownerId) {
      throw StateError('The boundary choice belongs to another account.');
    }
    final target = WorkoutProgress.fromJson(
      Map<String, dynamic>.from(intent['progress'] as Map),
    ).copyWith(dirty: true);
    if (target.userId != ownerId || target.planId != intent['planId']) {
      throw StateError('Conflicting boundary progress.');
    }
    final split = HiveService.getSplitById(target.splitId);
    final plan = HiveService.getPlanById(target.planId);
    if (split?.deletedAt != null || plan?.deletedAt != null) {
      await operations.delete('boundary');
      await operations.flush();
      return null;
    }
    HiveService.validateTrainingSplit(target.splitId, ownerId);
    if (plan == null ||
        plan.userId != ownerId ||
        plan.splitId != target.splitId) {
      throw StateError('The boundary plan is unavailable.');
    }
    if (intent['block'] case final Map json) {
      final block = TrainingBlock.fromJson(
        Map<String, dynamic>.from(json),
      ).copyWith(dirty: true);
      if (block.userId != ownerId || block.splitId != target.splitId) {
        throw StateError('Conflicting boundary block.');
      }
      final saved = HiveService.getTrainingBlockById(block.id);
      if (saved == null) {
        await HiveService.putTrainingBlockRaw(block);
      } else if (saved.deletedAt != null ||
          saved.splitId != block.splitId ||
          saved.userId != ownerId) {
        throw StateError('The boundary block changed.');
      } else if (intent['action'] == 'append' &&
          (block.plannedWeekCount ?? 0) > (saved.plannedWeekCount ?? 0)) {
        await HiveService.putTrainingBlockRaw(
          saved.copyWith(
            plannedWeekCount: block.plannedWeekCount,
            updatedAt: block.updatedAt,
            dirty: true,
          ),
        );
      }
    }
    for (final rawWeek in intent['weeks'] as List) {
      final week = TrainingWeek.fromJson(
        Map<String, dynamic>.from(rawWeek as Map),
      ).copyWith(dirty: true);
      if (week.userId != ownerId ||
          week.splitId != target.splitId ||
          week.number < 1) {
        throw StateError('Conflicting boundary week.');
      }
      HiveService.validateTrainingBlock(week.splitId, week.blockId, ownerId);
      final saved = HiveService.getTrainingWeekById(week.id);
      if (saved == null) {
        await HiveService.putTrainingWeekRaw(week);
      } else if (saved.deletedAt != null ||
          saved.splitId != week.splitId ||
          saved.blockId != week.blockId) {
        throw StateError('The boundary week changed.');
      }
    }
    final current = HiveService.getWorkoutProgressById(target.id);
    if (current != null &&
        current.deletedAt == null &&
        current.revision == intent['expectedRevision'] &&
        current.activeWeekId == intent['sourceWeekId'] &&
        current.state == WorkoutProgressState.awaitingBoundary) {
      await (writeProgress ?? HiveService.putWorkoutProgressRaw)(target);
    }
    await HiveService.flushTrainingData();
    await operations.delete('boundary');
    await operations.flush();
    return intent;
  }
}
