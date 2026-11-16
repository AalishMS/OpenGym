import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';

/// Why a block cannot be deleted. The first matching reason is reported.
enum BlockDeletionBlocker {
  /// A split always keeps one live block.
  lastBlock,

  /// A workout (any state, any plan) was logged in one of the block's weeks.
  hasWorkouts,

  /// A plan is currently positioned in one of the block's weeks.
  workoutInBlock,
}

/// The fewest weeks [block] can be shortened to: the highest week anything
/// still refers to, and never less than one.
///
/// That is the highest number among the block's live week rows, the block's
/// weeks that live progress points at (its active week and every available
/// week), and the block's weeks that live sessions sit in or whose completion
/// evidence names them, whatever their completion state.
int minimumBlockWeekCount(
  TrainingBlock block, {
  required Iterable<TrainingWeek> weeks,
  required Iterable<WorkoutProgress> progress,
  required Iterable<WorkoutSession> sessions,
}) {
  final Map<String, TrainingWeek> own = {
    for (final TrainingWeek w in weeks)
      if (w.blockId == block.id) w.id: w,
  };
  int floor = 1;
  void reach(Object? id) {
    final TrainingWeek? week = own[id];
    if (week != null && week.number > floor) floor = week.number;
  }

  for (final TrainingWeek w in own.values) {
    if (w.deletedAt == null) reach(w.id);
  }
  for (final WorkoutProgress p in progress) {
    if (p.deletedAt != null) continue;
    reach(p.activeWeekId);
    for (final String id in p.availableWeekIds ?? const <String>[]) {
      reach(id);
    }
  }
  for (final WorkoutSession s in sessions) {
    if (s.deletedAt != null) continue;
    reach(s.trainingWeekId);
    final Map<String, dynamic>? evidence = s.completionTransition;
    if (evidence != null) {
      reach(evidence['sourceWeekId']);
      reach(evidence['nextWeekId']);
    }
  }
  return floor;
}

/// What stops [block] being deleted, or null when it can be. [blocks],
/// [weeks], [progress] and [sessions] are the account's raw rows; tombstoned
/// weeks still count as the block's weeks.
///
/// A progress row that only lists a week of the block as available is not a
/// blocker, and neither are empty allocated week rows.
BlockDeletionBlocker? blockDeletionBlocker(
  TrainingBlock block, {
  required Iterable<TrainingBlock> blocks,
  required Iterable<TrainingWeek> weeks,
  required Iterable<WorkoutProgress> progress,
  required Iterable<WorkoutSession> sessions,
}) {
  if (!blocks.any(
    (b) =>
        b.id != block.id && b.splitId == block.splitId && b.deletedAt == null,
  )) {
    return BlockDeletionBlocker.lastBlock;
  }
  final Set<String> own = {
    for (final TrainingWeek w in weeks)
      if (w.blockId == block.id) w.id,
  };
  if (sessions.any(
    (s) => s.deletedAt == null && own.contains(s.trainingWeekId),
  )) {
    return BlockDeletionBlocker.hasWorkouts;
  }
  if (progress.any(
    (p) => p.deletedAt == null && own.contains(p.activeWeekId),
  )) {
    return BlockDeletionBlocker.workoutInBlock;
  }
  return null;
}

/// The duration clock for a change of a block's planned length at [at], or null
/// where no clock may exist. A clock is meaningful only for local-only data
/// ([owner] null) or an account whose server resolves length on it
/// ([lifecycleAvailable], training schema 4). Below that the server keeps the
/// larger count and ignores the clock, so a stamped clock would only wait to
/// beat a clock-less write made later by an older app.
DateTime? stampDurationClock(
  DateTime at, {
  required String? owner,
  required bool Function(String? owner) lifecycleAvailable,
}) => owner == null || lifecycleAvailable(owner) ? at : null;
