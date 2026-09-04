import 'package:flutter/foundation.dart';
import '../models/set.dart' as gym;
import '../models/exercise.dart';
import '../repositories/workout_session_repository.dart';
import '../services/hive_service.dart';
import 'split_provider.dart';

class ProgressionProvider with ChangeNotifier {
  final WorkoutSessionRepository _repository = WorkoutSessionRepository();
  final SplitProvider? _splitProvider;

  ProgressionProvider([this._splitProvider]) {
    _splitProvider?.addListener(notifyListeners);
  }

  String getSuggestion(String exerciseName, int targetReps) {
    final splitId = _splitProvider?.activeSplitId;
    final lastSession =
        splitId == null
            ? HiveService.getLastSessionForExercise(exerciseName, null)
            : _repository.getLastSessionForExercise(exerciseName, splitId);

    if (lastSession == null) {
      return 'No previous data';
    }

    Exercise? lastExercise;
    for (var exercise in lastSession.exercises) {
      if (exercise.name.toLowerCase() == exerciseName.toLowerCase()) {
        lastExercise = exercise;
        break;
      }
    }

    if (lastExercise == null || lastExercise.sets.isEmpty) {
      return 'No previous data';
    }

    // Check if all sets were completed (all have reps > 0)
    bool allSetsCompleted = lastExercise.sets.every((set) => set.reps > 0);

    if (!allSetsCompleted) {
      return 'Last: ${_formatSets(lastExercise.sets)} → Try completing all sets';
    }

    // Get last weight and reps
    double lastWeight = lastExercise.sets.last.weight;
    int lastReps = lastExercise.sets.last.reps;

    // Progression logic
    if (lastReps >= targetReps) {
      // Hit target reps, increase weight
      double newWeight = lastWeight + 2.5;
      return 'Last: ${lastWeight}kg x $lastReps → Suggested: ${newWeight}kg x $targetReps';
    } else {
      // Didn't hit target reps, increase reps
      int newReps = lastReps + 1;
      return 'Last: ${lastWeight}kg x $lastReps → Suggested: ${lastWeight}kg x $newReps';
    }
  }

  String _formatSets(List<gym.Set> sets) {
    return sets.map((s) => '${s.weight}kg x ${s.reps}').join(', ');
  }

  @override
  void dispose() {
    _splitProvider?.removeListener(notifyListeners);
    super.dispose();
  }
}
