import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/statistics.dart';
import '../providers/settings_provider.dart';
import '../providers/split_provider.dart';
import '../providers/training_block_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/statistics_analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/statistics/block_statistics.dart';
import '../widgets/statistics/lift_list.dart';
import '../widgets/statistics/statistics_controls.dart';
import '../widgets/statistics/statistics_widgets.dart';
import '../widgets/statistics/strength_trend.dart';
import '../widgets/statistics/training_overview.dart';

enum _StatisticsView { overview, strength, blocks, records }

extension on _StatisticsView {
  String get label => switch (this) {
    _StatisticsView.overview => 'Overview',
    _StatisticsView.strength => 'Strength',
    _StatisticsView.blocks => 'Blocks',
    _StatisticsView.records => 'Records',
  };
}

class StatsScreen extends StatefulWidget {
  final int weeklyTrainingRequest;
  final int visitRequest;

  const StatsScreen({
    this.weeklyTrainingRequest = 0,
    this.visitRequest = 0,
    super.key,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const _analytics = StatisticsAnalyticsService();
  final ScrollController _scrollController = ScrollController();
  _StatisticsView _view = _StatisticsView.overview;
  StatisticsPeriod _period = StatisticsPeriod.fourWeeks;
  ExerciseMetric _metric = ExerciseMetric.estimatedOneRepMax;
  String? _blockId;
  String? _weeklyExercise;
  String? _progressExercise;
  String? _lastSplit;
  int _recordLimit = 12;

  /// Home's weekly shortcut asks for the week in progress; any other entry
  /// into Stats returns the Overview to the last complete week.
  bool _showCurrentWeek = false;

  @override
  void didUpdateWidget(covariant StatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final weekly =
        widget.weeklyTrainingRequest != oldWidget.weeklyTrainingRequest;
    if (!weekly && widget.visitRequest == oldWidget.visitRequest) return;
    if (weekly) {
      _view = _StatisticsView.overview;
      _weeklyExercise = null;
    }
    _showCurrentWeek = weekly;
    _resetScroll();
  }

  void _resetScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  void _selectView(_StatisticsView view) {
    setState(() => _view = view);
    _resetScroll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _choose<T>({
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) labelFor,
    required ValueChanged<T> onSelected,
  }) async {
    final value = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppHeader(
                    leading: AppBackButton(
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: Text(title),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: values.length,
                      itemBuilder: (context, index) {
                        final value = values[index];
                        return ListTile(
                          title: Text(labelFor(value)),
                          selected: value == selected,
                          trailing:
                              value == selected
                                  ? const Icon(LucideIcons.check, size: 18)
                                  : null,
                          onTap: () => Navigator.pop(context, value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (mounted && value != null) onSelected(value);
  }

  Future<void> _chooseLift(
    List<LiftSummary> lifts,
    String selected,
    String unit,
  ) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.75,
              child: Column(
                children: [
                  AppHeader(
                    leading: AppBackButton(
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: const Text('Choose exercise'),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: LiftList(
                        lifts: lifts,
                        selected: selected,
                        metric: _metric,
                        weightUnit: unit,
                        onSelect: (name) => Navigator.pop(context, name),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (mounted && value != null) setState(() => _progressExercise = value);
  }

  @override
  Widget build(BuildContext context) {
    final splitId = context.watch<SplitProvider?>()?.activeSplitId;
    final unit = context.watch<SettingsProvider?>()?.weightUnit ?? 'kg';
    final training = context.watch<TrainingBlockProvider?>();
    final sessions = _analytics.eligibleSessions(
      context.watch<WorkoutSessionProvider>().sessions,
      splitId: splitId,
    );
    if (_lastSplit != splitId) {
      _lastSplit = splitId;
      _view = _StatisticsView.overview;
      _blockId = null;
      _weeklyExercise = null;
      _progressExercise = null;
      _recordLimit = 12;
      _resetScroll();
    }
    final directory = _analytics.exerciseDirectory(sessions);
    final names = directory.keys.toList();
    final weeklyExercise =
        names.contains(_weeklyExercise) ? _weeklyExercise : null;
    final lifts = _analytics.liftSummaries(
      _analytics.sessionsInPeriod(sessions, _period),
      _metric,
    );
    final lift =
        lifts
            .where(
              (lift) =>
                  (lift.exerciseId ?? lift.exerciseName) == _progressExercise,
            )
            .firstOrNull ??
        lifts.firstOrNull;
    final blocks =
        training == null
            ? const <BlockStatistics>[]
            : _analytics
                .blockStatistics(
                  sessions,
                  blocks: training.blocks,
                  weeksByBlock: training.weeksByBlock,
                )
                .where((block) => block.workouts > 0)
                .toList();
    final latestWeekId = sessions.firstOrNull?.trainingWeekId;
    final currentBlockId =
        latestWeekId == null ? null : training?.weekById[latestWeekId]?.blockId;
    final selectedBlock =
        blocks.where((b) => b.block.id == _blockId).firstOrNull ??
        blocks.where((b) => b.block.id == currentBlockId).firstOrNull ??
        blocks.lastOrNull;
    void selectBlock(String id) => setState(() => _blockId = id);

    final Widget content;
    switch (_view) {
      case _StatisticsView.overview:
        content = TrainingOverview(
          key: ValueKey(
            'overview-$splitId-$weeklyExercise-'
            '${widget.weeklyTrainingRequest}-$_showCurrentWeek',
          ),
          sessions: sessions,
          showCurrentWeek: _showCurrentWeek,
          weeks: _analytics.weeklyVolume(
            sessions,
            exerciseName: weeklyExercise,
          ),
          exercise: weeklyExercise,
          exerciseLabel: directory[weeklyExercise],
          weightUnit: unit,
          onChooseExercise:
              () => _choose<String>(
                title: 'Weekly training',
                values: ['', ...names],
                selected: weeklyExercise ?? '',
                labelFor:
                    (name) => name.isEmpty ? 'All exercises' : directory[name]!,
                onSelected:
                    (name) => setState(
                      () => _weeklyExercise = name.isEmpty ? null : name,
                    ),
              ),
        );
      case _StatisticsView.strength:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: 'Time range',
              child: SegmentedPills<StatisticsPeriod>(
                keyPrefix: 'progress-period',
                quiet: true,
                values: StatisticsPeriod.values,
                selected: _period,
                labelFor: (period) => period.shortLabel,
                semanticLabelFor: (period) => period.label,
                onSelected: (value) => setState(() => _period = value),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (lift != null) ...[
              Semantics(
                button: true,
                label: 'Change exercise, ${lift.exerciseName}',
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('progress-exercise-picker'),
                  borderRadius: AppRadius.control,
                  onTap:
                      () => _chooseLift(
                        lifts,
                        lift.exerciseId ?? lift.exerciseName,
                        unit,
                      ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            lift.exerciseName,
                            key: const ValueKey('progress-exercise'),
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Icon(
                          LucideIcons.chevronDown,
                          size: 20,
                          color: accentColor(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              const StatisticsSectionHeader(title: 'Exercise progress'),
            Row(
              children: [
                Flexible(
                  child: TextButton.icon(
                    key: const ValueKey('progress-metric-picker'),
                    // Flush with the exercise name above, like a form label.
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed:
                        () => _choose<ExerciseMetric>(
                          title: 'Measure',
                          values: ExerciseMetric.values,
                          selected: _metric,
                          labelFor: (metric) => metric.label,
                          onSelected:
                              (value) => setState(() => _metric = value),
                        ),
                    icon: const Icon(LucideIcons.chevronDown, size: 14),
                    iconAlignment: IconAlignment.end,
                    label: Text(_metric.label),
                  ),
                ),
                IconButton(
                  key: const ValueKey('progress-metric-info'),
                  tooltip: 'About ${_metric.label}',
                  icon: Icon(
                    LucideIcons.info,
                    size: 16,
                    color: textSecondaryColor(context),
                  ),
                  onPressed:
                      () => showDialog<void>(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: Text(_metric.label),
                              content: Text(_metric.description),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (lift == null)
              const _ViewEmpty(
                title: 'No lifts in this period',
                message:
                    'Try a longer time range or another measure. Estimated 1RM uses weighted sets of 1–12 reps.',
                icon: LucideIcons.chartNoAxesCombined,
              )
            else
              StrengthTrend(
                key: ValueKey(
                  'strength-$splitId-${lift.exerciseId ?? lift.exerciseName}-$_period-$_metric',
                ),
                progress: lift.progress,
                metric: _metric,
                weightUnit: unit,
              ),
          ],
        );
      case _StatisticsView.blocks:
        content =
            selectedBlock == null
                ? const _ViewEmpty(
                  title: 'No training blocks logged',
                  message:
                      'Log a workout in a training block to see its weekly workload and strength gains here.',
                  icon: LucideIcons.layers,
                )
                : BlockOverview(
                  key: ValueKey('blocks-$splitId'),
                  blocks: blocks,
                  selected: selectedBlock,
                  currentBlockId: currentBlockId,
                  onSelect: selectBlock,
                  weightUnit: unit,
                );
      case _StatisticsView.records:
        final records = _analytics.recordEvents(sessions);
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal bests',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your best sets, newest first.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (records.isEmpty)
              const _ViewEmpty(
                title: 'No records yet',
                message: 'Log performed sets to start your record history.',
                icon: LucideIcons.trophy,
              )
            else ...[
              for (final event in records.take(_recordLimit))
                RecordEventRow(
                  key: ValueKey(
                    'record-${event.session.id}-${event.exerciseId ?? event.exerciseName}',
                  ),
                  event: event,
                  weightUnit: unit,
                ),
              if (records.length > _recordLimit)
                TextButton(
                  onPressed: () => setState(() => _recordLimit += 12),
                  child: const Text('Show earlier records'),
                ),
            ],
          ],
        );
    }

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: const AppHeader(
        automaticallyImplyLeading: false,
        title: Text('Statistics'),
      ),
      body:
          sessions.isEmpty
              ? const _EmptyStatistics()
              : Column(
                children: [
                  _StatisticsNavigation(
                    selected: _view,
                    onSelected: _selectView,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('statistics-scroll'),
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.xl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 832),
                          child: SizedBox(
                            width: double.infinity,
                            child: content,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _StatisticsNavigation extends StatelessWidget {
  final _StatisticsView selected;
  final ValueChanged<_StatisticsView> onSelected;

  const _StatisticsNavigation({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: borderColor(context))),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scrolls =
                MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                constraints.maxWidth < 350;
            Widget tab(_StatisticsView view) => Semantics(
              button: true,
              selected: view == selected,
              label: view.label,
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('statistics-tab-${view.label}'),
                onTap: () => onSelected(view),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            view == selected
                                ? accentColor(context)
                                : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    view.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color:
                          view == selected
                              ? textPrimaryColor(context)
                              : textSecondaryColor(context),
                      fontWeight:
                          view == selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
            if (scrolls) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final view in _StatisticsView.values) tab(view),
                  ],
                ),
              );
            }
            return Row(
              children: [
                for (final view in _StatisticsView.values)
                  Expanded(child: tab(view)),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _ViewEmpty extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _ViewEmpty({
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: textSecondaryColor(context)),
        const SizedBox(height: AppSpacing.xl),
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: textSecondaryColor(context)),
        ),
      ],
    ),
  );
}

class _EmptyStatistics extends StatelessWidget {
  const _EmptyStatistics();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder:
        (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(
                child: _ViewEmpty(
                  title: 'No completed workouts',
                  message:
                      'Statistics appear after you finish and log a workout.',
                  icon: LucideIcons.chartNoAxesCombined,
                ),
              ),
            ),
          ),
        ),
  );
}
