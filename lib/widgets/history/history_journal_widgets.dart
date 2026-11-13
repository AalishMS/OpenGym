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
    const quiet = OutlineInputBorder(
      borderRadius: AppRadius.field,
      borderSide: BorderSide.none,
    );
    return TextField(
      key: const ValueKey('history-search-field'),
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search workouts or exercises',
        isDense: true,
        filled: true,
        fillColor: surfaceColor(context),
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
        border: quiet,
        enabledBorder: quiet,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide(color: accentColor(context)),
        ),
      ),
    );
  }
}

/// A month in the journal: its name, then how much training it held.
class HistoryMonthHeader extends StatelessWidget {
  final HistoryMonthGroup group;
  final String weightUnit;

  const HistoryMonthHeader({
    required this.group,
    this.weightUnit = 'kg',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final count = group.workouts.length;
    final volume = group.workouts.fold<double>(
      0,
      (sum, workout) => sum + workout.statistics.volumeLoad,
    );
    final tally = [
      '$count workout${count == 1 ? '' : 's'}',
      if (volume > 0) formatVolumeLoad(volume, weightUnit),
    ].join(' · ');
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
                tally,
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
/// The date sits on a rail at the left, the workout in the middle, and the
/// volume and set count in a right-aligned column so they line up down the
/// month. A second workout on the same day leaves its date out, and the rule
/// between the two starts after the rail.
class HistoryWorkoutRow extends StatelessWidget {
  final HistoryWorkoutSummary summary;
  final String weightUnit;
  final VoidCallback onTap;
  final bool showDate;
  final HistoryRowRule rule;

  const HistoryWorkoutRow({
    required this.summary,
    required this.weightUnit,
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
              _WorkoutSummary(
                summary: summary,
                weightUnit: weightUnit,
                inlineFigures: true,
              ),
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
                child: _WorkoutSummary(
                  summary: summary,
                  weightUnit: weightUnit,
                  inlineFigures: false,
                ),
              ),
            ],
          );
        }
        return Semantics(
          button: true,
          hint: 'Opens workout details',
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
                      color: borderColor(context),
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
  final String weightUnit;

  /// Large text and narrow rows put the figures on the context line instead
  /// of in their own column.
  final bool inlineFigures;

  const _WorkoutSummary({
    required this.summary,
    required this.weightUnit,
    required this.inlineFigures,
  });

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    final stats = summary.statistics;
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final duration = knownDurationSeconds(session.durationSeconds);
    final hasSets = stats.totalSets > 0;
    final volume = formatVolumeLoad(stats.volumeLoad, weightUnit);
    final sets = '${stats.totalSets} set${stats.totalSets == 1 ? '' : 's'}';
    final exerciseNames = [
      for (final exercise in session.exercises)
        if (exercise.name.trim().isNotEmpty) exercise.name.trim(),
    ];
    final details = [
      workoutContext(session),
      if (duration != null) formatStatisticsDuration(duration),
      if (!hasSets) 'No sets logged',
      if (hasSets && inlineFigures) ...[volume, sets],
    ];

    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            session.planName,
            maxLines: inlineFigures ? null : 2,
            overflow: inlineFigures ? null : TextOverflow.ellipsis,
            style: textTheme.titleLarge,
          ),
        ),
        if (summary.hasPersonalRecord) ...[
          const SizedBox(width: AppSpacing.sm),
          const HistoryRecordBadge(),
        ],
      ],
    );

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: AppSpacing.xxs),
        Text(
          details.join(' · '),
          style: AppTypography.figures(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: secondary,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inlineFigures || !hasSets)
          heading
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: AppSpacing.lg),
              _HistoryFigures(volume: volume, sets: sets),
            ],
          ),
        if (exerciseNames.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            exerciseNames.join(', '),
            maxLines: inlineFigures ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// Volume over the set count, right-aligned so the figures of a month line up
/// down the page.
class _HistoryFigures extends StatelessWidget {
  final String volume;
  final String sets;

  const _HistoryFigures({required this.volume, required this.sets});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Volume: $volume, $sets',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            volume,
            style: AppTypography.figures(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            sets,
            style: AppTypography.figures(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.45,
              color: textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact record flag shared by History and Workout details.
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
