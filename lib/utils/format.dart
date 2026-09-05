/// Small display formatters shared by the dashboard and workout widgets.
///
/// Weights are stored as `double` but are almost always whole numbers — showing
/// `70kg` instead of `70.0kg` keeps the monospace columns narrow and reads like
/// a log line rather than a float dump.
String formatWeight(double weight) {
  if (weight == weight.roundToDouble()) return weight.toStringAsFixed(0);
  return weight.toStringAsFixed(1);
}

/// Compacts large volume totals: `4200` → `4.2K`.
String formatVolume(num kg) {
  if (kg >= 10000) return '${(kg / 1000).toStringAsFixed(0)}K';
  if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}K';
  return kg.round().toString();
}

/// `d/m` — matches the terse date style already used in History.
String formatShortDate(DateTime date) => '${date.day}/${date.month}';

/// Stopwatch-style elapsed time, expanding to hours only when needed.
String formatDuration(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours == 0 ? '$mm:$ss' : '$hours:$mm:$ss';
}

/// Human-readable recency: `TODAY`, `YESTERDAY`, `3D AGO`, then a date.
String formatRelativeDay(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final then = DateTime(date.year, date.month, date.day);
  final days = today.difference(then).inDays;

  if (days <= 0) return 'TODAY';
  if (days == 1) return 'YESTERDAY';
  if (days < 30) return '${days}D AGO';
  return formatShortDate(date);
}
