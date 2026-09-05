import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/statistics.dart';
import '../providers/settings_provider.dart';
import '../providers/split_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/statistics_analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/radii.dart';
import '../utils/statistics_format.dart';
import '../widgets/statistics/statistics_widgets.dart';
import '../widgets/statistics/training_charts.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const _analytics = StatisticsAnalyticsService();
  StatisticsPeriod _period = StatisticsPeriod.fourWeeks;
  ExerciseMetric _metric = ExerciseMetric.estimatedOneRepMax;
  String? _weeklyExercise;
  String? _progressExercise;
  bool _allExercises = false;
  String? _lastSplit;

  @override
  Widget build(BuildContext context) {
    final splitId = context.watch<SplitProvider?>()?.activeSplitId;
    final unit = context.watch<SettingsProvider?>()?.weightUnit ?? 'kg';
    final sessions = _analytics.eligibleSessions(
      context.watch<WorkoutSessionProvider>().sessions,
      splitId: splitId,
    );
    if (_lastSplit != splitId) {
      _lastSplit = splitId;
      _weeklyExercise = null;
      _progressExercise = null;
      _allExercises = false;
    }
    final names = _analytics.exerciseNames(sessions);
    final defaultExercise = _analytics.latestExercise(sessions);
    final weekly =
        names.contains(_weeklyExercise) ? _weeklyExercise : defaultExercise;
    final exercise =
        names.contains(_progressExercise) ? _progressExercise : defaultExercise;
    final weeks = _analytics.weeklyVolume(
      sessions,
      exerciseName: _allExercises ? null : weekly,
    );
    final progress =
        exercise == null
            ? null
            : _analytics.exerciseProgress(
              _analytics.sessionsInPeriod(sessions, _period),
              exercise,
              _metric,
            );
    final records = _analytics.recordEvents(sessions).take(8).toList();

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
              ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No completed workouts',
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Statistics appear after you finish and log a workout.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const StatisticsSectionHeader(title: 'Weekly training'),
                        const SizedBox(height: 12),
                        _ChartPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Volume load',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Weight × reps · All history',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: textSecondaryColor(context),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _Selector<String>(
                                fieldKey: 'weekly-exercise',
                                label: 'Exercise',
                                value: _allExercises ? '' : weekly ?? '',
                                values: ['', ...names],
                                labelFor:
                                    (name) =>
                                        name.isEmpty ? 'All exercises' : name,
                                onChanged:
                                    (value) => setState(() {
                                      _allExercises = value.isEmpty;
                                      _weeklyExercise =
                                          value.isEmpty ? null : value;
                                    }),
                              ),
                              const SizedBox(height: 24),
                              WeeklyVolumeChart(
                                key: ValueKey(
                                  'weekly-$splitId-${_allExercises ? "all" : weekly}',
                                ),
                                weeks: weeks,
                                weightUnit: unit,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        const StatisticsSectionHeader(
                          title: 'Exercise progress',
                        ),
                        const SizedBox(height: 12),
                        _ChartPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (exercise == null)
                                const Text(
                                  'Log performed sets to see exercise progress.',
                                )
                              else ...[
                                _Selector<String>(
                                  fieldKey: 'progress-exercise',
                                  label: 'Exercise',
                                  value: exercise,
                                  values: names,
                                  labelFor: (name) => name,
                                  onChanged:
                                      (value) => setState(
                                        () => _progressExercise = value,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final metric = _Selector<ExerciseMetric>(
                                      fieldKey: 'progress-metric',
                                      label: 'Metric',
                                      value: _metric,
                                      values: ExerciseMetric.values,
                                      labelFor: (metric) => metric.label,
                                      onChanged:
                                          (value) =>
                                              setState(() => _metric = value),
                                    );
                                    final period = _Selector<StatisticsPeriod>(
                                      fieldKey: 'progress-period',
                                      label: 'Period',
                                      value: _period,
                                      values: StatisticsPeriod.values,
                                      labelFor: (period) => period.label,
                                      onChanged:
                                          (value) =>
                                              setState(() => _period = value),
                                    );
                                    if (constraints.maxWidth < 300 ||
                                        MediaQuery.textScalerOf(
                                              context,
                                            ).scale(1) >
                                            1.3) {
                                      return Column(
                                        children: [
                                          metric,
                                          const SizedBox(height: 12),
                                          period,
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        Expanded(flex: 3, child: metric),
                                        const SizedBox(width: 12),
                                        Expanded(flex: 2, child: period),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 24),
                                if (progress!.points.isNotEmpty) ...[
                                  _ProgressSummary(
                                    progress: progress,
                                    metric: _metric,
                                    unit: unit,
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Per workout',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium?.copyWith(
                                      color: textSecondaryColor(context),
                                    ),
                                  ),
                                ],
                                ExerciseTrendChart(
                                  key: ValueKey(
                                    'progress-$splitId-$exercise-$_period-$_metric',
                                  ),
                                  progress: progress,
                                  metric: _metric,
                                  weightUnit: unit,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        const StatisticsSectionHeader(title: 'Recent records'),
                        const SizedBox(height: 8),
                        if (records.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'New personal records will appear here as you train.',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: textSecondaryColor(context),
                              ),
                            ),
                          )
                        else
                          for (final event in records)
                            RecordEventRow(event: event, weightUnit: unit),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}

class _ChartPanel extends StatelessWidget {
  final Widget child;
  const _ChartPanel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: surfaceColor(context),
      borderRadius: AppRadius.card,
    ),
    child: child,
  );
}

class _Selector<T> extends StatelessWidget {
  final String fieldKey;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;
  const _Selector({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    key: ValueKey('$fieldKey-$value'),
    initialValue: value,
    isExpanded: true,
    itemHeight: null,
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    ),
    selectedItemBuilder:
        (context) => [
          for (final item in values)
            Text(labelFor(item), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
    items: [
      for (final item in values)
        DropdownMenuItem(
          value: item,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(labelFor(item)),
          ),
        ),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class _ProgressSummary extends StatelessWidget {
  final ExerciseProgress progress;
  final ExerciseMetric metric;
  final String unit;
  const _ProgressSummary({
    required this.progress,
    required this.metric,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final best = progress.points
        .map((point) => point.value)
        .reduce((a, b) => a > b ? a : b);
    final change = progress.change;
    final values = [
      (
        'Latest',
        formatChartExerciseValue(progress.currentValue!, metric, unit),
      ),
      (
        'Change',
        change == null
            ? 'Need 2 workouts'
            : '${change > 0 ? '+' : ''}${formatChartExerciseValue(change, metric, unit)}',
      ),
      ('Best in period', formatChartExerciseValue(best, metric, unit)),
    ];
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final (label, value) in values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.trainingData(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimaryColor(context),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
