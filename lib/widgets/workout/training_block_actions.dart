import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/training_block.dart';
import '../../providers/training_block_provider.dart';
import '../../repositories/training_block_repository.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import 'training_block_dialogs.dart';

/// The storage side of the starting-week sheet's Create block and Edit block:
/// what [TrainingBlockDialogs.startingWeek] and [TrainingBlockDialogs.manage]
/// take as `load`, `onCreateBlock` and `onEditBlock`.
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

  TrainingBlockActions({
    required BuildContext Function() context,
    required this.splitId,
    required this.ownerId,
    this.onChanged,
  }) : _context = context;

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

  TrainingBlockRepository get _repository =>
      TrainingBlockRepository(ownerId: ownerId);

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
