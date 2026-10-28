import 'package:uuid/uuid.dart';

import '../models/completion_transition.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
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
    return weeks.where((w) => w.number > source.number).firstOrNull;
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
                  nextWeekId: _nextInBlock(progress)?.id,
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
    final next = _nextInBlock(progress);
    await _writeProgress(
      progress.copyWith(
        activeWeekId: next?.id ?? progress.activeWeekId,
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
        state: WorkoutProgressState.ready,
        revision: _uuid.v4(),
        updatedAt: _clock(),
        dirty: true,
      ),
    );
  });
}
