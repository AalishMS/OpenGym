import '../models/training_block.dart';
import '../models/training_week.dart';
import '../utils/training_block_identity.dart';

/// Starting-week choices include intended slots without persisting previews.
List<TrainingWeek> plannedTrainingWeeks(
  TrainingBlock block,
  Iterable<TrainingWeek> supplied,
) {
  final byNumber = {
    for (final w in supplied)
      if (w.blockId == block.id && w.deletedAt == null) w.number: w,
  };
  final count = block.plannedWeekCount ?? 1;
  for (var n = 1; n <= count; n++) {
    byNumber.putIfAbsent(
      n,
      () => TrainingWeek(
        id: lazyTrainingWeekId(block.splitId, block.id, n),
        splitId: block.splitId,
        blockId: block.id,
        number: n,
        createdAt: block.createdAt,
        userId: block.userId,
      ),
    );
  }
  return byNumber.values.toList()..sort((a, b) => a.number.compareTo(b.number));
}
