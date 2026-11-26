import 'dart:math' as math;

import '../models/exercise_template.dart';
import '../models/set.dart' as gym;
import '../models/set_template.dart';
import '../models/workout_plan.dart';
import 'exercise_catalog.dart';

/// Carries a workout's *Replace exercise* into its plan, when the user asks
/// for that.
///
/// A swap made in a workout stays in that workout and the weeks that carry
/// it over; the plan keeps its own lineup. After a swap the logger offers to
/// make the same swap in the plan, so the plan editor, Home and Coach agree
/// with what is being trained. Movements match by canonical ID, and a plan
/// that lists one movement more than once matches by occurrence.
abstract final class PlanExerciseSwap {
  static String _identity(ExerciseTemplate template) =>
      ExerciseCatalog.identity(template.name, template.exerciseId);

  /// Where [plan] lists movement [exerciseId] for the [occurrence]th time,
  /// counting from 0, or -1 when it does not.
  static int indexOf(
    WorkoutPlan plan,
    String exerciseId, {
    int occurrence = 0,
  }) {
    final wanted = ExerciseCatalog.canonicalId(exerciseId);
    var seen = 0;
    for (final (index, template) in plan.exercises.indexed) {
      if (_identity(template) != wanted) continue;
      if (seen == occurrence) return index;
      seen++;
    }
    return -1;
  }

  /// Whether the swap can be made in [plan]: it still lists the replaced
  /// movement there, and does not already have the replacement, which would
  /// leave the plan with the same exercise twice.
  static bool canApply(
    WorkoutPlan plan, {
    required String from,
    required String to,
    int occurrence = 0,
  }) =>
      indexOf(plan, from, occurrence: occurrence) >= 0 && indexOf(plan, to) < 0;

  /// [plan] with its [occurrence]th listing of movement [from] swapped for
  /// movement [to], called [name]. Returns [plan] unchanged when
  /// [canApply] is false.
  ///
  /// The swap follows the workout's own rule. The set count and effort
  /// targets stay. Reps and weight come from [history], the replacement's
  /// latest logged sets; with none, the reps stay and the weights become 0,
  /// which is how a plan stores "no weight target". The guidance note was
  /// written for the replaced movement, so it is cleared.
  static WorkoutPlan apply(
    WorkoutPlan plan, {
    required String from,
    required String to,
    required String name,
    int occurrence = 0,
    List<gym.Set> history = const [],
  }) {
    if (!canApply(plan, from: from, to: to, occurrence: occurrence)) {
      return plan;
    }
    final index = indexOf(plan, from, occurrence: occurrence);
    final replaced = plan.exercises[index];
    final List<SetTemplate>? targets;
    if (history.isNotEmpty) {
      targets = [
        for (var i = 0; i < replaced.sets; i++)
          SetTemplate(
            reps: history[math.min(i, history.length - 1)].reps,
            weight: history[math.min(i, history.length - 1)].weight,
            rpe: replaced.targetAt(i)?.rpe,
          ),
      ];
    } else {
      targets = [
        for (final target in replaced.setTargets ?? const <SetTemplate>[])
          SetTemplate(reps: target.reps, weight: 0, rpe: target.rpe),
      ];
    }
    return plan.copyWith(
      exercises: [
        for (final (i, template) in plan.exercises.indexed)
          if (i == index)
            ExerciseTemplate(
              name: name,
              exerciseId: to,
              sets: replaced.sets,
              // A plan saved before targets existed keeps having none.
              setTargets:
                  replaced.setTargets == null && history.isEmpty
                      ? null
                      : targets,
            )
          else
            template,
      ],
    );
  }

  /// A workout's recorded plan lineup with the same swap made in it.
  ///
  /// The workout that asked for the plan change has already seen it. Without
  /// this, the next week would read the replacement as an exercise the plan
  /// gained since, and bring it back if this workout went on to drop it.
  /// Other plan edits made since the workout was built are left to arrive
  /// next week as usual.
  static List<String>? inLineup(
    List<String>? lineup, {
    required String from,
    required String to,
    int occurrence = 0,
  }) {
    if (lineup == null) return null;
    final wanted = ExerciseCatalog.canonicalId(from);
    var seen = 0;
    return List.unmodifiable([
      for (final id in lineup)
        if (ExerciseCatalog.canonicalId(id) == wanted && seen++ == occurrence)
          ExerciseCatalog.canonicalId(to)
        else
          id,
    ]);
  }
}
