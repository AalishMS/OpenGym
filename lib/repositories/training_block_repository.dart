import 'package:uuid/uuid.dart';

import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../services/training_block_lifecycle.dart';
import '../utils/training_block_identity.dart';

class TrainingBlockRepository {
  final String? Function() _owner;
  final bool Function(String? owner) _lifecycleAvailable;
  static const _uuid = Uuid();

  /// [lifecycleAvailable] answers whether this account's server keeps shortened
  /// blocks and deletes empty ones (training schema 4). It defaults to what
  /// sync negotiated; tests pass their own.
  TrainingBlockRepository({
    String? Function()? ownerId,
    bool Function(String? owner)? lifecycleAvailable,
  }) : _owner = ownerId ?? (() => SupabaseService.currentUserId),
       _lifecycleAvailable =
           lifecycleAvailable ?? SyncService.instance.blockLifecycleAvailable;

  DateTime? _clock(String? owner, DateTime at) => stampDurationClock(
    at,
    owner: owner,
    lifecycleAvailable: _lifecycleAvailable,
  );

  /// Whether blocks can be shortened and deleted for the current account.
  bool get lifecycleAvailable => _lifecycleAvailable(_owner());

  /// The fewest weeks [blockId] can be shortened to right now: the highest
  /// week anything refers to. Without lifecycle support it is the current
  /// length, because the server then only keeps the larger count.
  int minimumWeekCount(String splitId, String blockId) {
    final TrainingBlock block = HiveService.validateTrainingBlock(
      splitId,
      blockId,
      _owner(),
    );
    final int current = _currentCount(block);
    return _lifecycleAvailable(_owner()) ? _floor(block, current) : current;
  }

  /// Why [blockId] cannot be deleted from this device's data, or null. The
  /// server checks again when it deletes.
  BlockDeletionBlocker? deleteBlocker(String splitId, String blockId) {
    final String? owner = _owner();
    final TrainingBlock block = HiveService.validateTrainingBlock(
      splitId,
      blockId,
      owner,
    );
    return blockDeletionBlocker(
      block,
      blocks: HiveService.getAllTrainingBlocksRaw().where(
        (b) => b.userId == owner,
      ),
      weeks: HiveService.getAllTrainingWeeksRaw().where(
        (w) => w.userId == owner,
      ),
      progress: HiveService.getAllWorkoutProgressRaw().where(
        (p) => p.userId == owner,
      ),
      sessions: HiveService.getAllSessionsRaw().where((s) => s.userId == owner),
    );
  }

  int _currentCount(TrainingBlock block) =>
      block.plannedWeekCount ??
      weeksForBlock(
        block.splitId,
        block.id,
      ).fold<int>(1, (highest, w) => w.number > highest ? w.number : highest);

  int _floor(TrainingBlock block, int current) {
    final String? owner = _owner();
    final int floor = minimumBlockWeekCount(
      block,
      weeks: HiveService.getAllTrainingWeeksRaw().where(
        (w) => w.userId == owner,
      ),
      progress: HiveService.getAllWorkoutProgressRaw().where(
        (p) => p.userId == owner,
      ),
      sessions: HiveService.getAllSessionsRaw().where((s) => s.userId == owner),
    );
    return floor > current ? current : floor;
  }

  List<TrainingBlock> blocksForSplit(String splitId) =>
      HiveService.blocksForSplit(splitId);
  List<TrainingWeek> weeksForBlock(String splitId, String blockId) =>
      HiveService.weeksForBlock(splitId, blockId);
  WorkoutProgress? progressForPlan(String splitId, String planId) =>
      HiveService.progressForPlan(splitId, planId);
  List<WorkoutSession> sessionsForPlanWeek(
    String splitId,
    String planId,
    String weekId,
  ) => HiveService.sessionsForPlanWeek(splitId, planId, weekId);

