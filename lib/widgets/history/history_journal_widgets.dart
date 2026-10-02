import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
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
        prefixIcon: const Icon(LucideIcons.search),
        suffixIcon:
            controller.text.isEmpty
                ? null
                : AppIconButton(
                  label: 'Clear search',
                  icon: LucideIcons.x,
                  onPressed: onClear,
                ),
        border: const OutlineInputBorder(borderRadius: AppRadius.field),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                historyMonthLabel(group.month, group.year),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '$count workout${count == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Divider(height: 1, color: borderColor(context)),
      ],
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final stackDate = constraints.maxWidth < 310 || textScale >= 1.6;
              final date = _HistoryDate(
                date: session.date,
                horizontal: stackDate,
              );
              final details = Expanded(
                child: _WorkoutSummaryContent(
                  summary: summary,
                  weightUnit: weightUnit,
                ),
              );
              if (stackDate) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    date,
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [details, const _OpenIndicator()],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 52, child: date),
                  const SizedBox(width: AppSpacing.md),
                  details,
                  const _OpenIndicator(),
                ],
              );
            },
          ),
        ),
      ),
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
      style: Theme.of(context).textTheme.headlineMedium,
    );
    final weekday = Text(
      historyWeekday(date),
      style: Theme.of(context).textTheme.bodySmall,
    );
    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [day, const SizedBox(width: AppSpacing.sm), weekday],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: backgroundColor(context),
        borderRadius: AppRadius.control,
      ),
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
        Text(
          'Week ${session.weekNumber}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(session.planName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${session.exercises.length} exercise${session.exercises.length == 1 ? '' : 's'} · ${stats.totalSets} set${stats.totalSets == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            _HistoryMetric(
              icon: LucideIcons.weight,
              label: 'Volume load',
              value: formatVolumeLoad(stats.volumeLoad, weightUnit),
            ),
            if (session.durationSeconds != null)
              _HistoryMetric(
                icon: LucideIcons.timer,
                label: 'Duration',
                value: formatStatisticsDuration(session.durationSeconds!),
              ),
          ],
        ),
        if (summary.hasPersonalRecord) ...[
          const SizedBox(height: AppSpacing.sm),
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
              child: Text(
                'Personal record',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: onAccentColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
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
            child: Text(value, style: Theme.of(context).textTheme.labelMedium),
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
    );
  }
}
