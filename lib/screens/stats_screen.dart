import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/statistics.dart';
import '../models/workout_session.dart';
import '../providers/settings_provider.dart';
import '../providers/split_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/statistics_analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../utils/statistics_format.dart';
import '../widgets/statistics/statistics_widgets.dart';
import 'history_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const _analytics = StatisticsAnalyticsService();

  StatisticsPeriod _period = StatisticsPeriod.fourWeeks;
  TrainingMetric _trainingMetric = TrainingMetric.volumeLoad;
  ExerciseMetric _exerciseMetric = ExerciseMetric.estimatedOneRepMax;
  String? _selectedExercise;

  @override
  Widget build(BuildContext context) {
    final providerSessions = context.watch<WorkoutSessionProvider>().sessions;
    final splitId = context.watch<SplitProvider?>()?.activeSplitId;
    final weightUnit = context.watch<SettingsProvider?>()?.weightUnit ?? 'kg';
    final sessions = _analytics.eligibleSessions(
      providerSessions,
      splitId: splitId,
    );

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        title: Text(
          'Statistics',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textPrimaryColor(context)),
        ),
        automaticallyImplyLeading: false,
      ),
      body:
          sessions.isEmpty
              ? const _NoStatisticsState()
              : _StatisticsContent(
                sessions: sessions,
                period: _period,
                trainingMetric: _trainingMetric,
                exerciseMetric: _exerciseMetric,
                selectedExercise: _selectedExercise,
                weightUnit: weightUnit,
                onPeriodChanged: (value) => setState(() => _period = value),
                onTrainingMetricChanged:
                    (value) => setState(() => _trainingMetric = value),
                onExerciseMetricChanged:
                    (value) => setState(() => _exerciseMetric = value),
                onExerciseChanged:
                    (value) => setState(() => _selectedExercise = value),
              ),
    );
  }
}

class _StatisticsContent extends StatelessWidget {
  static const _analytics = StatisticsAnalyticsService();

  final List<WorkoutSession> sessions;
  final StatisticsPeriod period;
  final TrainingMetric trainingMetric;
  final ExerciseMetric exerciseMetric;
  final String? selectedExercise;
  final String weightUnit;
  final ValueChanged<StatisticsPeriod> onPeriodChanged;
  final ValueChanged<TrainingMetric> onTrainingMetricChanged;
  final ValueChanged<ExerciseMetric> onExerciseMetricChanged;
  final ValueChanged<String?> onExerciseChanged;

  const _StatisticsContent({
    required this.sessions,
    required this.period,
    required this.trainingMetric,
    required this.exerciseMetric,
    required this.selectedExercise,
    required this.weightUnit,
    required this.onPeriodChanged,
    required this.onTrainingMetricChanged,
    required this.onExerciseMetricChanged,
    required this.onExerciseChanged,
  });

