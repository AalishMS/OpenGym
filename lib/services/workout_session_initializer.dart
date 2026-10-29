import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/training_week.dart';
import 'package:uuid/uuid.dart';

/// Builds a session only when the caller has no saved data for the requested
/// plan and week.
///
/// The resolver supplies the saved destination and completed source explicitly.
/// Missing matches use current plan prescriptions, regardless of week label.
class WorkoutSessionInitializer {
  static WorkoutSession initialize({
    required WorkoutPlan plan,
    required TrainingWeek week,
    WorkoutSession? existingSession,
    WorkoutSession? previousSession,
    DateTime? now,
  }) {
    if (existingSession != null) return existingSession;
    if (plan.splitId != week.splitId) {
      throw ArgumentError('The week belongs to another split.');
    }
    final source =
        previousSession != null &&
                previousSession.planId == plan.id &&
                previousSession.splitId == plan.splitId &&
                previousSession.isCompleted &&
                previousSession.deletedAt == null
            ? previousSession
            : null;
    String name(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final sources = <String, List<Exercise>>{};
    for (final exercise in source?.exercises ?? <Exercise>[]) {
      sources.putIfAbsent(name(exercise.name), () => []).add(exercise);
    }
    final occurrences = <String, int>{};
    final exercises = <Exercise>[];
    for (final template in plan.exercises) {
      final key = name(template.name);
      final occurrence = occurrences[key] ?? 0;
      occurrences[key] = occurrence + 1;
      final matches = sources[key] ?? [];
      final from = occurrence < matches.length ? matches[occurrence] : null;
      exercises.add(
        Exercise(
          name: template.name,
          note: template.note,
          sets:
              from != null && from.sets.isNotEmpty
                  ? [
                    for (final set in from.sets)
                      gym.Set(reps: set.reps, weight: set.weight, rpe: set.rpe),
                  ]
                  : List.generate(template.sets, (i) {
                    final target = template.targetAt(i);
                    return gym.Set(
                      reps: target?.reps ?? 0,
                      weight: target?.weight ?? 0,
                      rpe: target?.rpe,
                    );
                  }),
        ),
      );
    }
    return WorkoutSession(
      id: const Uuid().v4(),
      date: now ?? DateTime.now(),
      planName: plan.name,
      planId: plan.id,
      splitId: plan.splitId,
      userId: plan.userId,
      trainingWeekId: week.id,
      weekNumber: week.number,
      exercises: exercises,
      isCompleted: false,
      durationSeconds: 0,
    );
  }
}
