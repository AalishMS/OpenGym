import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/split_provider.dart';
import '../models/workout_plan.dart';
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
import '../widgets/home/plan_card.dart';
import '../widgets/home/up_next_card.dart';
import '../widgets/home/training_snapshot.dart';
import 'plan_editor_screen.dart';
import 'workout_screen.dart';
import '../widgets/splits/preset_browser_dialog.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final bg = backgroundColor(context);
    final border = borderColor(context);

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: surfaceColor(context),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PlanEditorScreen.create()),
          );
        },
        tooltip: 'Create plan',
        child: const Icon(LucideIcons.plus),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context, border),
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

  Widget _buildHeader(BuildContext context, Color border) {
    final splitProvider = context.watch<SplitProvider?>();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: headerMesh(context)),
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: _CappedWidth(
                child: Row(
                  children: [
                    const Expanded(
                      child: AppWordmark(
                        fontSize: 18,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                    if (splitProvider != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const Flexible(child: SplitSwitcher()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WorkoutPlanProvider provider) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
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
    // Roll up each plan's training history once, keyed by its index in
    // `provider.plans`, so the cards don't each hit the repository.
    final sessions = context.watch<WorkoutSessionProvider>().sessions;
    final stats = PlanStat.compute(plans, sessions);
    final statsByIndex = {for (final stat in stats) stat.planIndex: stat};
    // With a single plan there is no rotation to point into: its card already
    // is the next workout, and a second copy of it above would only repeat it.
    final nextIndex =
        plans.length > 1 ? PlanStat.nextInRotation(stats, plans.length) : null;

    return _CappedWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          _fabClearance,
        ),
        children: [
          if (nextIndex != null) ...[
            UpNextCard(
              plan: plans[nextIndex],
              day: nextIndex + 1,
              dayCount: plans.length,
              stat: statsByIndex[nextIndex],
              onStart: () => _openWorkout(context, plans[nextIndex], nextIndex),
              footer: TrainingSnapshot(plans: plans, sessions: sessions),
            ),
            const SizedBox(height: AppSpacing.xl),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: surfaceColor(context),
                border: Border.all(color: borderColor(context)),
                borderRadius: AppRadius.card,
              ),
              child: TrainingSnapshot(plans: plans, sessions: sessions),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          _SectionHeading(title: 'Your plans', count: plans.length),
          const SizedBox(height: AppSpacing.md),
          _buildPlanGrid(context, plans, statsByIndex, accent),
        ],
      ),
    );
  }

  /// Room under the last card for the floating create button, which otherwise
  /// sits on top of the last card's summary line.
  static const double _fabClearance = 96;

  /// Narrowest a card gets before the grid drops a column.
  static const double _minCardWidth = 340;
  static const int _maxColumns = 3;

  Widget _buildPlanGrid(
    BuildContext context,
    List<WorkoutPlan> plans,
    Map<int, PlanStat> statsByIndex,
    Color accent,
  ) {
    Widget card(int index) => PlanCard(
      plan: plans[index],
      index: index,
      stat: statsByIndex[index],
      onOpen: () => _openWorkout(context, plans[index], index),
      onShowActions:
          () => _showPlanOptions(
            context,
            plans[index],
            index,
            accent,
            statsByIndex[index],
          ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth / _minCardWidth).floor();
        final columns = fit < 1 ? 1 : (fit > _maxColumns ? _maxColumns : fit);

        // Rows rather than a fixed-extent grid: a row is as tall as its tallest
        // card, so large text grows the cards instead of clipping them, and the
        // cards in a row still share one height.
        final rows = <Widget>[];
        for (var start = 0; start < plans.length; start += columns) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: _cardGap));
          if (columns == 1) {
            rows.add(card(start));
            continue;
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: _cardGap),
                    Expanded(
                      child:
                          start + column < plans.length
                              ? card(start + column)
                              : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  static const double _cardGap = 10;

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
