import '../models/statistics.dart';
import 'format.dart';

const double _poundsPerKilogram = 2.2046226218;

double displayWeight(double kilograms, String weightUnit) =>
    weightUnit == 'lbs' ? kilograms * _poundsPerKilogram : kilograms;

String formatAnalyticsNumber(double value, {int decimals = 0}) {
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final digits = parts.first;
  final sign = digits.startsWith('-') ? '-' : '';
  final unsigned = sign.isEmpty ? digits : digits.substring(1);
  final buffer = StringBuffer(sign);
  for (var index = 0; index < unsigned.length; index++) {
    if (index > 0 && (unsigned.length - index) % 3 == 0) buffer.write(',');
    buffer.write(unsigned[index]);
  }
  if (parts.length > 1) buffer.write('.${parts[1]}');
  return buffer.toString();
}

/// A signed change with a true minus sign (U+2212). A hyphen is narrower than
/// the plus sign and sits low, so a negative change read as a typo next to a
/// positive one.
String formatSignedChange(num change, String Function(double magnitude) format) {
  final magnitude = format(change.abs().toDouble());
  // A change that rounds away reads as no change, not as "−0%".
  if (change == 0 || magnitude == format(0)) return magnitude;
  return '${change > 0 ? '+' : '\u2212'}$magnitude';
}

String formatAnalyticsWeight(double kilograms, String weightUnit) {
  final converted = displayWeight(kilograms, weightUnit);
  return '${formatWeight(converted)} $weightUnit';
}

String formatVolumeLoad(double kilograms, String weightUnit) {
  if (weightUnit == 'kg' && kilograms >= 1000) {
    final tonnes = kilograms / 1000;
    final decimals = tonnes >= 10 ? 0 : 1;
    return '${tonnes.toStringAsFixed(decimals)} t';
  }
  final converted = displayWeight(kilograms, weightUnit);
  return '${formatAnalyticsNumber(converted)} $weightUnit';
}

String formatExerciseValue(
  double value,
  ExerciseMetric metric,
  String weightUnit,
) => switch (metric) {
  ExerciseMetric.estimatedOneRepMax ||
  ExerciseMetric.bestWeight => formatAnalyticsWeight(value, weightUnit),
  ExerciseMetric.bestSetVolume ||
  ExerciseMetric.sessionVolume => formatVolumeLoad(value, weightUnit),
  ExerciseMetric.totalReps ||
  ExerciseMetric.totalSets => formatAnalyticsNumber(value),
};

/// A recorded duration worth showing, or null when it is unknown. Sessions
/// start at 0 seconds, so anything under a minute means the timer never ran
/// and would only print as "0m".
int? knownDurationSeconds(int? seconds) =>
    seconds == null || seconds < 60 ? null : seconds;

