import 'training_block.dart';
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

  /// Fits an equal-width segment; [label] is what a screen reader says.
  String get shortLabel => switch (this) {
    StatisticsPeriod.fourWeeks => '4W',
    StatisticsPeriod.twelveWeeks => '12W',
    StatisticsPeriod.sixMonths => '6M',
    StatisticsPeriod.oneYear => '1Y',
    StatisticsPeriod.allTime => 'All',
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

  /// Fits a chip; [label] stays the name used in readouts and pickers.
  String get shortLabel => switch (this) {
    ExerciseMetric.estimatedOneRepMax => 'Est. 1RM',
    ExerciseMetric.bestWeight => 'Top weight',
    ExerciseMetric.bestSetVolume => 'Best set',
    ExerciseMetric.sessionVolume => 'Volume',
    ExerciseMetric.totalReps => 'Reps',
    ExerciseMetric.totalSets => 'Sets',
  };

  /// One plain sentence, so nobody has to know the jargon to read a chart.
  String get description => switch (this) {
    ExerciseMetric.estimatedOneRepMax =>
      'The most you could lift for one rep, estimated from your best set.',
    ExerciseMetric.bestWeight => 'The heaviest weight you lifted each workout.',
    ExerciseMetric.bestSetVolume =>
      'Your biggest single set each workout: weight × reps.',
    ExerciseMetric.sessionVolume =>
      'Weight × reps, added up over every set each workout.',
    ExerciseMetric.totalReps => 'All the reps you did each workout.',
    ExerciseMetric.totalSets => 'How many sets you did each workout.',
  };
}

enum RecordType {
  estimatedOneRepMax,
  heaviestWeight,
  repBest,
  setVolume,

  /// The most reps in one bodyweight set (weight 0).
  mostReps,

  /// The longest hold of a timed exercise, in seconds.
  longestHold,
}

extension RecordTypeLabel on RecordType {
  /// The record's name, such as `Heaviest weight` or `5-rep best`.
  String title([int? reps]) => switch (this) {
    RecordType.estimatedOneRepMax => 'Estimated 1RM',
    RecordType.heaviestWeight => 'Heaviest weight',
    RecordType.repBest => reps == null ? 'Rep-count best' : '$reps-rep best',
    RecordType.setVolume => 'Best set volume',
    RecordType.mostReps => 'Most reps',
    RecordType.longestHold => 'Longest hold',
  };

  /// [title] announced as new: `New heaviest weight`.
  String label([int? reps]) {
    final name = title(reps);
    return 'New ${name[0].toLowerCase()}${name.substring(1)}';
  }
}

class SessionStatistics {
  final WorkoutSession session;

  /// Weight × reps over performed sets. Bodyweight sets add 0 and timed sets
  /// are left out, since their reps are seconds.
  final double volumeLoad;

  /// Reps over performed sets, leaving out timed sets.
  final int totalReps;

  /// Every performed set, timed ones included.
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

/// One record a set broke. See `StatisticsAnalyticsService.recordEvents` for
/// the rules that decide what counts.
class RecordAchievement {
  final RecordType type;

  /// The new best: kilograms for the weight records, kilograms for set
  /// volume, reps for [RecordType.mostReps] and seconds for
  /// [RecordType.longestHold].
  final double value;
  final double setWeight;
  final int setReps;

  /// The rep count a [RecordType.repBest] is for; null for the other types.
  final int? reps;

  /// The best this record beat, in the same unit as [value]: the heaviest
  /// weight, estimated 1RM, set volume, most bodyweight reps or longest hold
  /// before this workout, or for a rep best the heaviest weight lifted for
  /// [reps] or more reps. Null when the producer did not supply one.
  final double? previousValue;

  /// Where the set that broke the record sits in its workout: the index into
  /// `WorkoutSession.exercises`, then into that exercise's `sets` (counting
  /// sets saved at zero reps, so it matches the saved row).
  final int? exerciseIndex;
  final int? setIndex;

