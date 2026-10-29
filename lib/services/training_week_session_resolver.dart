import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_session.dart';

/// Resolves destinations and inheritance from one explicit split snapshot.
/// No storage access, so a preview never creates a draft.
abstract final class TrainingWeekSessionResolver {
  static int recency(WorkoutSession a, WorkoutSession b) {
    final stamp = (b.updatedAt ?? b.date).compareTo(a.updatedAt ?? a.date);
    if (stamp != 0) return stamp;
    final date = b.date.compareTo(a.date);
    return date == 0 ? (b.id ?? '').compareTo(a.id ?? '') : date;
  }

  static WorkoutSession? destination({
    required String splitId,
    required String planId,
    required String weekId,
    required Iterable<WorkoutSession> sessions,
    String? sessionId,
  }) {
    final live =
        sessions
            .where((s) => s.deletedAt == null && s.splitId == splitId)
            .toList();
    if (sessionId != null) {
      return live.where((s) => s.id == sessionId).firstOrNull;
    }
    final slot =
        live
            .where((s) => s.planId == planId && s.trainingWeekId == weekId)
            .toList()
          ..sort((a, b) {
            int rank(WorkoutSession s) =>
                !s.isCompleted ? (s.isTimerRunning ? 0 : 1) : 2;
            final order = rank(a).compareTo(rank(b));
            return order == 0 ? recency(a, b) : order;
          });
    return slot.firstOrNull;
  }

  static List<TrainingBlock> orderedBlocks(
    String splitId,
    Iterable<TrainingBlock> blocks,
  ) =>
      blocks.where((b) => b.splitId == splitId && b.deletedAt == null).toList()
        ..sort((a, b) {
          final order = a.position.compareTo(b.position);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });

  static List<TrainingWeek> orderedWeeks(
    String splitId,
    String blockId,
    Iterable<TrainingWeek> weeks,
  ) =>
      weeks
          .where(
            (w) =>
                w.splitId == splitId &&
                w.blockId == blockId &&
                w.deletedAt == null,
          )
          .toList()
        ..sort((a, b) {
          final order = a.number.compareTo(b.number);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });

  static WorkoutSession? source({
    required String splitId,
    required String planId,
    required String weekId,
    required Iterable<TrainingBlock> blocks,
    required Iterable<TrainingWeek> weeks,
    required Iterable<WorkoutSession> sessions,
  }) {
    final ordered = orderedBlocks(splitId, blocks);
    final week =
        weeks
            .where(
              (w) =>
                  w.id == weekId && w.splitId == splitId && w.deletedAt == null,
            )
            .firstOrNull;
    if (week == null) return null;
    final blockIndex = ordered.indexWhere((b) => b.id == week.blockId);
    if (blockIndex < 0) return null;
    TrainingWeek? from;
    if (week.number == 1 && blockIndex > 0) {
      from =
          orderedWeeks(
            splitId,
            ordered[blockIndex - 1].id,
            weeks,
          ).where((w) => w.number == week.number).firstOrNull;
    } else {
      final supplied = orderedWeeks(splitId, week.blockId, weeks);
      final index = supplied.indexWhere((w) => w.id == weekId);
      if (index > 0) from = supplied[index - 1];
    }
    if (from == null) return null;
    final candidates =
        sessions
            .where(
              (s) =>
                  s.splitId == splitId &&
                  s.planId == planId &&
                  s.trainingWeekId == from!.id &&
                  s.deletedAt == null &&
                  s.isCompleted,
            )
            .toList()
          ..sort(recency);
    return candidates.firstOrNull;
  }

  static List<WorkoutSession> earlierSessions({
    required String splitId,
    required String planId,
    required String weekId,
    required Iterable<TrainingBlock> blocks,
    required Iterable<TrainingWeek> weeks,
    required Iterable<WorkoutSession> sessions,
    String? excludingSessionId,
  }) {
    final blockOrder = {
      for (final (i, b) in orderedBlocks(splitId, blocks).indexed) b.id: i,
    };
    final weekMap = {
      for (final w in weeks.where(
        (w) => w.splitId == splitId && w.deletedAt == null,
      ))
        w.id: w,
    };
    final selected = weekMap[weekId];
    if (selected == null || !blockOrder.containsKey(selected.blockId)) {
      return [];
    }
    final currentBlock = blockOrder[selected.blockId]!;
    final eligible =
        sessions.where((s) {
            final slot = weekMap[s.trainingWeekId];
            final position = slot == null ? null : blockOrder[slot.blockId];
            return s.id != excludingSessionId &&
                s.deletedAt == null &&
                s.isCompleted &&
                s.planId == planId &&
                s.splitId == splitId &&
                slot != null &&
                position != null &&
                (position < currentBlock ||
                    position == currentBlock && slot.number < selected.number);
          }).toList()
          ..sort((a, b) {
            final wa = weekMap[a.trainingWeekId]!,
                wb = weekMap[b.trainingWeekId]!;
            final order = blockOrder[wb.blockId]!.compareTo(
              blockOrder[wa.blockId]!,
            );
            if (order != 0) return order;
            final number = wb.number.compareTo(wa.number);
            if (number != 0) return number;
            final date = b.date.compareTo(a.date);
            return date == 0 ? (b.id ?? '').compareTo(a.id ?? '') : date;
          });
    return eligible;
  }
}
