import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/exercise_catalog.dart';
import '../../models/statistics.dart';
import '../../models/workout_session.dart';
import '../../services/statistics_analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import 'trend_line.dart';
import 'workout_heatmap.dart';

/// One weekly instrument: selecting a bar updates both the volume readout and
/// the workout/set/rep strip. History browses horizontally, not down a feed.
class TrainingOverview extends StatefulWidget {
  final List<WorkoutSession> sessions;
  final List<WeeklyTrainingValue> weeks;
  final String? exercise;
  final String? exerciseLabel;
  final String weightUnit;
  final VoidCallback onChooseExercise;
  final bool showCurrentWeek;

  const TrainingOverview({
    super.key,
    required this.sessions,
    required this.weeks,
    required this.exercise,
    this.exerciseLabel,
    required this.weightUnit,
    required this.onChooseExercise,
    this.showCurrentWeek = false,
  });

  @override
  State<TrainingOverview> createState() => _TrainingOverviewState();
}

class _TrainingOverviewState extends State<TrainingOverview> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final weeks = widget.weeks;
    final found = weeks.indexWhere((week) => week.weekStart == _selected);
    final index =
        found < 0
            ? math.max(0, weeks.length - (widget.showCurrentWeek ? 1 : 2))
            : found;
    final week = weeks[index];
    final current = index == weeks.length - 1;
    final previous = index > 0 ? weeks[index - 1].volumeLoad : 0.0;
    final change = previous > 0 ? (week.volumeLoad / previous - 1) * 100 : null;
    final weekSessions = widget.sessions.where(
      (session) =>
          StatisticsAnalyticsService.startOfWeek(session.date) ==
          week.weekStart,
    );
    var workouts = 0;
    var sets = 0;
    var reps = 0;
    for (final session in weekSessions) {
      final performed = session.exercises
          .where(
            (exercise) =>
                widget.exercise == null ||
                ExerciseCatalog.identity(exercise.name, exercise.exerciseId) ==
                    ExerciseCatalog.identity(widget.exercise!),
          )
          .expand((exercise) => exercise.sets)
          .where((set) => set.reps > 0);
      if (performed.isNotEmpty) workouts++;
      for (final set in performed) {
        sets++;
        reps += set.reps;
      }
    }
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Weekly training',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: TextButton(
                key: const ValueKey('weekly-exercise-picker'),
                onPressed: widget.onChooseExercise,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.exerciseLabel ??
                            widget.exercise ??
                            'All exercises',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(LucideIcons.chevronDown, size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${current
                    ? 'This week'
                    : index == weeks.length - 2
                    ? 'Last week'
                    : 'Selected week'}  /  ${formatWeekRange(week.weekStart)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                formatExactVolume(week.volumeLoad, widget.weightUnit),
                key: const ValueKey('weekly-volume-value'),
                style: AppTypography.figures(
                  fontSize: 40,
                  height: 1.15,
                  letterSpacing: -1.5,
                  fontWeight: FontWeight.w600,
                  color: textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Weight lifted', style: theme.textTheme.bodySmall),
                  if (current)
                    Text('Week in progress', style: theme.textTheme.bodySmall)
                  else if (change != null)
                    Text(
                      '${change > 0 ? '+' : ''}${change.round()}% vs previous week',
                      style: AppTypography.figures(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textPrimaryColor(context),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            // Keep six weeks visible at ordinary phone sizes. Long histories
            // retain generous targets and open at the most recent end.
            final slot = math.max(48 * scale, constraints.maxWidth / 6);
            final peak = weeks.fold<double>(
              0,
              (value, w) => math.max(value, w.volumeLoad),
            );
            // The top guide is a round figure in the unit it is read in.
            final ratio = displayWeight(1, widget.weightUnit);
            final maximum =
                niceAxisCeiling(math.max(1.0, peak * 1.05) * ratio) / ratio;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        weeks.length > 6
                            ? 'Swipe for earlier weeks'
                            : 'Tap a week to inspect',
                        style: theme.textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatVolumeLoad(maximum, widget.weightUnit),
                      style: AppTypography.figures(
                        fontSize: 10,
                        color: textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Stack(
                  children: [
                    Positioned.fill(
                      bottom: 32 * scale,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Container(height: 1, color: borderColor(context)),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      key: const ValueKey('training-timeline'),
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: SizedBox(
                        width: math.max(
                          constraints.maxWidth,
                          weeks.length * slot,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (var i = 0; i < weeks.length; i++)
                              Semantics(
                                button: true,
                                selected: i == index,
                                label:
                                    '${formatWeekRange(weeks[i].weekStart)}, '
                                    '${formatExactVolume(weeks[i].volumeLoad, widget.weightUnit)}'
                                    '${i == weeks.length - 1 ? ', week in progress' : ''}',
                                excludeSemantics: true,
                                child: InkWell(
                                  key: ValueKey('training-week-$i'),
                                  borderRadius: AppRadius.control,
                                  onTap:
                                      () => setState(
                                        () => _selected = weeks[i].weekStart,
                                      ),
                                  child: SizedBox(
                                    width: slot,
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          height: 112,
                                          child: Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              width: 26,
                                              height: math.max(
                                                3,
                                                weeks[i].volumeLoad /
                                                    maximum *
                                                    112,
                                              ),
                                              decoration: BoxDecoration(
                                                color:
                                                    i == index
                                                        ? accentFillColor(
                                                          context,
                                                        )
                                                        : accentDimColor(
                                                          context,
                                                        ),
                                                borderRadius: AppRadius.barCap,
                                              ),
                                              child:
                                                  i == weeks.length - 1
                                                      ? Align(
                                                        alignment:
                                                            Alignment.topCenter,
                                                        child: Container(
                                                          height: 2,
                                                          color: accentColor(
                                                            context,
                                                          ),
                                                        ),
                                                      )
                                                      : null,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 32 * scale,
                                          child: Center(
                                            child: Text(
                                              formatDayMonth(
                                                weeks[i].weekStart,
                                              ),
                                              style: AppTypography.figures(
                                                fontSize: 10,
                                                fontWeight:
                                                    i == index
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                color:
                                                    i == index
                                                        ? textPrimaryColor(
                                                          context,
                                                        )
                                                        : textSecondaryColor(
                                                          context,
                                                        ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
          },
        ),
        const SizedBox(height: AppSpacing.md),
        StatisticsFigures(
          values: [
            ('Workouts', '$workouts'),
            ('Sets', '$sets'),
            ('Reps', formatAnalyticsNumber(reps.toDouble())),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Divider(color: borderColor(context), height: 1),
        const SizedBox(height: AppSpacing.lg),
        WorkoutHeatmap(sessions: widget.sessions, compact: true),
      ],
    );
  }
}

/// Quiet, aligned figures that share the page rather than becoming tiles.
class StatisticsFigures extends StatelessWidget {
  final List<(String, String)> values;

  const StatisticsFigures({super.key, required this.values});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      return Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: [
          for (final (label, value) in values)
            SizedBox(
              width:
                  scale > 1.5
                      ? (constraints.maxWidth - AppSpacing.lg) / 2
                      : (constraints.maxWidth -
                              AppSpacing.lg * (values.length - 1)) /
                          values.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: AppTypography.figures(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      );
    },
  );
}
