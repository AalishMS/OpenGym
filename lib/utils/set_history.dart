import '../models/set.dart' as gym;
import '../models/workout_session.dart';

/// Most recent earlier occurrence of an exercise, preserving set positions.
/// Workout callers scope this to the active plan and weeks before the selected
/// week; plan editors can consult the exercise's history across plans.
List<gym.Set> previousExerciseSets(
  Iterable<WorkoutSession> sessions,
  String exerciseName, {
  String? planId,
  String? planName,
  String? splitId,
  int? beforeWeek,
}) {
  final eligible =
      sessions.where((session) {
          if (session.deletedAt != null) return false;
          if (!session.isCompleted) return false;
          if (splitId != null && session.splitId != splitId) return false;
          if (planName != null &&
              (planId != null && session.planId != null
                  ? session.planId != planId
                  : session.planName != planName)) {
            return false;
          }
          return beforeWeek == null || session.weekNumber < beforeWeek;
        }).toList()
        ..sort(
          (a, b) =>
              beforeWeek != null
                  ? b.weekNumber.compareTo(a.weekNumber)
                  : b.date.compareTo(a.date),
        );
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
