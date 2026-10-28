import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../services/training_week_session_resolver.dart';
import '../services/workout_completion_service.dart';
import '../services/workout_progression_service.dart';
import 'split_provider.dart';

/// One split-scoped snapshot and its transient indexes, rebuilt only on reload.
class TrainingBlockProvider with ChangeNotifier {
  final SplitProvider? _splitProvider;
  final String? Function() _splitId;
  final String? Function() _owner;
  late final WorkoutProgressionService _progression;
  late final StreamSubscription<void> _syncSubscription;
  List<TrainingBlock> blocks = const [];
  Map<String, TrainingBlock> blockById = const {};
  Map<String, TrainingWeek> weekById = const {};
  Map<String, List<TrainingWeek>> weeksByBlock = const {};
  Map<String, WorkoutProgress> progressByPlan = const {};
  Map<String, WorkoutSession> sessionById = const {};
  Map<(String, String), List<WorkoutSession>> _sessionsBySlot = const {};

  TrainingBlockProvider({
    SplitProvider? splitProvider,
    String? Function()? splitIdProvider,
    String? Function()? ownerId,
  }) : _splitProvider = splitProvider,
       _splitId = splitIdProvider ?? (() => splitProvider?.activeSplitId),
       _owner = ownerId ?? (() => SupabaseService.currentUserId) {
    _progression = WorkoutProgressionService(ownerId: _owner);
    _splitProvider?.addListener(reload);
    _syncSubscription = SyncService.instance.changes.listen((_) => reload());
    reload();
  }

  List<WorkoutSession> sessionsForSlot(String planId, String weekId) =>
      _sessionsBySlot[(planId, weekId)] ?? const [];

  WorkoutSession? destination(
    String planId,
    String weekId, {
    String? sessionId,
  }) => TrainingWeekSessionResolver.destination(
    splitId: _splitId() ?? '',
    planId: planId,
    weekId: weekId,
    sessions:
        sessionId == null
            ? sessionsForSlot(planId, weekId)
            : [if (sessionById[sessionId] case final s?) s],
    sessionId: sessionId,
  );

  WorkoutSession? source(String planId, String weekId) =>
      TrainingWeekSessionResolver.source(
        splitId: _splitId() ?? '',
        planId: planId,
        weekId: weekId,
        blocks: blocks,
        weeks: weekById.values,
        sessions: sessionById.values,
      );

  List<WorkoutSession> previous(
    String planId,
    String weekId, {
    String? excludingSessionId,
  }) => TrainingWeekSessionResolver.earlierSessions(
    splitId: _splitId() ?? '',
    planId: planId,
    weekId: weekId,
    blocks: blocks,
    weeks: weekById.values,
    sessions: sessionById.values,
    excludingSessionId: excludingSessionId,
  );

  void reload() {
    final split = _splitId();
    final owner = _owner();
    blocks = List.unmodifiable(
      TrainingWeekSessionResolver.orderedBlocks(
        split ?? '',
        HiveService.getAllTrainingBlocksRaw().where((b) => b.userId == owner),
      ),
    );
    blockById = Map.unmodifiable({for (final b in blocks) b.id: b});
    final weeks =
        HiveService.getAllTrainingWeeksRaw()
            .where(
              (w) =>
                  w.splitId == split &&
                  w.userId == owner &&
                  w.deletedAt == null &&
                  blockById.containsKey(w.blockId),
            )
            .toList();
    weekById = Map.unmodifiable({for (final w in weeks) w.id: w});
    weeksByBlock = Map.unmodifiable({
      for (final b in blocks)
        b.id: List<TrainingWeek>.unmodifiable(
          TrainingWeekSessionResolver.orderedWeeks(split ?? '', b.id, weeks),
        ),
    });
    progressByPlan = Map.unmodifiable({
      for (final p in HiveService.getAllWorkoutProgressRaw())
        if (p.splitId == split && p.userId == owner && p.deletedAt == null)
          p.planId: p,
    });
    sessionById = Map.unmodifiable({
      for (final s in HiveService.getAllSessionsRaw())
        if (s.splitId == split && s.userId == owner && s.deletedAt == null)
          s.id!: s,
    });
    final slots = <(String, String), List<WorkoutSession>>{};
    for (final s in sessionById.values) {
      if (s.planId != null && s.trainingWeekId != null) {
        slots.putIfAbsent((s.planId!, s.trainingWeekId!), () => []).add(s);
      }
    }
    _sessionsBySlot = Map.unmodifiable({
      for (final entry in slots.entries)
        entry.key: List<WorkoutSession>.unmodifiable(entry.value),
    });
    notifyListeners();
  }

  Future<WorkoutCompletionResult> complete(String sessionId) async {
    final result = await _progression.complete(sessionId);
    reload();
    SyncService.instance.scheduleSync();
    return result;
  }

  Future<void> replay() async {
    await _progression.replay();
    reload();
  }

  Future<void> chooseBoundary({
    required String planId,
    required String expectedRevision,
    required String destinationWeekId,
  }) async {
    await _progression.chooseBoundary(
      planId: planId,
      expectedRevision: expectedRevision,
      destinationWeekId: destinationWeekId,
    );
    reload();
    SyncService.instance.scheduleSync();
  }

  Future<void> continueCompleted({
    required String sessionId,
    required String expectedRevision,
  }) async {
    await _progression.continueCompleted(
      sessionId: sessionId,
      expectedRevision: expectedRevision,
    );
    reload();
    SyncService.instance.scheduleSync();
  }

  @override
  void dispose() {
    _splitProvider?.removeListener(reload);
    _syncSubscription.cancel();
    super.dispose();
  }
}
