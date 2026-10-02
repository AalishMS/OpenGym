import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/split_provider.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/exercise_template.dart';
import '../models/set_template.dart';
import '../data/plan_colors.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/format.dart';
import '../utils/plan_stats.dart';
import '../widgets/workout/workout_dialogs.dart';
import '../widgets/splits/split_switcher.dart';
import '../widgets/app_button.dart';
import '../widgets/app_wordmark.dart';
import '../widgets/home/plan_grid.dart';
import '../widgets/home/home_plan_row.dart';
import '../widgets/home/up_next_card.dart';
import '../widgets/home/training_snapshot.dart';
import 'plan_editor_screen.dart';
import 'workout_screen.dart';
import '../widgets/splits/preset_browser_dialog.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenWeeklyTraining;
  final ValueChanged<WorkoutSession>? onOpenLastWorkout;
  final GlobalKey? tutorialPlanKey;
  final GlobalKey? tutorialStartKey;
  final ScrollController? tutorialScrollController;
  final bool tutorialActive;

  const HomeScreen({
    this.onOpenWeeklyTraining,
    this.onOpenLastWorkout,
    this.tutorialPlanKey,
    this.tutorialStartKey,
    this.tutorialScrollController,
    this.tutorialActive = false,
    super.key,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _managing = false;

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tutorialActive && !oldWidget.tutorialActive) _managing = false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final bg = backgroundColor(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Consumer<WorkoutPlanProvider>(
                builder: (context, provider, child) {
                  if (provider.plans.isEmpty) {
                    return _buildEmptyState(context, provider);
                  }
                  return _buildPlanSection(context, provider, accent);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final splitProvider = context.watch<SplitProvider?>();
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: _CappedWidth(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: AppWordmark(
                  fontSize: 20,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ),
              if (splitProvider != null) ...[
                const SizedBox(width: AppSpacing.sm),
                const Flexible(child: IntrinsicWidth(child: SplitSwitcher())),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WorkoutPlanProvider provider) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        controller: widget.tutorialScrollController,
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: surfaceColor(context),
                  border: Border.all(color: borderColor(context), width: 1),
                  borderRadius: AppRadius.card,
                ),
                child: Icon(
                  LucideIcons.clipboardList,
                  size: 32,
                  color: accentColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'No plans yet',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  color: textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Build a plan of your own, or start from a proven split '
                'and make it yours.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                key: widget.tutorialPlanKey,
                width: double.infinity,
                child: AppButton.primary(
                  label: 'Create plan',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PlanEditorScreen.create(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton.text(
                label: 'Choose a split',
                onPressed: () {
                  PresetBrowserDialog.show(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanSection(
    BuildContext context,
    WorkoutPlanProvider provider,
    Color accent,
  ) {
    final plans = provider.plans;
    final sessions = context.watch<WorkoutSessionProvider>().sessions;
    final stats = PlanStat.compute(plans, sessions);
    final statsByIndex = {for (final stat in stats) stat.planIndex: stat};
    final nextIndex = PlanStat.nextInRotation(stats, plans.length);
    final today = DateTime.now();
    final weekStart = startOfWeek(today);
    final trainedDays = {
      for (final stat in stats)
        if (stat.lastTrained != null &&
            !stat.lastTrained!.isBefore(weekStart) &&
            calendarDaysBetween(stat.lastTrained!, today) >= 0)
          stat.planIndex,
    };
    final timedSessions =
        sessions
            .where(
              (session) =>
                  session.isCompleted &&
                  (session.durationSeconds ?? 0) > 0 &&
                  (session.planId != null && plans[nextIndex].id != null
                      ? session.planId == plans[nextIndex].id
                      : session.planName.toLowerCase() ==
                          plans[nextIndex].name.toLowerCase()),
            )
            .toList();
    final durationMinutes =
        timedSessions.isEmpty
            ? null
            : (timedSessions.fold<int>(
                      0,
                      (sum, session) => sum + session.durationSeconds!,
                    ) /
                    timedSessions.length /
                    60)
                .round()
                .clamp(1, 99999);

    void actions(int index) => _showPlanOptions(
      context,
      plans[index],
      index,
      accent,
      statsByIndex[index],
    );

    return _CappedWidth(
      child: ListView(
        controller: widget.tutorialScrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          if (!_managing) ...[
            UpNextCard(
              tutorialStartKey: widget.tutorialStartKey,
              plan: plans[nextIndex],
              day: nextIndex + 1,
              dayCount: plans.length,
              stat: statsByIndex[nextIndex],
              trainedDays: trainedDays,
              durationMinutes: durationMinutes,
              onStart: () => _openWorkout(context, plans[nextIndex], nextIndex),
            ),
            const SizedBox(height: AppSpacing.lg),
            TrainingSnapshot(
              plans: plans,
              sessions: sessions,
              onOpenWeeklyTraining: widget.onOpenWeeklyTraining,
              onOpenLastWorkout: widget.onOpenLastWorkout,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          Row(
            children: [
              Expanded(
                child: _SectionHeading(
                  title: 'Your plans',
                  count: plans.length,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => setState(() => _managing = !_managing),
                child: Text(_managing ? 'Done' : 'Manage'),
              ),
            ],
          ),
          if (_managing) ...[
            const SizedBox(height: AppSpacing.sm),
            PlanGrid(
              plans: plans,
              stats: statsByIndex,
              onOpen: (index) => _openWorkout(context, plans[index], index),
              onShowActions: actions,
              onMove: (fromId, toId) => _movePlan(context, fromId, toId),
            ),
          ] else ...[
            Divider(height: 1, color: borderColor(context)),
            for (var index = 0; index < plans.length; index++) ...[
              HomePlanRow(
                key: ValueKey(plans[index].id),
                plan: plans[index],
                isNext: index == nextIndex,
                onOpen: () => _openWorkout(context, plans[index], index),
                onShowActions: () => actions(index),
              ),
              if (index < plans.length - 1 &&
                  index != nextIndex &&
                  index + 1 != nextIndex)
                Divider(height: 1, color: borderColor(context)),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: widget.tutorialPlanKey,
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('New plan'),
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PlanEditorScreen.create(),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _movePlan(
    BuildContext context,
    String fromId,
    String toId,
  ) async {
    final provider = context.read<WorkoutPlanProvider>();
    final plans = provider.plans;
    final oldIndex = plans.indexWhere((plan) => plan.id == fromId);
    final newIndex = plans.indexWhere((plan) => plan.id == toId);
    if (oldIndex < 0 || newIndex < 0 || oldIndex == newIndex) return;
    try {
      await provider.reorderPlans(oldIndex, newIndex);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save plan order')),
        );
      }
    }
  }

  void _movePlanOneStep(BuildContext context, String planId, int step) {
    final plans = context.read<WorkoutPlanProvider>().plans;
    final index = plans.indexWhere((plan) => plan.id == planId);
    final target = index + step;
    if (index < 0 || target < 0 || target >= plans.length) return;
    _movePlan(context, planId, plans[target].id!);
  }

  void _openWorkout(BuildContext context, WorkoutPlan plan, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutScreen(plan: plan, planIndex: index),
      ),
    );
  }

  /// `4 exercises · last trained yesterday`, for the plan menu's header.
  String _planSummary(WorkoutPlan plan, PlanStat? stat) {
    final count = plan.exercises.length;
    final exercises = count == 1 ? '1 exercise' : '$count exercises';
    final last = stat?.lastTrained;
    if (last == null) return '$exercises  ·  not trained yet';
    return '$exercises  ·  last trained ${formatDaysAgo(last).toLowerCase()}';
  }

  void _showPlanOptions(
    BuildContext context,
    WorkoutPlan plan,
    int index,
    Color accent,
    PlanStat? stat,
  ) {
    final planColor = planColorOf(plan.planColor, context);
    final planCount = context.read<WorkoutPlanProvider>().plans.length;
    final border = borderColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);

    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: surfaceColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: border, width: 1),
            ),
            // Without a cap the dialog takes Material's share of a desktop window
            // and the four rows end up a hand-span apart.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                // Vertical inset only — the header and rows carry their own
                // horizontal padding, so the two rules run full-bleed.
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The header names what you long-pressed and echoes the card's
                    // colour bar, so there's no doubt which plan is about to change.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 28,
                            decoration: BoxDecoration(
                              color: planColor,
                              borderRadius: AppRadius.micro,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titleCase(plan.name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(color: textPrimary),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  _planSummary(plan, stat),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: border),
                    _PlanActionRow(
                      icon: LucideIcons.paintbrush,
                      label: 'Change color',
                      color: textPrimary,
                      // Shows the current value without opening the picker.
                      trailing: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: planColor,
                          borderRadius: AppRadius.badge,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showColorPickerDialog(context, plan, index, accent);
                      },
                    ),
                    _PlanActionRow(
                      icon: LucideIcons.copy,
                      label: 'Duplicate plan',
                      color: textPrimary,
                      onTap: () {
                        Navigator.pop(ctx);
                        final copyPlan = WorkoutPlan(
                          name: '${plan.name} (Copy)',
                          exercises:
                              plan.exercises
                                  .map(
                                    (e) => ExerciseTemplate(
                                      name: e.name,
                                      sets: e.sets,
                                      setTargets:
                                          e.setTargets
                                              ?.map(
                                                (t) => SetTemplate(
                                                  reps: t.reps,
                                                  weight: t.weight,
                                                ),
                                              )
                                              .toList(),
                                    ),
                                  )
                                  .toList(),
                          planColor: plan.planColor,
                        );
                        context.read<WorkoutPlanProvider>().addPlan(copyPlan);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Plan copied',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: onAccentColor(context)),
                            ),
                            backgroundColor: accentFillColor(context),
                          ),
                        );
                      },
                    ),
                    _PlanActionRow(
                      icon: LucideIcons.pencil,
                      label: 'Edit plan',
                      color: textPrimary,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlanEditorScreen.edit(plan),
                          ),
                        );
                      },
                    ),
                    if (index > 0)
                      _PlanActionRow(
                        icon: LucideIcons.arrowUp,
                        label: 'Move earlier',
                        color: textPrimary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _movePlanOneStep(context, plan.id!, -1);
                        },
                      ),
                    if (index < planCount - 1)
                      _PlanActionRow(
                        icon: LucideIcons.arrowDown,
                        label: 'Move later',
                        color: textPrimary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _movePlanOneStep(context, plan.id!, 1);
                        },
                      ),
                    // A rule and the error colour set the one irreversible action
                    // apart; deleting also asks first, which it never used to.
                    Divider(height: 1, thickness: 1, color: border),
                    _PlanActionRow(
                      icon: LucideIcons.trash2,
                      label: 'Delete plan',
                      color: errorColor(context),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final confirmed =
                            await WorkoutDialogs.showDeletePlanDialog(
                              context,
                              planName: plan.name,
                            );
                        if (confirmed && context.mounted) {
                          context.read<WorkoutPlanProvider>().deletePlan(
                            plan.id!,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _showColorPickerDialog(
    BuildContext context,
    WorkoutPlan plan,
    int planIndex,
    Color accent,
  ) {
    int? selectedColor = plan.planColor;
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.card,
                side: BorderSide(color: border, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${titleCase(plan.name)} color',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select plan color',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: List.generate(kPlanColors.length, (slot) {
                        final colorValue = kPlanColors[slot];
                        // The chip shows the tone this slot resolves to in the
                        // current mode, so what you tap is what gets painted.
                        // Selection is matched by slot, not by value, so a plan
                        // saved before the palette change still highlights.
                        final color = planSwatch(slot, context);
                        final isSelected =
                            selectedColor != null &&
                            planSlotOf(selectedColor!) == slot;
                        return Semantics(
                          label: 'Plan color ${slot + 1}',
                          button: true,
                          selected: isSelected,
                          child: InkWell(
                            onTap:
                                () => setDialogState(
                                  () => selectedColor = colorValue,
                                ),
                            borderRadius: AppRadius.control,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: color,
                                border: Border.all(
                                  color:
                                      isSelected ? accent : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: AppRadius.control,
                              ),
                              child:
                                  isSelected
                                      ? Icon(
                                        LucideIcons.check,
                                        size: 18,
                                        color: onColor(color),
                                      )
                                      : null,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AppButton.text(
                          label: 'Cancel',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        const SizedBox(width: 8),
                        AppButton.primary(
                          label: 'Save',
                          onPressed: () {
                            final updated = plan.copyWith(
                              planColor: selectedColor,
                            );
                            context.read<WorkoutPlanProvider>().updatePlan(
                              updated,
                            );
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Centres its child and caps it at [Breakpoints.expanded].
///
/// Without a cap an ultra-wide monitor stretched the plans a hand-span across
/// the desk. Header, up-next card, and plans all sit in the same capped
/// measure, so they share one left edge; only the header's ground and its
/// rule still run full-bleed, because a rule is screen furniture rather than
/// content.
class _CappedWidth extends StatelessWidget {
  final Widget child;

  const _CappedWidth({required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
        child: child,
      ),
    );
  }
}

/// A list heading with its count set beside it as data: `Your plans  6`.
class _SectionHeading extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeading({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textPrimaryColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the long-press plan menu.
///
/// No ground and no outline: the header's colour bar is the only accent in the
/// dialog, so the rows stay quiet and the destructive one is set apart by colour
/// and a rule instead of competing with three identical outlined pills. The
/// splash stays square because the row is a full-bleed strip, not a rounded box.
class _PlanActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? trailing;
  final VoidCallback onTap;

  const _PlanActionRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.lg,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
