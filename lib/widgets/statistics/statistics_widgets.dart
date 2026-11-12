import 'package:flutter/material.dart';

import '../../data/exercise_library.dart';
import '../../models/statistics.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../utils/statistics_format.dart';

class StatisticsSectionHeader extends StatelessWidget {
  final String title;

  const StatisticsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class RecordEventRow extends StatefulWidget {
  final RecordEvent event;
  final String weightUnit;

  const RecordEventRow({
    super.key,
    required this.event,
    required this.weightUnit,
  });

  @override
  State<RecordEventRow> createState() => _RecordEventRowState();
}

class _RecordEventRowState extends State<RecordEventRow> {
  /// The order of a row's tags: the record most people recognise first.
  static int _priority(RecordType type) => switch (type) {
    RecordType.heaviestWeight => 0,
    RecordType.mostReps => 1,
    RecordType.longestHold => 2,
    RecordType.estimatedOneRepMax => 3,
    RecordType.repBest => 4,
    RecordType.setVolume => 5,
  };

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final weightUnit = widget.weightUnit;
    // A stable sort keeps rep bests in their rep order.
    final achievements = [
      for (final (index, achievement) in event.achievements.indexed)
        (index, achievement),
    ]..sort((a, b) {
      final type = _priority(a.$2.type).compareTo(_priority(b.$2.type));
      return type != 0 ? type : a.$1.compareTo(b.$1);
    });
    final labels = <String>[];
    for (final (_, achievement) in achievements) {
      final previous = formatRecordPreviousValue(achievement, weightUnit);
      final label =
          '${formatRecordTitle(achievement)} · '
          '${formatRecordValue(achievement, weightUnit)}'
          '${previous == null ? '' : ', up from $previous'}';
      if (!labels.contains(label)) labels.add(label);
    }
    final tagStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: textSecondaryColor(context));
    // The set shown is the one behind the leading tag.
    final producer = achievements.first.$2;
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
                  '${formatSetSummary(producer.setWeight, producer.setReps, weightUnit, timed: ExerciseLibrary.isTimed(event.exerciseName))} · '
                  '${event.session.planName} · '
                  '${formatStatisticsDate(event.session.date)}',
                  style: AppTypography.figures(
                    fontSize: 12,
                    color: textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                if (labels.length == 1)
                  Text(labels.single, style: tagStyle)
                else ...[
                  if (_expanded)
                    for (final label in labels.take(labels.length - 1))
                      Text(label, style: tagStyle),
                  // The toggle sits on the last tag's line, so its tap target
                  // doesn't add a line of its own.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _expanded ? labels.last : labels.first,
                          style: tagStyle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          visualDensity: VisualDensity.compact,
                          textStyle: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        child: Text(
                          _expanded
                              ? 'Show less'
                              : '+${labels.length - 1} more',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
