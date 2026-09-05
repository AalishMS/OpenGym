import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../models/workout_plan.dart';
import '../models/workout_session.dart';

/// Builds a session only when the caller has no saved data for the requested
/// plan and week.
///
/// Week 1 starts from the plan prescription. Later weeks retain the existing
/// previous-week copy behavior, with empty plan-shaped sets as the fallback.
class WorkoutSessionInitializer {
  static WorkoutSession initialize({
    required WorkoutPlan plan,
    required int weekNumber,
    WorkoutSession? existingSession,
    WorkoutSession? previousSession,
    DateTime? now,
  }) {
    if (existingSession != null) return existingSession;

    if (weekNumber > 1 &&
        previousSession != null &&
        previousSession.exercises.any((exercise) => exercise.sets.isNotEmpty)) {
      return WorkoutSession(
        date: now ?? DateTime.now(),
        planName: plan.name,
        exercises:
            previousSession.exercises
                .map(
                  (exercise) => Exercise(
                    name: exercise.name,
                    sets:
                        exercise.sets
                            .map(
                              (set) => gym.Set(
                                reps: set.reps,
                                weight: set.weight,
                                rpe: set.rpe,
                                note: set.note,
                                completed: false,
                              ),
                            )
                            .toList(),
                    note: exercise.note,
                  ),
                )
                .toList(),
        weekNumber: weekNumber,
        splitId: plan.splitId,
      );
    }

    final seedTargets = weekNumber == 1;
    return WorkoutSession(
      date: now ?? DateTime.now(),
      planName: plan.name,
      exercises:
          plan.exercises
              .map(
                (template) => Exercise(
                  name: template.name,
                  sets: List.generate(template.sets, (index) {
                    final target =
                        seedTargets ? template.targetAt(index) : null;
                    return gym.Set(
                      reps: target?.reps ?? 0,
                      weight: target?.weight ?? 0,
                      completed: false,
                    );
                  }),
                ),
              )
              .toList(),
      weekNumber: weekNumber,
      splitId: plan.splitId,
    );
  }
}
