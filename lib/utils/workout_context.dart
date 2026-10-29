import '../models/workout_session.dart';
import '../services/hive_service.dart';

/// Display context only; retained labels keep orphan history readable.
String workoutContext(WorkoutSession session) {
  final week =
      session.trainingWeekId == null
          ? null
          : HiveService.getTrainingWeekById(session.trainingWeekId!);
  final block =
      week == null ? null : HiveService.getTrainingBlockById(week.blockId);
  if (week == null ||
      block == null ||
      week.splitId != session.splitId ||
      block.splitId != session.splitId ||
      week.userId != session.userId ||
      block.userId != session.userId) {
    return 'Week ${session.weekNumber}';
  }
  final number =
      week.deletedAt == null && block.deletedAt == null
          ? week.number
          : session.weekNumber;
  return '${block.name} · Week $number';
}