  @override
  Widget build(BuildContext context) {
    final periodSessions = _analytics.sessionsInPeriod(sessions, period);
    final overview = _analytics.trainingOverview(
      sessions,
      period,
      trainingMetric,
    );
    final names = _analytics.exerciseNames(periodSessions);
    final exercise =
        names.contains(selectedExercise)
            ? selectedExercise
            : (names.isEmpty ? null : names.first);
    final progress =
        exercise == null
            ? null
            : _analytics.exerciseProgress(
              periodSessions,
              exercise,
              exerciseMetric,
            );
    final records = _analytics.recordEvents(sessions).take(8).toList();
    final recentSessions =
        sessions.take(8).map(_analytics.sessionStatistics).toList();
    final total = overview.weeks.fold<double>(
      0,
      (sum, week) => sum + week.valueFor(trainingMetric),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= Breakpoints.medium - 180 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.4;
        return Align(
          alignment: Alignment.topCenter,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Breakpoints.expanded,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StatisticsSectionHeader(
                      title: 'Weekly training',
                      supportingText:
                          'Completed workouts grouped Monday to Sunday.',
                    ),
                    const SizedBox(height: 16),
                    StatisticsChoiceBar<StatisticsPeriod>(
                      values: StatisticsPeriod.values,
                      selected: period,
                      labelFor: (value) => value.label,
                      onSelected: onPeriodChanged,
                    ),
                    const SizedBox(height: 16),
                    StatisticsChoiceBar<TrainingMetric>(
                      values: TrainingMetric.values,
                      selected: trainingMetric,
                      labelFor: (value) => value.label,
                      onSelected: onTrainingMetricChanged,
                    ),
                    const SizedBox(height: 20),
                    _PeriodSummary(
                      total: total,
                      metric: trainingMetric,
                      weightUnit: weightUnit,
                      comparison: overview.comparison,
                      hasDurationData: overview.hasDurationData,
                    ),
                    const SizedBox(height: 16),
                    WeeklyTrainingChart(
                      overview: overview,
                      metric: trainingMetric,
                      weightUnit: weightUnit,
                    ),
                    const SizedBox(height: 36),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _RecentSessionsSection(
                              statistics: recentSessions,
                              weightUnit: weightUnit,
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(
                            child: _RecordEventsSection(
                              events: records,
                              weightUnit: weightUnit,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _RecentSessionsSection(
                        statistics: recentSessions,
                        weightUnit: weightUnit,
                      ),
                      const SizedBox(height: 36),
                      _RecordEventsSection(
                        events: records,
                        weightUnit: weightUnit,
                      ),
                    ],
                    const SizedBox(height: 36),
                    const StatisticsSectionHeader(
                      title: 'Exercise progress',
                      supportingText:
                          'One point for each workout containing the exercise.',
                    ),
                    const SizedBox(height: 16),
                    if (names.isEmpty)
                      const _InlineEmptyState(
                        text: 'No performed sets are available in this period.',
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey(exercise),
                        initialValue: exercise,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Exercise',
                        ),
                        items: [
                          for (final name in names)
                            DropdownMenuItem(value: name, child: Text(name)),
                        ],
                        onChanged: onExerciseChanged,
                      ),
                      const SizedBox(height: 12),
                      StatisticsChoiceBar<ExerciseMetric>(
                        values: ExerciseMetric.values,
                        selected: exerciseMetric,
                        labelFor: (value) => value.label,
                        onSelected: onExerciseMetricChanged,
                      ),
                      const SizedBox(height: 16),
                      ExerciseProgressChart(
                        progress: progress!,
                        metric: exerciseMetric,
                        weightUnit: weightUnit,
                      ),
                      const SizedBox(height: 20),
                      _ExerciseSummary(
                        progress: progress,
                        metric: exerciseMetric,
                        weightUnit: weightUnit,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PeriodSummary extends StatelessWidget {
  final double total;
  final TrainingMetric metric;
  final String weightUnit;
  final PeriodComparison? comparison;
  final bool hasDurationData;

  const _PeriodSummary({
    required this.total,
    required this.metric,
    required this.weightUnit,
    required this.comparison,
    required this.hasDurationData,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = metric != TrainingMetric.duration || hasDurationData;
    return MetricSummary(
      values: [
        (
          'Period total',
          hasValue
              ? formatTrainingValue(total, metric, weightUnit)
              : 'Not recorded',
        ),
        ('Compared with previous', _comparisonText()),
      ],
    );
  }

  String _comparisonText() {
    final value = comparison;
    if (value == null) return 'All completed workouts';
    if (metric == TrainingMetric.duration && !hasDurationData) {
      return 'Not recorded';
    }
    final percentage = value.percentageChange;
    if (percentage != null) {
      final prefix = percentage > 0 ? '+' : '';
      return '$prefix${percentage.toStringAsFixed(0)}%';
    }
    if (value.currentValue == 0) return 'No change';
    final formatted = formatTrainingValue(
      value.absoluteChange.abs(),
      metric,
      weightUnit,
    );
    return '${value.absoluteChange > 0 ? '+' : '−'}$formatted';
  }
}

class _RecentSessionsSection extends StatelessWidget {
  final List<SessionStatistics> statistics;
  final String weightUnit;

  const _RecentSessionsSection({
    required this.statistics,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatisticsSectionHeader(
          title: 'Recent sessions',
          supportingText: 'Tap a workout to review or edit it.',
        ),
        const SizedBox(height: 8),
        for (final item in statistics)
          SessionStatisticsRow(
            statistics: item,
            weightUnit: weightUnit,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditSessionScreen(session: item.session),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _RecordEventsSection extends StatelessWidget {
  final List<RecordEvent> events;
  final String weightUnit;

  const _RecordEventsSection({required this.events, required this.weightUnit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatisticsSectionHeader(
          title: 'Recent records',
          supportingText: 'Recalculated from completed workout history.',
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const _InlineEmptyState(
            text: 'Record events appear as training history grows.',
          )
        else
          for (final event in events)
            RecordEventRow(event: event, weightUnit: weightUnit),
      ],
    );
  }
}

class _ExerciseSummary extends StatelessWidget {
  final ExerciseProgress progress;
  final ExerciseMetric metric;
  final String weightUnit;

  const _ExerciseSummary({
    required this.progress,
    required this.metric,
    required this.weightUnit,
  });

  @override
  Widget build(BuildContext context) {
    final current = progress.currentValue;
    final change = progress.change;
    final bestSet = progress.bestSetWeight;
    return MetricSummary(
      values: [
        (
          'Current value',
          current == null
              ? 'Not available'
              : formatExerciseValue(current, metric, weightUnit),
        ),
        (
          'Period change',
          change == null
              ? 'Need 2 sessions'
              : '${change > 0 ? '+' : ''}${formatExerciseValue(change, metric, weightUnit)}',
        ),
        (
          'Best set',
          bestSet == null
              ? 'Not available'
              : '${formatAnalyticsWeight(bestSet, weightUnit)} × ${progress.bestSetReps}',
        ),
        ('Session count', '${progress.sessionCount}'),
      ],
    );
  }
}

class _NoStatisticsState extends StatelessWidget {
  const _NoStatisticsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No completed workouts',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Statistics appear after you finish and log a workout.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String text;

  const _InlineEmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: textSecondaryColor(context)),
      ),
    );
  }
}
