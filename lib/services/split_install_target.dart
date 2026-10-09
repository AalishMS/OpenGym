import 'package:uuid/uuid.dart';

import '../models/split.dart';
import '../models/split_preference.dart';
import '../utils/split_identity.dart';
import 'hive_service.dart';

/// The split a batch of generated plans is installed into, shared by the
/// preset installer and the Coach: the user's untouched default split, reused
/// and renamed, or a new split. Writing it also makes it the active split.
///
/// Prepare, write, and roll back inside
/// `SyncService.runExclusiveLocalMutation`, so a sync can't interleave.
class SplitInstallTarget {
  static const Uuid _uuid = Uuid();
  static const int maxNameLength = 24;

  final String userId;
  final String splitId;
  final String splitName;
  final bool reusedDefaultSplit;
  final DateTime now;

  final Split _split;
  final Split? _originalSplit;
  final SplitPreference? _originalPreference;

  SplitInstallTarget._({
    required this.userId,
    required this.splitId,
    required this.splitName,
    required this.reusedDefaultSplit,
    required this.now,
    required Split split,
    required Split? originalSplit,
    required SplitPreference? originalPreference,
  }) : _split = split,
       _originalSplit = originalSplit,
       _originalPreference = originalPreference;

  /// Reads the current splits and preference, and throws a [StateError] when
  /// the user is at [maxSplits] and the active split can't be reused. Writes
  /// nothing.
  factory SplitInstallTarget.prepare({
    required String requestedName,
    required String userId,
    required int maxSplits,
    required DateTime now,
  }) {
    final activeSplits = HiveService.getSplits();
    final originalPreference = HiveService.getSplitPreference(userId);
    final preferenceSnapshot =
        originalPreference == null
            ? null
            : SplitPreference(
              userId: originalPreference.userId,
              activeSplitId: originalPreference.activeSplitId,
              updatedAt: originalPreference.updatedAt,
              dirty: originalPreference.dirty,
            );
    final activeId = HiveService.getActiveSplitId(userId);
    final activeSplit =
        activeId == null ? null : HiveService.getSplitById(activeId);
    final reusable = isUntouchedDefault(activeSplit, userId);
    if (!reusable && activeSplits.length >= maxSplits) {
      throw StateError(
        'You can have at most $maxSplits splits. Delete one in Manage splits.',
      );
    }

    final splitId = reusable ? activeSplit!.id : _uuid.v4();
    final splitName = uniqueName(
      requestedName,
      activeSplits,
      exceptId: reusable ? splitId : null,
    );
    return SplitInstallTarget._(
      userId: userId,
      splitId: splitId,
      splitName: splitName,
      reusedDefaultSplit: reusable,
      now: now,
      split:
          reusable
              ? activeSplit!.copyWith(
                name: splitName,
                userId: userId,
                updatedAt: now,
                dirty: true,
              )
              : Split(
                id: splitId,
                name: splitName,
                userId: userId,
                createdAt: now,
                updatedAt: now,
                dirty: true,
              ),
      originalSplit: reusable ? activeSplit!.copyWith() : null,
      originalPreference: preferenceSnapshot,
    );
  }

  Future<void> writeSplit() => HiveService.putSplitRaw(_split);

  Future<void> writePreference() => HiveService.putSplitPreferenceRaw(
    SplitPreference(
      userId: userId,
      activeSplitId: splitId,
      updatedAt: now,
      dirty: true,
    ),
  );

  /// Restores the split and preference as [SplitInstallTarget.prepare] found
  /// them. Safe to call whether or not the writes happened.
  Future<void> rollback() async {
    final originalSplit = _originalSplit;
    if (originalSplit == null) {
      await HiveService.deleteSplitRaw(splitId);
    } else {
      await HiveService.putSplitRaw(originalSplit);
    }
    final originalPreference = _originalPreference;
    if (originalPreference == null) {
      await HiveService.deleteSplitPreferenceRaw(userId);
    } else {
      await HiveService.putSplitPreferenceRaw(originalPreference);
    }
  }

  /// The deterministic `My Split` with no plans and no sessions.
  static bool isUntouchedDefault(Split? split, String userId) {
    if (split == null ||
        split.id != defaultSplitIdForUser(userId) ||
        split.name != 'My Split') {
      return false;
    }
    return HiveService.getPlans(splitId: split.id).isEmpty &&
        HiveService.getSessions(splitId: split.id).isEmpty;
  }

  /// [requested], or a ` (n)`-suffixed form of it that fits in
  /// [maxNameLength] and no other split uses.
  static String uniqueName(
    String requested,
    List<Split> splits, {
    String? exceptId,
  }) {
    final existing = {
      for (final split in splits.where((split) => split.id != exceptId))
        split.name.toLowerCase(),
    };
    if (!existing.contains(requested.toLowerCase())) return requested;
    var suffix = 2;
    while (true) {
      final tail = ' ($suffix)';
      final keep = maxNameLength - tail.length;
      final candidate =
          '${requested.substring(0, requested.length.clamp(0, keep))}$tail';
      if (!existing.contains(candidate.toLowerCase())) return candidate;
      suffix++;
    }
  }
}