  Future<TrainingBlock> createBlock({
    required String splitId,
    required String name,
    required int weekCount,
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
    final trimmed = HiveService.validateTrainingName(name);
    if (weekCount < 1 || weekCount > kMaxBlockWeeks) {
      throw ArgumentError.value(weekCount, 'weekCount');
    }
    final owner = _owner();
    HiveService.validateTrainingSplit(splitId, owner);
    // Recover fixed IDs before allocating any new creation.
    final recovered = await HiveService.recoverTrainingOperation(
      ownerId: owner,
    );
    if (recovered != null) {
      if (recovered.splitId != splitId ||
          recovered.name != trimmed ||
          (recovered.plannedWeekCount ??
                  weeksForBlock(splitId, recovered.id).length) !=
              weekCount) {
        throw StateError(
          'The previous block creation was recovered. Retry your new action.',
        );
      }
      return recovered;
    }
    final now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
    );
    final blocks = blocksForSplit(splitId);
    final block = TrainingBlock(
      id: _uuid.v4(),
      splitId: splitId,
      name: trimmed,
      plannedWeekCount: weekCount,
      plannedWeekCountUpdatedAt: _clock(owner, now),
      position:
          blocks.isEmpty
              ? 0
              : blocks.map((b) => b.position).reduce((a, b) => a > b ? a : b) +
                  1,
      createdAt: now,
      updatedAt: now,
      userId: owner,
      dirty: true,
    );
    final weeks = [
      TrainingWeek(
        id: lazyTrainingWeekId(splitId, block.id, 1),
        splitId: splitId,
        blockId: block.id,
        number: 1,
        createdAt: now,
        updatedAt: now,
        userId: owner,
        dirty: true,
      ),
    ];
    await HiveService.persistTrainingCreation(block, weeks);
    return block;
  });

  Future<TrainingWeek> appendWeek(String splitId, String blockId) =>
      SyncService.instance.runExclusiveLocalMutation(() async {
        final block = HiveService.validateTrainingBlock(
          splitId,
          blockId,
          _owner(),
        );
        final weeks = weeksForBlock(splitId, blockId);
        final now = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch,
        );
        final week = TrainingWeek(
          id: lazyTrainingWeekId(
            splitId,
            blockId,
            weeks.isEmpty ? 1 : weeks.last.number + 1,
          ),
          splitId: splitId,
          blockId: blockId,
          number: weeks.isEmpty ? 1 : weeks.last.number + 1,
          createdAt: now,
          updatedAt: now,
          userId: _owner(),
          dirty: true,
        );
        await HiveService.putTrainingWeekRaw(week);
        if (week.number > (block.plannedWeekCount ?? 0)) {
          await HiveService.putTrainingBlockRaw(
            block.copyWith(
              plannedWeekCount: week.number,
              plannedWeekCountUpdatedAt: _clock(_owner(), now),
              updatedAt: now,
              dirty: true,
            ),
          );
        }
        return week;
      });

  Future<void> renameBlock(String splitId, String blockId, String name) =>
      SyncService.instance.runExclusiveLocalMutation(() async {
        final trimmed = HiveService.validateTrainingName(name);
        final block = HiveService.validateTrainingBlock(
          splitId,
          blockId,
          _owner(),
        );
        await HiveService.putTrainingBlockRaw(
          block.copyWith(name: trimmed, updatedAt: DateTime.now(), dirty: true),
        );
      });

  /// Renames a block and/or changes its planned length. Where the server keeps
  /// shortened blocks (training schema 4, see [lifecycleAvailable]) the length
  /// can go down to [minimumWeekCount]; otherwise it is grow-only, because the
  /// server keeps the greater count and a shorter value could never stick.
  /// Week rows stay lazy; a plan allocates the next one when it reaches it.
  ///
  /// A null [weekCount] leaves the stored length alone: neither the count nor
  /// its clock is written, so a rename cannot undo a length another device set
  /// since the caller last read the block. Pass a count only when the user
  /// chose one.
  Future<TrainingBlock> updateBlock({
    required String splitId,
    required String blockId,
    required String name,
    int? weekCount,
  }) => SyncService.instance.runExclusiveLocalMutation(() async {
    final trimmed = HiveService.validateTrainingName(name);
    final owner = _owner();
    HiveService.validateTrainingBlock(splitId, blockId, owner);
    // Finish interrupted structural writes first so the floor sees every week.
    await HiveService.recoverTrainingOperations(ownerId: owner);
    final block = HiveService.validateTrainingBlock(splitId, blockId, owner);
    if (weekCount == null) {
      if (trimmed == block.name) return block;
      final renamed = block.copyWith(
        name: trimmed,
        updatedAt: DateTime.now(),
        dirty: true,
      );
      await HiveService.putTrainingBlockRaw(renamed);
      return renamed;
    }
    final current = _currentCount(block);
    final minimum =
        _lifecycleAvailable(owner) ? _floor(block, current) : current;
    if (weekCount < minimum) {
      throw ArgumentError.value(
        weekCount,
        'weekCount',
        minimum == current
            ? 'A block can be extended but not shortened.'
            : 'A block cannot be shorter than $minimum weeks.',
      );
    }
    if (weekCount > current && weekCount > kMaxBlockWeeks) {
      throw ArgumentError.value(weekCount, 'weekCount');
    }
    if (trimmed == block.name && weekCount == block.plannedWeekCount) {
      return block;
    }
    final now = DateTime.now();
    final updated = block.copyWith(
      name: trimmed,
      plannedWeekCount: weekCount,
      // A changed length is stamped (or left without a clock where none may
      // exist); a rename alone keeps whatever the block has.
      plannedWeekCountUpdatedAt:
          weekCount == block.plannedWeekCount
              ? block.plannedWeekCountUpdatedAt
              : _clock(owner, now),
      updatedAt: now,
      dirty: true,
    );
    await HiveService.putTrainingBlockRaw(updated);
    return updated;
  });

  /// Deletes a block that nothing has been logged in and no plan is on. The
  /// block and its weeks are tombstoned; positions of other blocks are left
  /// alone, since order is (position, id). Signed-in data goes through the
  /// server's guarded delete, which can still refuse with a
  /// [TrainingBlockDeletionException]; data that never syncs is tombstoned
  /// here after the same local checks.
  Future<void> deleteBlock({required String splitId, required String blockId}) {
    final String? owner = _owner();
    if (owner != null && SupabaseService.isConfigured) {
      return SyncService.instance.deleteTrainingBlock(
        splitId: splitId,
        blockId: blockId,
      );
    }
    return SyncService.instance.runExclusiveLocalMutation(() async {
      await HiveService.recoverTrainingOperations(ownerId: owner);
      final TrainingBlock block = HiveService.validateTrainingBlock(
        splitId,
        blockId,
        owner,
      );
      final BlockDeletionBlocker? blocker = deleteBlocker(splitId, block.id);
      if (blocker != null) {
        throw TrainingBlockDeletionException(switch (blocker) {
          BlockDeletionBlocker.lastBlock =>
            TrainingBlockDeletionReason.lastBlock,
          _ => TrainingBlockDeletionReason.inUse,
        }, blocker: blocker);
      }
      await SyncService.tombstoneTrainingBlockLocally(blockId);
      await HiveService.flushTrainingData();
    });
  }

  Future<void> reorderBlocks(String splitId, List<String> orderedIds) =>
      SyncService.instance.runExclusiveLocalMutation(() async {
        HiveService.validateTrainingSplit(splitId, _owner());
        final blocks = blocksForSplit(splitId);
        if (orderedIds.length != blocks.length ||
            orderedIds.toSet().length != blocks.length ||
            !orderedIds.toSet().containsAll(blocks.map((b) => b.id))) {
          throw ArgumentError('Supply every live block exactly once.');
        }
        final now = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch,
        );
        final byId = {for (final block in blocks) block.id: block};
        for (var i = 0; i < orderedIds.length; i++) {
          final block = byId[orderedIds[i]]!;
          if (block.position != i) {
            await HiveService.putTrainingBlockRaw(
              block.copyWith(position: i, updatedAt: now, dirty: true),
            );
          }
        }
      });
}
