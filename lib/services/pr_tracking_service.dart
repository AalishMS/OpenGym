import '../models/exercise.dart';
import '../models/workout_session.dart';
import '../repositories/stats_repository.dart';

class PRResult {
  final String exerciseName;
  final double previousPR;
  final double newPR;
  final int reps;
  final bool isWeightPR;
  final bool isRepsPR;

  PRResult({
    required this.exerciseName,
    required this.previousPR,
    required this.newPR,
    required this.reps,
    this.isWeightPR = true,
    this.isRepsPR = false,
  });
}

class PRTrackingService {
  static final StatsRepository _statsRepo = StatsRepository();

  static List<PRResult> checkForNewPRs(
    List<Exercise> exercises,
    String? splitId,
  ) {
    final results = <PRResult>[];

    for (var exercise in exercises) {
      if (exercise.sets.isEmpty) continue;

      for (var set in exercise.sets) {
        if (splitId == null) continue;
        final currentPR = _statsRepo.getExercisePR(exercise.name, splitId);

        if (set.weight > currentPR) {
          results.add(
            PRResult(
              exerciseName: exercise.name,
              previousPR: currentPR,
              newPR: set.weight,
              reps: set.reps,
              isWeightPR: true,
            ),
          );
        }
      }
    }

    return results;
  }

  /// Compares a candidate against an immutable completed-history snapshot.
  /// The caller is responsible for excluding the candidate's saved version.
  static List<PRResult> checkAgainstHistory(
    List<Exercise> exercises,
    Iterable<WorkoutSession> completedHistory,
  ) {
    final previousByExercise = <String, double>{};
    for (final session in completedHistory) {
      if (!session.isCompleted || session.deletedAt != null) continue;
      for (final exercise in session.exercises) {
        final key = exercise.name.trim().toLowerCase();
        for (final set in exercise.sets) {
          if (set.reps == 0 && set.weight == 0) continue;
          final old = previousByExercise[key] ?? 0;
          if (set.weight > old) previousByExercise[key] = set.weight;
        }
      }
    }

    final results = <PRResult>[];
    final bestCandidateByExercise =
        <String, ({Exercise exercise, double weight, int reps})>{};
    for (final exercise in exercises) {
      final key = exercise.name.trim().toLowerCase();
      for (final set in exercise.sets) {
        if (set.reps == 0 && set.weight == 0) continue;
        final best = bestCandidateByExercise[key];
        if (best == null || set.weight > best.weight) {
          bestCandidateByExercise[key] = (
            exercise: exercise,
            weight: set.weight,
            reps: set.reps,
          );
        }
      }
    }
    for (final entry in bestCandidateByExercise.entries) {
      final previous = previousByExercise[entry.key] ?? 0;
      final candidate = entry.value;
      if (candidate.weight > previous) {
        results.add(
          PRResult(
            exerciseName: candidate.exercise.name,
            previousPR: previous,
            newPR: candidate.weight,
            reps: candidate.reps,
          ),
        );
      }
    }
    return results;
  }
}
