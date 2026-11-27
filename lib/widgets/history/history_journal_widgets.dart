import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import '../../utils/workout_context.dart';
import '../app_button.dart';
import 'history_journal_data.dart';

/// Width of the date column that runs down the left of the journal: room for
/// a two-digit day and a weekday at the row's small text size.
const double _railWidth = 32;

class HistorySearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const HistorySearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('history-search-field'),
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search workouts or exercises',
        isDense: true,
        prefixIcon: Icon(
          LucideIcons.search,
          size: 18,
          color: textSecondaryColor(context),
        ),
        suffixIcon:
            controller.text.isEmpty
                ? null
                : AppIconButton(
                  label: 'Clear search',
                  icon: LucideIcons.x,
                  onPressed: onClear,
                ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      ),
    );
  }
}

/// A month in the journal: its name, then how many workouts it held.
class HistoryMonthHeader extends StatelessWidget {
  final HistoryMonthGroup group;

  const HistoryMonthHeader({required this.group, super.key});

  @override
  Widget build(BuildContext context) {
    final count = group.workouts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.end,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Semantics(
              header: true,
              child: Text(
                historyMonthLabel(group.month, group.year),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                '$count workout${count == 1 ? '' : 's'}',
                style: AppTypography.figures(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondaryColor(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Divider(height: 1, thickness: 1, color: textPrimaryColor(context)),
      ],
    );
  }
}

/// The rule a journal row draws under itself.
enum HistoryRowRule {
  /// The last workout of a month: the next month header opens its own space.
  none,

  /// The next workout is on another day: the rule spans the whole row.
  full,

  /// The next workout is on the same day: the rule starts after the date
  /// rail, so both workouts read as one day.
  inset,
}

/// One workout in the journal, as a ruled row rather than a card.
///
/// A row is two lines of text on one grid. The date is that grid's first
/// column, set no larger than the details so the workout's name leads: the
/// day sits on the name's baseline and the weekday on the details'. The PR
/// mark ends the details line. A second workout on the same day leaves its
/// date out, and the rule between the two starts after the date column.
class HistoryWorkoutRow extends StatelessWidget {
  final HistoryWorkoutSummary summary;
  final VoidCallback onTap;
  final bool showDate;
  final HistoryRowRule rule;

  const HistoryWorkoutRow({
    required this.summary,
    required this.onTap,
    this.showDate = true,
    this.rule = HistoryRowRule.none,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        // Narrow rows and large text put the date above the workout.
        final compact = constraints.maxWidth < 310 || textScale >= 1.6;
        final inset = compact ? 0.0 : _railWidth + AppSpacing.md;
        final name = _WorkoutName(summary: summary, compact: compact);
        final details = _WorkoutDetails(summary: summary);
        final Widget content;
        if (compact) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDate) ...[
                _HistoryDate(date: session.date),
                const SizedBox(height: AppSpacing.xxs),
              ],
              name,
              const SizedBox(height: AppSpacing.xxs),
              details,
            ],
          );
        } else {
          Widget line(Widget? rail, Widget body) => Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(width: _railWidth, child: showDate ? rail : null),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: body),
            ],
          );
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(
                _HistoryDay(
                  key: const ValueKey('history-date'),
                  date: session.date,
                ),
                name,
              ),
              const SizedBox(height: AppSpacing.xxs),
              line(_HistoryWeekday(date: session.date), details),
            ],
          );
        }
        return Semantics(
          button: true,
          hint: 'Opens the workout',
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: content,
                ),
                if (rule != HistoryRowRule.none)
                  Padding(
                    padding: EdgeInsets.only(
                      left: rule == HistoryRowRule.inset ? inset : 0,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: hairlineColor(context),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The day of the month, on the workout name's baseline. Smaller and lighter
/// than the name, so it indexes the row rather than heading it.
class _HistoryDay extends StatelessWidget {
  final DateTime date;

  const _HistoryDay({required this.date, super.key});

  @override
  Widget build(BuildContext context) => Text(
    '${date.day}',
    style: AppTypography.figures(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.35,
      color: textPrimaryColor(context),
    ),
  );
}

/// The weekday, on the details line's baseline and in its style.
class _HistoryWeekday extends StatelessWidget {
  final DateTime date;

  const _HistoryWeekday({required this.date});

  @override
  Widget build(BuildContext context) =>
      Text(historyWeekday(date), style: _detailsStyle(context));
}

/// The date on a line of its own, above the workout, when the row is narrow.
class _HistoryDate extends StatelessWidget {
  final DateTime date;

  const _HistoryDate({required this.date});

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('history-date'),
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      _HistoryDay(date: date),
      const SizedBox(width: AppSpacing.sm),
      _HistoryWeekday(date: date),
    ],
  );
}

TextStyle _detailsStyle(BuildContext context) => AppTypography.figures(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  height: 1.45,
  color: textSecondaryColor(context),
);

class _WorkoutName extends StatelessWidget {
  final HistoryWorkoutSummary summary;

  /// Large text and narrow rows let the name wrap as far as it needs.
  final bool compact;

  const _WorkoutName({required this.summary, required this.compact});

  @override
  Widget build(BuildContext context) => Text(
    summary.session.planName,
    maxLines: compact ? null : 2,
    overflow: compact ? null : TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleLarge,
  );
}

/// Block, week and duration, with the PR mark at the end of the line.
class _WorkoutDetails extends StatelessWidget {
  final HistoryWorkoutSummary summary;

  const _WorkoutDetails({required this.summary});

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    final duration = knownDurationSeconds(session.durationSeconds);
    final details = [
      workoutContext(session),
      if (duration != null) formatStatisticsDuration(duration),
      if (summary.statistics.totalSets == 0) 'No sets logged',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(details.join(' · '), style: _detailsStyle(context)),
              // A search that found this workout by an exercise names it,
              // so the match explains itself.
              if (summary.matchedExercises.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  summary.matchedExercises.join(', '),
                  key: const ValueKey('history-matched-exercises'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.45),
                ),
              ],
            ],
          ),
        ),
        if (summary.hasPersonalRecord) ...[
          const SizedBox(width: AppSpacing.md),
          HistoryRecordMark(count: summary.recordCount),
        ],
      ],
    );
  }
}

/// How many exercises set a personal record, in accent ink on no ground:
/// most workouts in a good month carry one, so the mark stays quiet down a
/// list, and the count still tells one row from the next.
class HistoryRecordMark extends StatelessWidget {
  final int count;

  const HistoryRecordMark({required this.count, super.key});

  @override
  Widget build(BuildContext context) {
    final ink = accentColor(context);
    return Semantics(
      label: '$count personal record${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('history-record-mark'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Icon(LucideIcons.trophy, size: 12, color: ink),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$count PR${count == 1 ? '' : 's'}',
            style: AppTypography.figures(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.45,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryEmptyState extends StatelessWidget {
  final bool isSearching;
  final VoidCallback onClearSearch;

  const HistoryEmptyState({
    required this.isSearching,
    required this.onClearSearch,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearching ? LucideIcons.searchX : LucideIcons.history,
              size: 36,
              color: textSecondaryColor(context),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isSearching ? 'No matching workouts' : 'No completed workouts',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (isSearching) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton.text(label: 'Clear search', onPressed: onClearSearch),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Finish and log a workout to see it here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
