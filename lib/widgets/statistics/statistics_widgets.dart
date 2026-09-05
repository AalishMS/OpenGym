import 'package:flutter/material.dart';

import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../utils/statistics_format.dart';

class StatisticsSectionHeader extends StatelessWidget {
  final String title;
  final String? supportingText;

  const StatisticsSectionHeader({
    super.key,
    required this.title,
    this.supportingText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (supportingText != null) ...[
          const SizedBox(height: 4),
          Text(
            supportingText!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

class RecordEventRow extends StatelessWidget {
  final RecordEvent event;
  final String weightUnit;

  const RecordEventRow({
    super.key,
    required this.event,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    final labels = <String>[];
    for (final achievement in event.achievements) {
      final raw = achievement.type
          .label(achievement.reps)
          .replaceFirst('New ', '');
      final label = '${raw[0].toUpperCase()}${raw.substring(1)}';
      if (!labels.contains(label)) labels.add(label);
    }
    final producer = event.achievements.last;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor(context),
              borderRadius: AppRadius.micro,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.exerciseName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatAnalyticsWeight(producer.setWeight, weightUnit)} × '
                  '${producer.setReps} · ${event.session.planName} · '
                  '${formatStatisticsDate(event.session.date)}',
                  style: AppTypography.trainingData(
                    fontSize: 12,
                    color: textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  labels.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
