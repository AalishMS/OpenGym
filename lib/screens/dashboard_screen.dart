import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../providers/settings_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../repositories/stats_repository.dart';
import '../services/sample_data_seeder.dart';
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
    final accent = context.watch<SettingsProvider>().accentColor;
    final sessions = context.watch<WorkoutSessionProvider>().sessions;
    final plans = context.watch<WorkoutPlanProvider>().plans;
    final statsRepo = StatsRepository();

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: Text(
          '> DASHBOARD',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 16, fontWeight: FontWeight.bold, color: accent),
        ),
        automaticallyImplyLeading: false,
      ),
      body: plans.isEmpty && sessions.isEmpty
          ? _EmptyState(accent: accent)
          : _buildBody(context, sessions, plans, statsRepo),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<WorkoutSession> sessions,
    List<WorkoutPlan> plans,
    StatsRepository statsRepo,
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
              constraints:
                  const BoxConstraints(maxWidth: Breakpoints.expanded),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kpiRow(
                    context,
                    wide: wide,
                    totalWorkouts: sessions.length,
                    thisWeek: statsRepo.getWorkoutsThisWeek(),
                    prsTracked: statsRepo.getAllExercisePRs().length,
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
                      child: prEntries.isEmpty
                          ? const DashboardEmptyLine('> no records yet')
                          : RecentPrsTile(entries: prEntries),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _twoUp(
                    wide: wide,
                    left: DashboardPanel(
                      title: 'PLANS',
                      caption: '${plans.length} TOTAL',
                      child: planStats.isEmpty
                          ? const DashboardEmptyLine('> no plans yet')
                          : PlanStatusTile(
                              stats: planStats,
                              onOpen: (stat) => _openPlan(
                                context,
                                stat.planIndex,
                                stat.plan,
                              ),
                            ),
                    ),
                    right: _progressionPanel(context, sessions, statsRepo),
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
      BuildContext context, WorkoutSession last, List<WorkoutPlan> plans) {
    final index = plans.indexWhere(
      (p) => p.name.toLowerCase() == last.planName.toLowerCase(),
    );

    return DashboardPanel(
      title: 'LAST SESSION',
      // A deleted or renamed plan can't be reopened — the button greys out
      // rather than disappearing, so the row keeps its shape.
      action: BracketButton(
        label: ' RESUME ',
        onTap: index >= 0
            ? () => _openPlan(context, index, plans[index])
            : null,
      ),
      child: LastSessionTile(session: last),
    );
  }

  Widget _progressionPanel(
    BuildContext context,
    List<WorkoutSession> sessions,
    StatsRepository statsRepo,
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
        child: DashboardEmptyLine('> no exercise data yet'),
      );
    }

    final topKey =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final name = display[topKey]!;
    final progression = statsRepo.getExerciseProgression(name);
    final values =
        progression.map((p) => p['maxWeight'] as double).toList();

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
        children: [
          left,
          const SizedBox(height: AppSpacing.lg),
          right,
        ],
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
  final Color accent;

  const _EmptyState({required this.accent});

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '> NO DATA',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 16, color: textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a plan and log a workout to fill this in',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxl),
            OutlinedButton(
              onPressed: () async {
                await SampleDataSeeder.seedSampleData();
                if (!context.mounted) return;
                context.read<WorkoutPlanProvider>().loadPlans();
                context.read<WorkoutSessionProvider>().loadSessions();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('> Sample data loaded!',
                        style: GoogleFonts.jetBrainsMono(
                            color: onAccentColor(context))),
                    backgroundColor: accent,
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent, width: 1),
              ),
              child:
                  Text('[ LOAD SAMPLE DATA ]', style: GoogleFonts.jetBrainsMono()),
            ),
          ],
        ),
      ),
    );
  }
}
