import '../services/hive_service.dart';

class StatsRepository {
  double getExercisePR(String exerciseName, String? splitId) {
    return HiveService.getExercisePR(exerciseName, splitId);
  }

  List<String> getAllExerciseNames(String? splitId) {
    return HiveService.getAllExerciseNames(splitId);
  }

  Map<String, double> getAllExercisePRs(String? splitId) {
    return HiveService.getAllExercisePRs(splitId);
  }

  List<Map<String, dynamic>> getExerciseProgression(
    String exerciseName,
    String? splitId,
  ) {
    return HiveService.getExerciseProgression(exerciseName, splitId);
  }

  int getWorkoutsThisWeek(String? splitId) {
    return HiveService.getWorkoutsThisWeek(splitId);
  }

  Map<int, int> getWorkoutFrequency(int weeksBack, String? splitId) {
    return HiveService.getWorkoutFrequency(weeksBack, splitId);
  }
}
