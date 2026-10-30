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
      decoration: InputDecoration(
        hintText: 'Search workouts or exercises',
        prefixIcon: Icon(
          LucideIcons.search,
          size: 19,
          color: textSecondaryColor(context),
        ),
        filled: true,
        fillColor: surfaceColor(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        suffixIcon:
            controller.text.isEmpty
                ? null
                : AppIconButton(
                  label: 'Clear search',
                  icon: LucideIcons.x,
                  onPressed: onClear,
                ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class HistoryMonthHeader extends StatelessWidget {
  final HistoryMonthGroup group;

  const HistoryMonthHeader({required this.group, super.key});

  @override
  Widget build(BuildContext context) {
    final count = group.workouts.length;
    final heading = Semantics(
      header: true,
      child: Text(
        historyMonthLabel(group.month, group.year),
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
    final countLabel = Text(
      '$count workout${count == 1 ? '' : 's'}',
      style: Theme.of(context).textTheme.bodySmall,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            280 * MediaQuery.textScalerOf(context).scale(1)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: AppSpacing.xs),
              countLabel,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: AppSpacing.sm),
            countLabel,
          ],
        );
      },
    );
  }
}

class HistoryWorkoutRow extends StatelessWidget {
  final HistoryWorkoutSummary summary;
  final String weightUnit;
  final VoidCallback onTap;

  const HistoryWorkoutRow({
    required this.summary,
    required this.weightUnit,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final session = summary.session;
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
        final stackDate = constraints.maxWidth < 300 || largeText;
        final card = Material(
          color: surfaceColor(context),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: AppRadius.card,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _WorkoutSummaryContent(
                summary: summary,
                weightUnit: weightUnit,
              ),
            ),
          ),
        );
        final date = _HistoryDate(date: session.date, horizontal: stackDate);
        if (stackDate) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [date, const SizedBox(height: AppSpacing.sm), card],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 40, child: date),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: card),
          ],
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
      date.day.toString().padLeft(2, '0'),
      style: AppTypography.figures(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimaryColor(context),
        height: 1.2,
      ),
    );
    final weekday = Text(
      historyWeekday(date),
      style: Theme.of(context).textTheme.labelSmall,
    );
    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [day, const SizedBox(width: AppSpacing.sm), weekday],
      );
    }
    return Padding(
      key: const ValueKey('history-date'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [day, const SizedBox(height: AppSpacing.xxs), weekday],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                session.planName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
            const _OpenIndicator(),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          workoutContext(session),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${session.exercises.length} exercise${session.exercises.length == 1 ? '' : 's'} · ${stats.totalSets} set${stats.totalSets == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (stats.totalSets > 0)
              _HistoryMetric(
                icon: LucideIcons.weight,
                label: 'Volume load',
                value: formatVolumeLoad(stats.volumeLoad, weightUnit),
              )
            else
              Text(
                'No sets logged',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (knownDurationSeconds(session.durationSeconds)
                case final duration?)
              _HistoryMetric(
                icon: LucideIcons.timer,
                label: 'Duration',
                value: formatStatisticsDuration(duration),
              ),
            if (summary.hasPersonalRecord)
              DecoratedBox(
                key: const ValueKey('history-personal-record-pill'),
                decoration: BoxDecoration(
                  color: accentFillColor(context),
                  borderRadius: AppRadius.badge,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.trophy,
                        size: 12,
                        color: onAccentColor(context),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'Personal record',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            color: onAccentColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HistoryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textSecondaryColor(context)),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              value,
              style: AppTypography.figures(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenIndicator extends StatelessWidget {
  const _OpenIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: textSecondaryColor(context),
        semanticLabel: 'Open workout details',
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
      ),
    );
  }
}
