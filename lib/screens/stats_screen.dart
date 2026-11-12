import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/statistics.dart';
import '../models/workout_session.dart';
import '../providers/settings_provider.dart';
import '../providers/split_provider.dart';
import '../providers/training_block_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/statistics_analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/statistics_format.dart';
import '../widgets/app_header.dart';
import '../widgets/statistics/block_statistics.dart';
import '../widgets/statistics/lift_list.dart';
import '../widgets/statistics/statistics_controls.dart';
import '../widgets/statistics/statistics_widgets.dart';
import '../widgets/statistics/training_charts.dart';
import '../widgets/statistics/workout_heatmap.dart';

class StatsScreen extends StatefulWidget {
  final int weeklyTrainingRequest;

  /// Bumped each time the tab is entered from another tab. The screen lives
  /// in the shell's IndexedStack, so without this it would keep its offset.
  final int visitRequest;

  /// Works out every figure on the screen. Replaceable so tests can count
  /// how often it runs.
  final StatisticsAnalyticsService analytics;

  const StatsScreen({
    this.weeklyTrainingRequest = 0,
    this.visitRequest = 0,
    this.analytics = const StatisticsAnalyticsService(),
    super.key,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _weeklyKey = GlobalKey();
  StatisticsPeriod _period = StatisticsPeriod.fourWeeks;
  ExerciseMetric _metric = ExerciseMetric.estimatedOneRepMax;
  BlockMeasure _blockMeasure = BlockMeasure.sets;
  String? _blockId;
  String? _weeklyExercise;
  String? _progressExercise;
  bool _allExercises = true;
  bool _showsBlocks = false;
  String? _lastSplit;

  // The screen lives in the shell's IndexedStack and rebuilds on every
  // provider notification, even while hidden. Each derived value is kept
  // until one of its own inputs changes. Provider lists are replaced, never
  // mutated, on reload, so identity is a sound key.
  final _eligible = _Memo<List<WorkoutSession>>();
  final _overview = _Memo<_Overview>();
  final _weekly = _Memo<List<WeeklyTrainingValue>>();
  final _lifts = _Memo<List<LiftSummary>>();
  final _blocks = _Memo<List<BlockStatistics>>();

  @override
  void didUpdateWidget(covariant StatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final weekly =
        widget.weeklyTrainingRequest != oldWidget.weeklyTrainingRequest;
    if (!weekly && widget.visitRequest == oldWidget.visitRequest) return;
    if (weekly) _allExercises = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
      // The weekly summary on Home links to this week's training, which sits
      // below the block overview.
      final section = _weeklyKey.currentContext;
      if (weekly && _showsBlocks && section != null) {
        Scrollable.ensureVisible(section, duration: Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = widget.analytics;
    final splitId = context.watch<SplitProvider?>()?.activeSplitId;
    final unit = context.watch<SettingsProvider?>()?.weightUnit ?? 'kg';
    final training = context.watch<TrainingBlockProvider?>();
    final all = context.watch<WorkoutSessionProvider>().sessions;
    // Keyed on the workouts themselves, not the list that holds them, so a
    // provider that adds to its list in place still refreshes the screen.
    final sessions = _eligible([
      analytics,
      splitId,
      ...all,
    ], () => analytics.eligibleSessions(all, splitId: splitId));
    if (_lastSplit != splitId) {
      _lastSplit = splitId;
      _blockId = null;
      _weeklyExercise = null;
      _progressExercise = null;
      _allExercises = true;
    }
    // Weekly charts and periods end with the current week.
    final thisWeek = StatisticsAnalyticsService.startOfWeek(DateTime.now());
    final overview = _overview(
      [analytics, sessions],
      () => _Overview(
        names: analytics.exerciseNames(sessions),
        defaultExercise: analytics.latestExercise(sessions),
        records: analytics.recordEvents(sessions),
      ),
    );
    final names = overview.names;
    final weekly =
        names.contains(_weeklyExercise)
            ? _weeklyExercise
            : overview.defaultExercise;
    final weeklyName = _allExercises ? null : weekly;
    final weeks = _weekly([
      analytics,
      sessions,
      weeklyName,
      thisWeek,
    ], () => analytics.weeklyVolume(sessions, exerciseName: weeklyName));
    final lifts = _lifts(
      [analytics, sessions, _period, _metric, thisWeek],
      () => analytics.liftSummaries(
        analytics.sessionsInPeriod(sessions, _period),
        _metric,
      ),
    );
    final lift =
        lifts
            .where((lift) => lift.exerciseName == _progressExercise)
            .firstOrNull ??
        lifts.firstOrNull;
    final records = overview.records.take(8).toList();

    final blocks =
        training == null
            ? const <BlockStatistics>[]
            : _blocks(
              [analytics, sessions, training.blocks, training.weeksByBlock],
              () =>
                  analytics
                      .blockStatistics(
                        sessions,
                        blocks: training.blocks,
                        weeksByBlock: training.weeksByBlock,
                        records: overview.records,
                      )
                      .where((block) => block.workouts > 0)
                      .toList(),
            );
    final latestWeekId = sessions.firstOrNull?.trainingWeekId;
    final currentBlockId =
        latestWeekId == null ? null : training?.weekById[latestWeekId]?.blockId;
    final selectedBlock =
        blocks.where((b) => b.block.id == _blockId).firstOrNull ??
        blocks.where((b) => b.block.id == currentBlockId).firstOrNull ??
        blocks.lastOrNull;
    _showsBlocks = selectedBlock != null;
    void selectBlock(String id) => setState(() => _blockId = id);

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: const AppHeader(
        automaticallyImplyLeading: false,
        title: Text('Statistics'),
      ),
      body:
          sessions.isEmpty
              ? const _EmptyStatistics()
              : SingleChildScrollView(
                key: const ValueKey('statistics-scroll'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedBlock != null) ...[
                          const StatisticsSectionHeader(
                            title: 'Training blocks',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ChartPanel(
                            child: BlockOverview(
                              blocks: blocks,
                              selected: selectedBlock,
                              currentBlockId: currentBlockId,
                              onSelect: selectBlock,
                              weightUnit: unit,
                            ),
                          ),
                          if (blocks.length > 1) ...[
                            const SizedBox(height: AppSpacing.md),
                            _ChartPanel(
                              child: BlockComparison(
                                blocks: blocks,
                                selectedId: selectedBlock.block.id,
                                currentBlockId: currentBlockId,
                                measure: _blockMeasure,
                                onMeasure:
                                    (measure) =>
                                        setState(() => _blockMeasure = measure),
                                onSelect: selectBlock,
                                weightUnit: unit,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xxl),
                        ],
                        StatisticsSectionHeader(
                          key: _weeklyKey,
                          title: 'Weekly training',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ChartPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weight lifted',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Weight × reps for every set, added up by week',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: textSecondaryColor(context),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _Selector<String>(
                                fieldKey: 'weekly-exercise',
                                label: 'Exercise',
                                value: _allExercises ? '' : weekly ?? '',
                                values: ['', ...names],
                                labelFor:
                                    (name) =>
                                        name.isEmpty ? 'All exercises' : name,
                                labelBuilder: (name) {
                                  if (name.isNotEmpty) return null;
                                  return Row(
                                    children: [
                                      Icon(
                                        Icons.layers_outlined,
                                        size: 18,
                                        color: accentColor(context),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          'All exercises',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: accentColor(context),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                                onChanged:
                                    (value) => setState(() {
                                      _allExercises = value.isEmpty;
                                      _weeklyExercise =
                                          value.isEmpty ? null : value;
                                    }),
                              ),
                              const SizedBox(height: AppSpacing.xl),
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
                        const SizedBox(height: AppSpacing.xxl),
                        const StatisticsSectionHeader(title: 'Activity'),
                        const SizedBox(height: AppSpacing.md),
                        _ChartPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Workouts',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              // Captions itself with the weeks that fit.
                              WorkoutHeatmap(sessions: sessions),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        const StatisticsSectionHeader(
                          title: 'Exercise progress',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ChartPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                container: true,
                                label: 'Time range',
                                child: SegmentedPills<StatisticsPeriod>(
                                  keyPrefix: 'progress-period',
                                  values: StatisticsPeriod.values,
                                  selected: _period,
                                  labelFor: (period) => period.shortLabel,
                                  semanticLabelFor: (period) => period.label,
                                  onSelected:
                                      (value) =>
                                          setState(() => _period = value),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Semantics(
                                container: true,
                                label: 'Measure',
                                child: ScrollingPills<ExerciseMetric>(
                                  keyPrefix: 'progress-metric',
                                  values: ExerciseMetric.values,
                                  selected: _metric,
                                  labelFor: (metric) => metric.shortLabel,
                                  onSelected:
                                      (value) =>
                                          setState(() => _metric = value),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _metric.description,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: textSecondaryColor(context),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (lifts.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                  ),
                                  child: Text(
                                    _period == StatisticsPeriod.allTime
                                        ? 'Log performed sets to see exercise progress.'
                                        : 'No lifts logged in the last ${_period.label}. Try a longer time range.',
                                  ),
                                )
                              else
                                LiftList(
                                  key: ValueKey('lifts-$splitId-$_period'),
                                  lifts: lifts,
                                  selected: lift?.exerciseName,
                                  metric: _metric,
                                  weightUnit: unit,
                                  onSelect:
                                      (name) => setState(
                                        () => _progressExercise = name,
                                      ),
                                ),
                            ],
                          ),
                        ),
                        if (lift != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _ChartPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    lift.exerciseName,
                                    key: const ValueKey('progress-exercise'),
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${progressMeasureLabel(_metric, lift.progress.fallback)} · ${_period.label}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                    color: textSecondaryColor(context),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                _ProgressSummary(
                                  progress: lift.progress,
                                  metric: _metric,
                                  unit: unit,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                ExerciseTrendChart(
                                  key: ValueKey(
                                    'progress-$splitId-${lift.exerciseName}-$_period-$_metric',
                                  ),
                                  progress: lift.progress,
                                  metric: _metric,
                                  weightUnit: unit,
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xxl),
                        const StatisticsSectionHeader(title: 'Recent records'),
                        const SizedBox(height: AppSpacing.sm),
                        if (records.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.lg,
                            ),
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
                            RecordEventRow(
                              key: ValueKey(
                                'record-${event.session.id}-${event.exerciseName}',
                              ),
                              event: event,
                              weightUnit: unit,
                            ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}

class _EmptyStatistics extends StatelessWidget {
  const _EmptyStatistics();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder:
        (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No completed workouts', textAlign: TextAlign.center),
                    SizedBox(height: AppSpacing.sm),
                    Text(
                      'Statistics appear after you finish and log a workout.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
  );
}

class _ChartPanel extends StatelessWidget {
  final Widget child;
  const _ChartPanel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.lg),
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
  final Widget? Function(T)? labelBuilder;
  final ValueChanged<T> onChanged;
  const _Selector({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    this.labelBuilder,
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
            labelBuilder?.call(item) ??
                Text(
                  labelFor(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ],
    items: [
      for (final item in values)
        DropdownMenuItem(
          value: item,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: labelBuilder?.call(item) ?? Text(labelFor(item)),
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
    String format(double value) =>
        formatProgressValue(value, metric, progress.fallback, unit);
    // The latest value is already the readout under the chart.
    final values = [
      (
        'Change',
        change == null
            ? 'Need 2 workouts'
            : '${change > 0 ? '+' : ''}${format(change)}',
      ),
      ('Best in period', format(best)),
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
                style: AppTypography.figures(
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

/// The parts of the screen that depend only on the split's workouts.
class _Overview {
  final List<String> names;
  final String? defaultExercise;

  /// Every record, newest first: Recent records shows the first few and the
  /// blocks count them, so they are worked out once.
  final List<RecordEvent> records;

  const _Overview({
    required this.names,
    required this.defaultExercise,
    required this.records,
  });
}

/// One derived value, kept until its inputs change. Inputs compare with
/// `==`, which for lists and maps is identity.
class _Memo<T> {
  List<Object?>? _inputs;
  late T _value;

  T call(List<Object?> inputs, T Function() compute) {
    final previous = _inputs;
    if (previous != null && listEquals(previous, inputs)) return _value;
    _value = compute();
    _inputs = inputs;
    return _value;
  }
}
