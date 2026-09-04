import '../models/split.dart';
import '../models/split_preference.dart';
import '../services/hive_service.dart';

class SplitRepository {
  List<Split> getSplits() => HiveService.getSplits();

  SplitPreference? getPreference(String userId) =>
      HiveService.getSplitPreference(userId);

  Future<void> upsertSplit(Split split) => HiveService.upsertSplit(split);

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
