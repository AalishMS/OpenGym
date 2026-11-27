import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import '../../utils/workout_context.dart';
import '../app_button.dart';
import 'history_journal_data.dart';

/// Width of the date rail that runs down the left of the journal.
const double _railWidth = 44;

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
/// The date sits on a rail at the left. The workout's name runs the full
/// width beside it, over its block, week and duration, with the PR flag at
/// the bottom right. A second workout on the same day leaves its date out,
/// and the rule between the two starts after the rail.
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
        final compact = constraints.maxWidth < 310 || textScale >= 1.6;
        final inset = compact ? 0.0 : _railWidth + AppSpacing.md;
        final Widget content;
        if (compact) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDate) ...[
                _HistoryDate(date: session.date, horizontal: true),
                const SizedBox(height: AppSpacing.xs),
              ],
              _WorkoutSummary(summary: summary, compact: true),
            ],
          );
        } else {
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _railWidth,
                child:
                    showDate
                        ? _HistoryDate(date: session.date, horizontal: false)
                        : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _WorkoutSummary(summary: summary, compact: false),
              ),
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

class _HistoryDate extends StatelessWidget {
  final DateTime date;
  final bool horizontal;

  const _HistoryDate({required this.date, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    final day = Text(
      '${date.day}',
      style: AppTypography.figures(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.1,
        color: textPrimaryColor(context),
      ),
    );
    final weekday = Text(
      historyWeekday(date),
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );
    if (horizontal) {
      return Row(
        key: const ValueKey('history-date'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [day, const SizedBox(width: AppSpacing.sm), weekday],
      );
    }
    return Padding(
      key: const ValueKey('history-date'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [day, const SizedBox(height: AppSpacing.xxs), weekday],
      ),
    );
  }
}

class _WorkoutSummary extends StatelessWidget {
  final HistoryWorkoutSummary summary;

  /// Large text and narrow rows let the name wrap as far as it needs.
  final bool compact;

  const _WorkoutSummary({required this.summary, required this.compact});

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    final textTheme = Theme.of(context).textTheme;
    final duration = knownDurationSeconds(session.durationSeconds);
    final details = [
      workoutContext(session),
      if (duration != null) formatStatisticsDuration(duration),
      if (summary.statistics.totalSets == 0) 'No sets logged',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          session.planName,
          maxLines: compact ? null : 2,
          overflow: compact ? null : TextOverflow.ellipsis,
          style: textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    details.join(' · '),
                    style: AppTypography.figures(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                      color: textSecondaryColor(context),
                    ),
                  ),
                  // A search that found this workout by an exercise names
                  // it, so the match explains itself.
                  if (summary.matchedExercises.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      summary.matchedExercises.join(', '),
                      key: const ValueKey('history-matched-exercises'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (summary.hasPersonalRecord) ...[
              const SizedBox(width: AppSpacing.md),
              const HistoryRecordBadge(),
            ],
          ],
        ),
      ],
    );
  }
}

/// History's compact record flag.
class HistoryRecordBadge extends StatelessWidget {
  const HistoryRecordBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final foreground = onAccentColor(context);
    return Semantics(
      label: 'Personal record',
      excludeSemantics: true,
      child: DecoratedBox(
        key: const ValueKey('history-personal-record-pill'),
        decoration: BoxDecoration(
          color: accentFillColor(context),
          borderRadius: AppRadius.badge,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs + AppSpacing.xxs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.trophy, size: 11, color: foreground),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'PR',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
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
