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
  final days = calendarDaysBetween(date, DateTime.now());

  if (days <= 0) return 'TODAY';
  if (days == 1) return 'YESTERDAY';
  if (days < 30) return '${days}D AGO';
  return formatShortDate(date);
}

/// Sentence-case recency for interface copy: `Today`, `Yesterday`,
/// `3 days ago`, `2 weeks ago`, `4 months ago`.
String formatDaysAgo(DateTime date, {DateTime? now}) {
  final days = calendarDaysBetween(date, now ?? DateTime.now());

  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 14) return '$days days ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  return '${days ~/ 30} months ago';
}

/// Whole calendar days from [from] to [to], ignoring the time of day.
///
/// Counted on UTC dates: subtracting two local midnights across a daylight
/// saving change gives a 23-hour day, which `inDays` rounds down to zero.
int calendarDaysBetween(DateTime from, DateTime to) =>
    _utcDate(to).difference(_utcDate(from)).inDays;

DateTime _utcDate(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Local midnight on the Monday of [date]'s week — the same week the
/// dashboard heatmap draws.
DateTime startOfWeek(DateTime date) =>
    DateTime(date.year, date.month, date.day - (date.weekday - 1));

/// `push day` → `Push Day`, for display only; stored names keep their case.
String titleCase(String name) {
  return name
      .trim()
      .split(RegExp(r'\s+'))
      .map(
        (word) =>
            word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
