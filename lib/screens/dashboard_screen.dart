import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/split_provider.dart';
import '../services/hive_service.dart';
import '../widgets/splits/preset_browser_dialog.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/spacing.dart';
import '../utils/plan_stats.dart';
import '../widgets/dashboard/dashboard_panel.dart';
import '../widgets/dashboard/frequency_heatmap.dart';
import '../widgets/dashboard/last_session_tile.dart';
import '../widgets/dashboard/plan_status_tile.dart';
import '../widgets/dashboard/progression_sparkline.dart';
import '../widgets/dashboard/recent_prs_tile.dart';
import '../widgets/dashboard/stat_tile.dart';
import '../widgets/app_button.dart';
import '../widgets/history/history_journal_data.dart';
import 'history_screen.dart';
import 'plan_editor_screen.dart';
import 'workout_screen.dart';

/// Desktop overview: everything the phone spreads across four tabs, on one
/// screen. Reachable from the sidebar only — the phone bottom bar has no room
/// for it, and [AppShell] clamps to Plans below [Breakpoints.medium].
///
/// All numbers are derived from data the app already computes; nothing here
/// introduces a new source of truth.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<WorkoutSessionProvider>().sessions;
    final plans = context.watch<WorkoutPlanProvider>().plans;
    final splitId =
        context.watch<SplitProvider?>()?.activeSplitId ??
        (sessions.isEmpty ? null : sessions.first.splitId);

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: Text(
          'Dashboard',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textPrimaryColor(context)),
        ),
        automaticallyImplyLeading: false,
      ),
      body:
          plans.isEmpty && sessions.isEmpty
              ? const _EmptyState()
              : _buildBody(context, sessions, plans, splitId),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<WorkoutSession> sessions,
    List<WorkoutPlan> plans,
    String? splitId,
  ) {
    final prEntries = PrEntry.fromSessions(sessions);
    final planStats = PlanStat.compute(plans, sessions);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-up panels need room for both columns to stay readable; below that
        // (a narrowed desktop window mid-resize) everything stacks.
        final wide = constraints.maxWidth >= Breakpoints.medium - 180;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kpiRow(
                    context,
                    wide: wide,
                    totalWorkouts: sessions.length,
                    thisWeek: HiveService.getWorkoutsThisWeek(splitId),
                    prsTracked: HiveService.getAllExercisePRs(splitId).length,
                    totalPlans: plans.length,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (sessions.isNotEmpty)
                    _lastSessionPanel(context, sessions.first, plans),
                  if (sessions.isNotEmpty)
                    const SizedBox(height: AppSpacing.lg),
                  _twoUp(
                    wide: wide,
                    left: DashboardPanel(
                      title: 'ACTIVITY',
                      caption: '${sessions.length} SESSIONS',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FrequencyHeatmap(sessions: sessions),
                          const SizedBox(height: AppSpacing.sm),
                          const HeatmapLegend(),
                        ],
                      ),
                    ),
                    right: DashboardPanel(
                      title: 'RECENT PRS',
                      caption: '${prEntries.length} TRACKED',
                      child:
                          prEntries.isEmpty
                              ? const DashboardEmptyLine('No records yet')
                              : RecentPrsTile(entries: prEntries),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _twoUp(
                    wide: wide,
                    left: DashboardPanel(
                      title: 'PLANS',
                      caption: '${plans.length} TOTAL',
                      child:
                          planStats.isEmpty
                              ? const DashboardEmptyLine('No plans yet')
                              : PlanStatusTile(
                                stats: planStats,
                                onOpen:
                                    (stat) => _openPlan(
                                      context,
                                      stat.planIndex,
                                      stat.plan,
                                    ),
                              ),
                    ),
                    right: _progressionPanel(context, sessions, splitId),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _kpiRow(
    BuildContext context, {
    required bool wide,
    required int totalWorkouts,
    required int thisWeek,
    required int prsTracked,
    required int totalPlans,
  }) {
    final tiles = [
      StatTile(label: 'TOTAL WORKOUTS', value: '$totalWorkouts'),
      StatTile(label: 'THIS WEEK', value: '$thisWeek'),
      StatTile(label: 'PRS TRACKED', value: '$prsTracked'),
      StatTile(label: 'TOTAL PLANS', value: '$totalPlans'),
    ];

    Widget row(List<Widget> items) => Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: items[i]),
        ],
      ],
    );

    if (wide) return row(tiles);

    // 2 × 2 when there's no room for four across.
    return Column(
      children: [
        row(tiles.sublist(0, 2)),
        const SizedBox(height: AppSpacing.sm),
        row(tiles.sublist(2)),
      ],
    );
  }

  Widget _lastSessionPanel(
    BuildContext context,
    WorkoutSession last,
    List<WorkoutPlan> plans,
  ) {
    final index = plans.indexWhere(
      (plan) =>
          plan.splitId == last.splitId &&
          (last.planId != null
              ? plan.id == last.planId
              : plan.name.toLowerCase() == last.planName.toLowerCase()),
    );

    return DashboardPanel(
      title: 'LAST SESSION',
      action: AppButton.secondary(
        label: last.isCompleted ? 'View workout' : 'Resume',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder:
                  (_) =>
                      last.isCompleted
                          ? WorkoutDetailsScreen(
                            sessionIdentity: historySessionIdentity(last),
                          )
                          : WorkoutScreen(
                            plan:
                                index >= 0
                                    ? plans[index]
                                    : WorkoutPlan(
                                      name: last.planName,
                                      id: last.planId,
                                      splitId: last.splitId,
                                      exercises: const [],
                                    ),
                            planIndex: index,
                            initialSession: last,
                          ),
            ),
          );
        },
      ),
      child: LastSessionTile(session: last),
    );
  }

  Widget _progressionPanel(
    BuildContext context,
    List<WorkoutSession> sessions,
    String? splitId,
  ) {
    // Plot whichever exercise has the most logged sessions — the one with the
    // most signal. Counted from the sessions already in memory so this costs a
    // single progression read.
    final counts = <String, int>{};
    final display = <String, String>{};
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        final key = exercise.name.toLowerCase();
        display.putIfAbsent(key, () => exercise.name);
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) {
      return const DashboardPanel(
        title: 'PROGRESSION',
        child: DashboardEmptyLine('No exercise data yet'),
      );
    }

    final topKey =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final name = display[topKey]!;
    final progression = HiveService.getExerciseProgression(name, splitId);
    final values = progression.map((p) => p['maxWeight'] as double).toList();

    return DashboardPanel(
      title: 'PROGRESSION',
      caption: '${values.length} SESSIONS',
      child: ProgressionSparkline(exercise: name, values: values),
    );
  }

  Widget _twoUp({
    required bool wide,
    required Widget left,
    required Widget right,
  }) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: AppSpacing.lg), right],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: left),
        const SizedBox(width: AppSpacing.lg),
        Expanded(flex: 2, child: right),
      ],
    );
  }

  void _openPlan(BuildContext context, int index, WorkoutPlan plan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutScreen(plan: plan, planIndex: index),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No data yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a plan and log a workout to fill this in',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxl),
            // Same as the plans empty state: the copy asks for a plan, so the
            // button makes one. Seeding demo data filled the dashboard without
            // ever getting the reader closer to their own numbers.
            AppButton.secondary(
              label: 'New plan',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlanEditorScreen.create(),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton.text(
              label: 'Choose a split',
              onPressed: () {
                PresetBrowserDialog.show(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
