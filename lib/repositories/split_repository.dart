import '../models/split.dart';
import '../models/split_preference.dart';
import '../services/hive_service.dart';
import '../services/sync_service.dart';
import '../services/training_block_migration.dart';
import '../services/training_block_restore.dart';

class SplitRepository {
  List<Split> getSplits() => HiveService.getSplits();

  SplitPreference? getPreference(String userId) =>
      HiveService.getSplitPreference(userId);

  Future<void> upsertSplit(Split split) =>
      SyncService.instance.runExclusiveLocalMutation(() async {
        if (HiveService.getSplitById(split.id) != null) {
          await HiveService.upsertSplit(split);
          return;
        }
        await HiveService.recoverTrainingOperations(ownerId: split.userId);
        final graph = TrainingBlockMigration.prepareGraph(
          HiveService.readTrainingGraph(ownerId: split.userId)
              .ownedBy(split.userId)
              .copyWith(splits: [...HiveService.getAllSplitsRaw(), split])
              .ensureNewStructure(split.id),
        );
        await TrainingBlockRestore().replaceUnderGate(
          graph: graph,
          stampRecords: false,
        );
      });

  Future<void> setActive(String userId, String splitId) =>
      HiveService.setActiveSplit(userId, splitId);

  Future<void> deleteSplit({
    required String userId,
    required String splitId,
    required String replacementSplitId,
  }) => HiveService.softDeleteSplit(
    userId: userId,
    splitId: splitId,
    replacementSplitId: replacementSplitId,
  );

  int getPlanCount(String splitId) =>
      HiveService.getPlans(splitId: splitId).length;

  int getSessionCount(String splitId) =>
      HiveService.getSessions(splitId: splitId).length;
}
