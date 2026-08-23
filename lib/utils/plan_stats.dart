import '../models/workout_plan.dart';
import '../models/workout_session.dart';

/// Rolled-up training history for one plan.
///
/// Derived (not stored): computed from an already-loaded session list so both
/// the Dashboard's plan panel and the Plans grid footers can share one pass
/// instead of each querying the repository per plan.
class PlanStat {
  final WorkoutPlan plan;

  /// Index into `WorkoutPlanProvider.plans` — `WorkoutScreen` needs it.
  final int planIndex;
  final int sessionCount;
  final DateTime? lastTrained;
  final int volumeKg;

  const PlanStat({
    required this.plan,
    required this.planIndex,
    required this.sessionCount,
    required this.lastTrained,
    required this.volumeKg,
  });

  /// Recently-trained plans first; never-trained plans keep their original plan
  /// order at the bottom.
  static List<PlanStat> compute(
    List<WorkoutPlan> plans,
    List<WorkoutSession> sessions,
  ) {
    final stats = <PlanStat>[];

    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      final planSessions = sessions
          .where((s) => s.planName.toLowerCase() == plan.name.toLowerCase())
          .toList();

      var volume = 0;
      DateTime? last;
      for (final session in planSessions) {
        if (last == null || session.date.isAfter(last)) last = session.date;
        for (final exercise in session.exercises) {
          for (final set in exercise.sets) {
            volume += (set.weight * set.reps).round();
          }
        }
      }

      stats.add(PlanStat(
        plan: plan,
        planIndex: i,
        sessionCount: planSessions.length,
        lastTrained: last,
        volumeKg: volume,
      ));
    }

    stats.sort((a, b) {
      if (a.lastTrained == null && b.lastTrained == null) {
        return a.planIndex.compareTo(b.planIndex);
      }
      if (a.lastTrained == null) return 1;
      if (b.lastTrained == null) return -1;
      return b.lastTrained!.compareTo(a.lastTrained!);
    });

    return stats;
  }
}