String formatStatisticsDuration(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatStatisticsDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// `19 Oct`: a date inside a span whose year is already clear.
String formatDayMonth(DateTime date) =>
    '${date.day} ${_months[date.month - 1]}';

/// `13 – 29 Oct 2026`, `28 Sep – 12 Oct 2026`, or both years when they differ.
String formatDateSpan(DateTime start, DateTime end) {
  if (start.year != end.year) {
    return '${formatStatisticsDate(start)} – ${formatStatisticsDate(end)}';
  }
  if (start.month != end.month) {
    return '${formatDayMonth(start)} – ${formatStatisticsDate(end)}';
  }
  if (start.day == end.day) return formatStatisticsDate(end);
  return '${start.day} – ${formatStatisticsDate(end)}';
}

String formatWeekLabel(DateTime date) => '${date.day}/${date.month}';

/// ISO week dates use Thursday to determine the week-year (not calendar year).
({int year, int week}) isoWeek(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final first = DateTime.utc(thursday.year, 1, 1);
  return (
    year: thursday.year,
    week: thursday.difference(first).inDays ~/ 7 + 1,
  );
}

String formatIsoWeek(DateTime date) => 'W${isoWeek(date).week}';

String formatWeekRange(DateTime start) =>
    formatDateSpan(start, DateTime(start.year, start.month, start.day + 6));

String formatChartNumber(double value) {
  final magnitude = value.abs();
  if (magnitude >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}m';
  if (magnitude >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return formatWeight(value);
}

String formatExactVolume(double kilograms, String unit) =>
    '${formatAnalyticsNumber(displayWeight(kilograms, unit), decimals: 2).replaceFirst(RegExp(r'\.?0+$'), '')} $unit';

String formatChartExerciseValue(
  double value,
  ExerciseMetric metric,
  String unit,
) => switch (metric) {
  ExerciseMetric.bestWeight ||
  ExerciseMetric.estimatedOneRepMax ||
  ExerciseMetric.bestSetVolume ||
  ExerciseMetric.sessionVolume => formatExactVolume(value, unit),
  _ => formatExerciseValue(value, metric, unit),
};

/// A hold of [seconds], as timed sets store it in `reps`: `45 s` under 90
/// seconds, `1:30` from 90 seconds up. Negative values (a change) keep their
/// sign.
String formatHoldTime(int seconds) {
  final sign = seconds < 0 ? '-' : '';
  final value = seconds.abs();
  if (value < 90) return '$sign$value s';
  return '$sign${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
}

/// [formatHoldTime] for a screen reader: `45 seconds`, `1 minute 30 seconds`.
String formatHoldTimeSpoken(int seconds) {
  String unit(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
  final sign = seconds < 0 ? 'minus ' : '';
  final value = seconds.abs();
  if (value < 90) return '$sign${unit(value, 'second')}';
  final rest = value % 60;
  return '$sign${unit(value ~/ 60, 'minute')}'
      '${rest == 0 ? '' : ' ${unit(rest, 'second')}'}';
}

/// `1 rep`, `12 reps`.
String formatRepCount(int reps) => '$reps rep${reps.abs() == 1 ? '' : 's'}';

/// The heading over a set's count column: `Time` for a timed exercise,
/// `Reps` otherwise.
String setCountLabel({required bool timed}) => timed ? 'Time' : 'Reps';

/// A set's count cell: the reps, or the hold time for a timed exercise.
String formatSetCount(int reps, {required bool timed}) =>
    timed ? formatHoldTime(reps) : '$reps';

/// One performed set on one line: `80 kg × 5`, `12 reps` at weight 0, or for
/// a timed exercise `45 s` (`10 kg · 45 s` when loaded).
String formatSetSummary(
  double kilograms,
  int reps,
  String weightUnit, {
  required bool timed,
}) {
  if (timed) {
    final time = formatHoldTime(reps);
    return kilograms > 0
        ? '${formatAnalyticsWeight(kilograms, weightUnit)} · $time'
        : time;
  }
  if (kilograms <= 0) return formatRepCount(reps);
  return '${formatAnalyticsWeight(kilograms, weightUnit)} × $reps';
}

/// The record's name for display: `Heaviest weight`, `5-rep best`.
String formatRecordTitle(RecordAchievement achievement) =>
    achievement.type.title(achievement.reps);

String _recordAmount(RecordType type, double value, String weightUnit) =>
    switch (type) {
      RecordType.estimatedOneRepMax ||
      RecordType.heaviestWeight ||
      RecordType.repBest => formatAnalyticsWeight(value, weightUnit),
      RecordType.setVolume => formatVolumeLoad(value, weightUnit),
      RecordType.mostReps => formatRepCount(value.round()),
      RecordType.longestHold => formatHoldTime(value.round()),
    };

/// The new best a record set, in display units: `100 kg`, `12 reps`, `1:30`.
String formatRecordValue(RecordAchievement achievement, String weightUnit) =>
    _recordAmount(achievement.type, achievement.value, weightUnit);

/// The best a record beat, in the same display units as
/// [formatRecordValue], or null when it isn't known.
String? formatRecordPreviousValue(
  RecordAchievement achievement,
  String weightUnit,
) {
  final previous = achievement.previousValue;
  return previous == null
      ? null
      : _recordAmount(achievement.type, previous, weightUnit);
}

/// What an Exercise progress value measures, for headings and screen
/// readers: the measure's own label, or what the lift fell back to.
String progressMeasureLabel(ExerciseMetric metric, ProgressFallback fallback) =>
    switch (fallback) {
      ProgressFallback.none => metric.label,
      ProgressFallback.bestReps => 'Best reps in one set',
      ProgressFallback.bestTime => 'Longest hold',
    };

/// An Exercise progress value (or a change in one) in its display unit:
/// reps or a hold time when the lift fell back, otherwise as
/// [formatChartExerciseValue] prints the measure.
String formatProgressValue(
  double value,
  ExerciseMetric metric,
  ProgressFallback fallback,
  String weightUnit,
) => switch (fallback) {
  ProgressFallback.none => formatChartExerciseValue(value, metric, weightUnit),
  ProgressFallback.bestReps => formatRepCount(value.round()),
  ProgressFallback.bestTime => formatHoldTime(value.round()),
};

/// Whether an Exercise progress value is a weight, so it is converted to the
/// display unit before it is plotted.
bool progressValueIsWeight(ExerciseMetric metric, ProgressFallback fallback) =>
    fallback == ProgressFallback.none &&
    metric != ExerciseMetric.totalReps &&
    metric != ExerciseMetric.totalSets;

/// The plot's unit for an Exercise progress chart: the weight unit, `reps`,
/// `sets`, or `s` for a hold.
String progressAxisUnit(
  ExerciseMetric metric,
  ProgressFallback fallback,
  String weightUnit,
) => switch (fallback) {
  ProgressFallback.bestReps => 'reps',
  ProgressFallback.bestTime => 's',
  ProgressFallback.none =>
    metric == ExerciseMetric.totalReps
        ? 'reps'
        : metric == ExerciseMetric.totalSets
        ? 'sets'
        : weightUnit,
};