  const RecordAchievement({
    required this.type,
    required this.value,
    required this.setWeight,
    required this.setReps,
    this.reps,
    this.previousValue,
    this.exerciseIndex,
    this.setIndex,
  });
}

/// The records one exercise set in one workout. An exercise logged twice in a
/// workout under the same name still yields one event.
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

/// What an [ExerciseProgress] counts instead of the chosen measure, for a lift
/// the measure can't describe.
enum ProgressFallback {
  /// The chosen measure.
  none,

  /// Best reps in one set: a lift whose sets in range are all at weight 0,
  /// under a weight-based measure.
  bestReps,

  /// Longest hold in seconds: a timed lift under any measure but sets.
  bestTime,
}

class ExerciseProgress {
  final List<ExerciseProgressPoint> points;
  final double? currentValue;
  final double? change;
  final double? bestSetWeight;
  final int? bestSetReps;
  final int sessionCount;

  /// What [points] measure when it isn't the measure asked for.
  final ProgressFallback fallback;

  const ExerciseProgress({
    required this.points,
    required this.currentValue,
    required this.change,
    required this.bestSetWeight,
    required this.bestSetReps,
    required this.sessionCount,
    this.fallback = ProgressFallback.none,
  });
}

/// What a block-comparison bar measures, as an average per trained week.
enum BlockMeasure { sets, volume, workouts }

extension BlockMeasureLabel on BlockMeasure {
  String get label => switch (this) {
    BlockMeasure.sets => 'Sets',
    BlockMeasure.volume => 'Volume',
    BlockMeasure.workouts => 'Workouts',
  };
}

class BlockWeekStatistics {
  /// Null for a planned week nobody has reached yet.
  final String? weekId;
  final int number;
  final int workouts;
  final int sets;
  final double volumeLoad;

  const BlockWeekStatistics({
    required this.weekId,
    required this.number,
    this.workouts = 0,
    this.sets = 0,
    this.volumeLoad = 0,
  });

  bool get reached => weekId != null;
}

/// First-to-latest change of one lift's best estimated 1RM inside a block.
class LiftGain {
  final String exerciseName;
  final double start;
  final double end;

  const LiftGain({
    required this.exerciseName,
    required this.start,
    required this.end,
  });

  double get change => end - start;
  double get percent => start == 0 ? 0 : change / start * 100;
}

class BlockStatistics {
  final TrainingBlock block;

  /// Reached weeks in order, then any planned weeks still ahead.
  final List<BlockWeekStatistics> weeks;
  final int workouts;
  final int sets;
  final double volumeLoad;
  final int records;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// The week the latest workout of this block was logged in.
  final String? latestWeekId;
  final List<LiftGain> gains;

  const BlockStatistics({
    required this.block,
    required this.weeks,
    required this.workouts,
    required this.sets,
    required this.volumeLoad,
    required this.records,
    required this.firstDate,
    required this.lastDate,
    required this.latestWeekId,
    required this.gains,
  });

  /// Weeks with at least one workout: the fair divisor between blocks of
  /// different lengths.
  int get trainedWeeks => weeks.where((week) => week.workouts > 0).length;

  BlockWeekStatistics? get latestWeek =>
      weeks.where((week) => week.weekId == latestWeekId).firstOrNull;

  /// Planned length, stretched when weeks were added past the plan.
  int get plannedWeeks => weeks.isEmpty ? 0 : weeks.last.number;

  double perWeek(BlockMeasure measure) {
    if (trainedWeeks == 0) return 0;
    final total = switch (measure) {
      BlockMeasure.sets => sets.toDouble(),
      BlockMeasure.volume => volumeLoad,
      BlockMeasure.workouts => workouts.toDouble(),
    };
    return total / trainedWeeks;
  }
}

class LiftSummary {
  final String exerciseName;
  final ExerciseProgress progress;

  const LiftSummary({required this.exerciseName, required this.progress});
}
