import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/training_block.dart';
import '../../providers/training_block_provider.dart';
import '../../repositories/training_block_repository.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/training_block_lifecycle.dart';
import 'training_block_dialogs.dart';

/// The storage side of the starting-week sheet's Create block, Edit block and
/// Delete block: what [TrainingBlockDialogs.startingWeek] and
/// [TrainingBlockDialogs.manage] take as `load`, `onCreateBlock`,
/// `onEditBlock` and `lifecycle`.
///
/// Block changes write straight to storage, outside any form's Save, so each
/// one reloads [TrainingBlockProvider] (when present) and schedules a sync,
/// also after a failure: a recovered creation can have written a block.
class TrainingBlockActions {
  final BuildContext Function() _context;
  final String splitId;

  /// The account the write belongs to, resolved when the write happens.
  final String? Function() ownerId;

  /// Runs after every write attempt, while the context is still mounted.
  final VoidCallback? onChanged;

  /// Overrides what sync negotiated, for tests.
  final bool Function(String? owner)? _lifecycleAvailable;

  TrainingBlockActions({
    required BuildContext Function() context,
    required this.splitId,
    required this.ownerId,
    this.onChanged,
    bool Function(String? owner)? lifecycleAvailable,
  }) : _context = context,
       _lifecycleAvailable = lifecycleAvailable;

  /// The split's own owner, unless the caller knows a plan's.
  static String? splitOwner(String splitId) =>
      HiveService.getSplitById(splitId)?.userId;

  TrainingBlockSnapshot load() {
    final blocks = HiveService.blocksForSplit(splitId);
    return (
      blocks: blocks,
      weeksByBlock: {
        for (final b in blocks)
          b.id: HiveService.startingWeeksForBlock(splitId, b.id),
      },
    );
  }

  TrainingBlockRepository get _repository => TrainingBlockRepository(
    ownerId: ownerId,
    lifecycleAvailable: _lifecycleAvailable,
  );

  Future<TrainingBlock> create(String name, int count) => _mutate(
    () =>
        _repository.createBlock(splitId: splitId, name: name, weekCount: count),
  );

  Future<TrainingBlock> edit(TrainingBlock block, String name, int count) =>
      _mutate(
        () => _repository.updateBlock(
          splitId: splitId,
          blockId: block.id,
          name: name,
          weekCount: count,
        ),
      );

  Future<void> delete(TrainingBlock block) => _mutate(
    () => _repository.deleteBlock(splitId: splitId, blockId: block.id),
  );

  /// Whether this account can shorten and delete blocks right now.
  bool get lifecycleAvailable => _repository.lifecycleAvailable;

  /// The fewest weeks [blockId] can be shortened to.
  int minimumWeekCount(String blockId) =>
      _repository.minimumWeekCount(splitId, blockId);

  BlockDeletionBlocker? deleteBlocker(String blockId) =>
      _repository.deleteBlocker(splitId, blockId);

  /// The shorten and delete rules for the block sheets.
  TrainingBlockLifecycle get lifecycle =>
      TrainingBlockLifecycle.of(_repository, splitId: splitId, delete: delete);

  Future<T> _mutate<T>(Future<T> Function() write) async {
    try {
      return await write();
    } finally {
      final context = _context();
      if (context.mounted) {
        context.read<TrainingBlockProvider?>()?.reload();
        onChanged?.call();
      }
      SyncService.instance.scheduleSync();
    }
  }
}
