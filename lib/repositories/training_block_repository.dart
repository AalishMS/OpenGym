import 'package:uuid/uuid.dart';

import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../utils/training_block_identity.dart';

class TrainingBlockRepository {
  final String? Function() _owner;
  static const _uuid = Uuid();

  TrainingBlockRepository({String? Function()? ownerId})
    : _owner = ownerId ?? (() => SupabaseService.currentUserId);

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
    if (weekCount < 1 || weekCount > 52) {
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
