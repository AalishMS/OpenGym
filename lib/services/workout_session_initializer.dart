import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../models/workout_plan.dart';
import '../models/workout_session.dart';

class WorkoutSessionInitialization {
  final WorkoutSession session;
  final bool seededFromPlan;

  const WorkoutSessionInitialization({
    required this.session,
    required this.seededFromPlan,
  });
}

/// Builds only sessions that do not already exist.
///
/// Week 1 starts from the plan prescription. Later weeks deliberately retain
/// the established previous-week copy behavior, with empty plan-shaped sets as
/// the fallback when there is no usable prior session.
class WorkoutSessionInitializer {
  static WorkoutSessionInitialization initialize({
    required WorkoutPlan plan,
    required int weekNumber,
    WorkoutSession? existingSession,
    WorkoutSession? previousSession,
    DateTime? now,
  }) {
    if (existingSession != null) {
      return WorkoutSessionInitialization(
        session: existingSession,
        seededFromPlan: false,
      );
    }

    if (weekNumber > 1 &&
        previousSession != null &&
        previousSession.exercises.any((exercise) => exercise.sets.isNotEmpty)) {
      return WorkoutSessionInitialization(
        session: WorkoutSession(
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
                                ),
                              )
                              .toList(),
                      note: exercise.note,
                    ),
                  )
                  .toList(),
          weekNumber: weekNumber,
          splitId: plan.splitId,
        ),
        seededFromPlan: false,
      );
    }

    final seedTargets = weekNumber == 1;
    return WorkoutSessionInitialization(
      session: WorkoutSession(
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
                      );
                    }),
                  ),
                )
                .toList(),
        weekNumber: weekNumber,
        splitId: plan.splitId,
      ),
      seededFromPlan: seedTargets,
    );
  }
}
