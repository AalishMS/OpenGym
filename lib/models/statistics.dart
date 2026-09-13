import 'workout_session.dart';

enum StatisticsPeriod { fourWeeks, twelveWeeks, sixMonths, oneYear, allTime }

extension StatisticsPeriodLabel on StatisticsPeriod {
  String get label => switch (this) {
    StatisticsPeriod.fourWeeks => '4 weeks',
    StatisticsPeriod.twelveWeeks => '12 weeks',
    StatisticsPeriod.sixMonths => '6 months',
    StatisticsPeriod.oneYear => '1 year',
    StatisticsPeriod.allTime => 'All time',
  };

  int? get weekCount => switch (this) {
    StatisticsPeriod.fourWeeks => 4,
    StatisticsPeriod.twelveWeeks => 12,
    StatisticsPeriod.sixMonths => 26,
    StatisticsPeriod.oneYear => 52,
    StatisticsPeriod.allTime => null,
  };
}

enum ExerciseMetric {
  estimatedOneRepMax,
  bestWeight,
  bestSetVolume,
  sessionVolume,
  totalReps,
  totalSets,
}

extension ExerciseMetricLabel on ExerciseMetric {
  String get label => switch (this) {
    ExerciseMetric.estimatedOneRepMax => 'Estimated 1RM',
    ExerciseMetric.bestWeight => 'Best weight',
    ExerciseMetric.bestSetVolume => 'Best set volume',
    ExerciseMetric.sessionVolume => 'Session volume',
    ExerciseMetric.totalReps => 'Total reps',
    ExerciseMetric.totalSets => 'Total sets',
  };
}

enum RecordType { estimatedOneRepMax, heaviestWeight, repBest, setVolume }

extension RecordTypeLabel on RecordType {
  String label([int? reps]) => switch (this) {
    RecordType.estimatedOneRepMax => 'New estimated 1RM',
    RecordType.heaviestWeight => 'New heaviest weight',
    RecordType.repBest =>
      reps == null ? 'New rep-count best' : 'New $reps-rep best',
    RecordType.setVolume => 'New best set volume',
  };
}

class SessionStatistics {
  final WorkoutSession session;
  final double volumeLoad;
  final int totalReps;
  final int totalSets;

  const SessionStatistics({
    required this.session,
    required this.volumeLoad,
    required this.totalReps,
    required this.totalSets,
  });

  int? get durationSeconds => session.durationSeconds;
}

class WeeklyTrainingValue {
  final DateTime weekStart;
  final double volumeLoad;

  const WeeklyTrainingValue({
    required this.weekStart,
    required this.volumeLoad,
  });
}

class RecordAchievement {
  final RecordType type;
  final double value;
  final double setWeight;
  final int setReps;
  final int? reps;

  const RecordAchievement({
    required this.type,
    required this.value,
    required this.setWeight,
    required this.setReps,
    this.reps,
  });
}

class RecordEvent {
  final String exerciseName;
  final WorkoutSession session;
  final List<RecordAchievement> achievements;

  const RecordEvent({
    required this.exerciseName,
    required this.session,
    required this.achievements,
  });
}

class ExerciseProgressPoint {
  final WorkoutSession session;
  final double value;
  final double bestSetWeight;
  final int bestSetReps;

  const ExerciseProgressPoint({
    required this.session,
    required this.value,
    required this.bestSetWeight,
    required this.bestSetReps,
  });
}

class ExerciseProgress {
  final List<ExerciseProgressPoint> points;
  final double? currentValue;
  final double? change;
  final double? bestSetWeight;
  final int? bestSetReps;
  final int sessionCount;

  const ExerciseProgress({
    required this.points,
    required this.currentValue,
    required this.change,
    required this.bestSetWeight,
    required this.bestSetReps,
    required this.sessionCount,
  });
}
