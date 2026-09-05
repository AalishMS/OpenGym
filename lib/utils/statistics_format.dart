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

String formatTrainingValue(
  double value,
  TrainingMetric metric,
  String weightUnit,
) => switch (metric) {
  TrainingMetric.volumeLoad => formatVolumeLoad(value, weightUnit),
  TrainingMetric.sets || TrainingMetric.reps => formatAnalyticsNumber(value),
  TrainingMetric.duration => formatStatisticsDuration(value.round()),
};

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

String formatStatisticsDuration(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

String formatStatisticsDate(DateTime date) {
  const months = [
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
  return '${date.day} ${months[date.month - 1]} ${date.year}';
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

String formatWeekRange(DateTime start) {
  final end = DateTime(start.year, start.month, start.day + 6);
  return '${formatIsoWeek(start)} · ${isoWeek(start).year} · '
      '${formatStatisticsDate(start)} – ${formatStatisticsDate(end)}';
}

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
