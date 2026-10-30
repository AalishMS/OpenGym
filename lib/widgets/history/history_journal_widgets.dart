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
    return Wrap(
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
    );
  }
}

/// One workout in the journal: the date on a rail, the session on a card.
///
/// The rail draws a hairline down to the next workout of the same month, so a
/// month reads as one continuous log. A second workout on the same day leaves
/// its date out and hangs off the same line.
class HistoryWorkoutRow extends StatelessWidget {
  final HistoryWorkoutSummary summary;
  final String weightUnit;
  final VoidCallback onTap;
  final bool showDate;
  final bool continuesTimeline;

  const HistoryWorkoutRow({
    required this.summary,
    required this.weightUnit,
    required this.onTap,
    this.showDate = true,
    this.continuesTimeline = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    final card = _WorkoutCard(
      summary: summary,
      weightUnit: weightUnit,
      onTap: onTap,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stackDate = constraints.maxWidth < 310 || textScale >= 1.6;
        if (stackDate) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDate) ...[
                  _HistoryDate(date: session.date, horizontal: true),
                  const SizedBox(height: AppSpacing.sm),
                ],
                card,
              ],
            ),
          );
        }
        final rule = borderColor(context);
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _railWidth,
                child: Column(
                  children: [
                    if (showDate)
                      _HistoryDate(date: session.date, horizontal: false),
                    Expanded(
                      child:
                          continuesTimeline
                              ? Padding(
                                padding: EdgeInsets.only(
                                  top: showDate ? AppSpacing.sm : 0,
                                ),
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: rule,
                                ),
                              )
                              : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Align(alignment: Alignment.topCenter, child: card),
                ),
              ),
            ],
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
        height: 1.15,
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
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: [day, const SizedBox(height: AppSpacing.xxs), weekday],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final HistoryWorkoutSummary summary;
  final String weightUnit;
  final VoidCallback onTap;

  const _WorkoutCard({
    required this.summary,
    required this.weightUnit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: borderColor(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: _WorkoutSummaryContent(
            summary: summary,
            weightUnit: weightUnit,
          ),
        ),
      ),
    );
  }
}

class _WorkoutSummaryContent extends StatelessWidget {
  final HistoryWorkoutSummary summary;
  final String weightUnit;

  const _WorkoutSummaryContent({
    required this.summary,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    final stats = summary.statistics;
    final duration = knownDurationSeconds(session.durationSeconds);
    final secondary = textSecondaryColor(context);
    final exerciseNames = [
      for (final exercise in session.exercises)
        if (exercise.name.trim().isNotEmpty) exercise.name.trim(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  session.planName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            if (summary.hasPersonalRecord)
              const Padding(
                padding: EdgeInsets.only(
                  left: AppSpacing.sm,
                  top: AppSpacing.xs,
                ),
                child: HistoryRecordBadge(),
              ),
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                top: AppSpacing.xxs,
              ),
              child: Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: secondary,
                semanticLabel: 'Open workout details',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                workoutContext(session),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (duration != null)
                Semantics(
                  label: 'Duration: ${formatStatisticsDuration(duration)}',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.timer, size: 13, color: secondary),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        formatStatisticsDuration(duration),
                        style: AppTypography.figures(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Divider(height: 1, thickness: 1, color: borderColor(context)),
        const SizedBox(height: AppSpacing.md),
        if (stats.totalSets > 0)
          _HistoryFigures(
            figures: [
              ('Exercises', '${session.exercises.length}'),
              ('Sets', '${stats.totalSets}'),
              ('Volume', formatVolumeLoad(stats.volumeLoad, weightUnit)),
            ],
          )
        else
          Row(
            children: [
              Icon(LucideIcons.circleDashed, size: 14, color: secondary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'No sets logged',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: secondary),
                ),
              ),
            ],
          ),
        if (exerciseNames.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Text(
              exerciseNames.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// A row of labelled training figures that keep the same columns on every
/// card, so a month of workouts can be compared down the page.
class _HistoryFigures extends StatelessWidget {
  final List<(String, String)> figures;

  const _HistoryFigures({required this.figures});

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (final (label, value) in figures)
        Semantics(
          label: '$label: $value',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppTypography.figures(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
    ];
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) {
      return Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        children: cells,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final cell in cells) Expanded(child: cell)],
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
