// Builders for eval fixtures: plans, splits, and a generated training log
// whose trends come out the way each case needs.

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';

/// Every case runs as if it were Saturday 10 October 2026, midday.
final DateTime kEvalNow = DateTime(2026, 10, 10, 12);

const String kActiveSplitId = 'split-active';

Split split(String name, {String id = kActiveSplitId}) =>
    Split(id: id, name: name, createdAt: DateTime(2026, 3, 1));

/// [sets] sets of [reps] at [kg]; kg 0 means no weight target.
ExerciseTemplate ex(
  String name,
  int sets,
  int reps,
  double kg, {
  String? note,
}) => ExerciseTemplate(
  name: name,
  sets: sets,
  setTargets: [
    for (var index = 0; index < sets; index++)
      SetTemplate(reps: reps, weight: kg),
  ],
  note: note,
);

WorkoutPlan plan(
  String id,
  String name,
  int position,
  List<ExerciseTemplate> exercises, {
  String splitId = kActiveSplitId,
}) => WorkoutPlan(
  id: id,
  name: name,
  exercises: exercises,
  splitId: splitId,
  position: position,
  planColor: position,
  userId: 'eval-user',
  updatedAt: DateTime(2026, 9, 1),
);

enum Pattern { improving, stalled, declining }

/// How one exercise was logged. [lastKg] is the latest working weight, which
/// can differ from the plan's target; null uses the target.
class Lift {
  final Pattern pattern;
  final double? lastKg;

  const Lift(this.pattern, {this.lastKg});
}

double _half(double value) => (value * 2).round() / 2;

/// A completed session on every [weekdays] day of the last [weeks] weeks,
/// cycling through [plans] in order. Each exercise follows its [Lift]
/// (improving by default) so the context builder's trend comes out as named.
List<WorkoutSession> logHistory({
  required List<WorkoutPlan> plans,
  int weeks = 6,
  List<int> weekdays = const [
    DateTime.monday,
    DateTime.wednesday,
    DateTime.friday,
  ],
  Map<String, Lift> lifts = const {},
  String splitId = kActiveSplitId,
}) {
  final today = DateTime(kEvalNow.year, kEvalNow.month, kEvalNow.day);
  final sessions = <WorkoutSession>[];
  var count = 0;
  for (var daysAgo = weeks * 7; daysAgo >= 1; daysAgo--) {
    final date = DateTime(today.year, today.month, today.day - daysAgo, 18);
    if (!weekdays.contains(date.weekday)) continue;
    final source = plans[count % plans.length];
    count++;
    final weeksAgo = daysAgo ~/ 7;
    sessions.add(
      WorkoutSession(
        id: 'session-$count',
        date: date,
        planName: source.name,
        planId: source.id,
        splitId: splitId,
        userId: 'eval-user',
        durationSeconds: 3600,
        updatedAt: date,
        exercises: [
          for (final template in source.exercises)
            Exercise(
              name: template.name,
              sets: _loggedSets(
                template,
                lifts[template.name] ?? const Lift(Pattern.improving),
                weeksAgo,
                count,
              ),
            ),
        ],
      ),
    );
  }
  return sessions;
}

List<gym.Set> _loggedSets(
  ExerciseTemplate template,
  Lift lift,
  int weeksAgo,
  int sessionNumber,
) {
  final targets = template.setTargets ?? const <SetTemplate>[];
  final base = lift.lastKg ?? (targets.isEmpty ? 0.0 : targets.first.weight);
  return [
    for (var index = 0; index < template.sets; index++)
      _loggedSet(
        reps: index < targets.length ? targets[index].reps : 8,
        base: base,
        lift: lift,
        weeksAgo: weeksAgo,
        missesRep: index == template.sets - 1 && sessionNumber.isEven,
      ),
  ];
}

gym.Set _loggedSet({
  required int reps,
  required double base,
  required Lift lift,
  required int weeksAgo,
  required bool missesRep,
}) {
  if (base == 0) {
    // Bodyweight: progress, or stall, in reps.
    final drop = lift.pattern == Pattern.improving ? weeksAgo ~/ 2 : 0;
    return gym.Set(reps: (reps - drop).clamp(1, 100), weight: 0);
  }
  final step = base >= 60 ? 2.5 : 1.0;
  return switch (lift.pattern) {
    Pattern.improving => gym.Set(
      reps: reps,
      weight: _half(base - step * weeksAgo),
    ),
    // Same weight every week; the last set misses a rep now and then.
    Pattern.stalled => gym.Set(reps: missesRep ? reps - 1 : reps, weight: base),
    Pattern.declining => gym.Set(
      reps: reps,
      weight: weeksAgo < 2 ? base : _half(base * 1.07),
    ),
  };
}
