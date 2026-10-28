import '../models/set.dart' as gym;
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_session.dart';
import '../services/training_week_session_resolver.dart';

/// Workout Previous follows structural slots; plan-editor Last stays date-based.
List<gym.Set> previousExerciseSets(
  Iterable<WorkoutSession> sessions,
  String exerciseName, {
  String? planId,
  String? planName,
  String? splitId,
  int? beforeWeek,
  String? beforeWeekId,
  String? excludingSessionId,
  Iterable<TrainingBlock> blocks = const [],
  Iterable<TrainingWeek> weeks = const [],
  bool includeDrafts = false,
}) {
  if (beforeWeekId != null) {
    if (planId == null || splitId == null) {
      throw ArgumentError('Structural history requires plan and split IDs.');
    }
    sessions = TrainingWeekSessionResolver.earlierSessions(
      splitId: splitId,
      planId: planId,
      weekId: beforeWeekId,
      blocks: blocks,
      weeks: weeks,
      sessions: sessions,
      excludingSessionId: excludingSessionId,
    );
  }
  final eligible =
      sessions.where((session) {
        if (session.deletedAt != null ||
            (excludingSessionId != null && session.id == excludingSessionId)) {
          return false;
        }
        if (!includeDrafts && !session.isCompleted) return false;
        if (splitId != null && session.splitId != splitId) return false;
        if (planId != null && session.planId != planId) return false;
        if (planId == null &&
            planName != null &&
            session.planName != planName) {
          return false;
        }
        return beforeWeek == null || session.weekNumber < beforeWeek;
      }).toList();
  if (beforeWeekId == null) {
    eligible.sort((a, b) {
      if (beforeWeek != null) {
        final number = b.weekNumber.compareTo(a.weekNumber);
        if (number != 0) return number;
      }
      final date = b.date.compareTo(a.date);
      return date == 0 ? (b.id ?? '').compareTo(a.id ?? '') : date;
    });
  }
  for (final session in eligible) {
    for (final exercise in session.exercises) {
      if (exercise.name.trim().toLowerCase() ==
              exerciseName.trim().toLowerCase() &&
          exercise.sets.any((set) => set.reps > 0)) {
        return exercise.sets;
      }
    }
  }
  return const [];
}
