import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
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
import 'plan_editor_screen.dart';
import 'workout_screen.dart';
import '../services/sample_data_seeder.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final bg = backgroundColor(context);
    final border = borderColor(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(context, accent, border),
            Expanded(
              child: Consumer<WorkoutPlanProvider>(
                builder: (context, provider, child) {
                  if (provider.plans.isEmpty) {
                    return _buildEmptyState(context, provider, accent);
                  }
                  return _buildPlanSection(context, provider, accent);
                },
              ),
            ),
            // Hidden while the list is empty: the empty state carries the same
            // action as its primary button, and two `[+ NEW PLAN]`s on one
            // screen make the reader pick between identical doors.
            Consumer<WorkoutPlanProvider>(
              builder: (context, provider, child) {
                if (provider.plans.isEmpty) return const SizedBox.shrink();
                return _CappedWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildNewPlanButton(context, accent),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, Color border) {
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
              padding: const EdgeInsets.all(16),
              child: _CappedWidth(
                child: Row(
                  children: [
                    Text(
                      '> OPENGYM',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WorkoutPlanProvider provider,
    Color accent,
  ) {
    final textSecondary = textSecondaryColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '> NO PLANS FOUND',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create your first workout plan',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            // The line above has always said "create your first workout plan",
            // but the only button here seeded demo data — the one thing a
            // first-run screen exists to start could not be started from it.
            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlanEditorScreen.create(),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent, width: 1),
              ),
              child: Text('[+ NEW PLAN]', style: GoogleFonts.jetBrainsMono()),
            ),
            const SizedBox(height: AppSpacing.md),
            // Sample data stays reachable for someone who wants to look around
            // before committing to their own plan, at text weight so it reads
            // as the way out rather than the way in. It also lives in Settings.
            TextButton(
              onPressed: () async {
                await SampleDataSeeder.seedSampleData();
                provider.loadPlans();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '> Sample data loaded!',
                        style: GoogleFonts.jetBrainsMono(
                          color: onAccentColor(context),
                        ),
                      ),
                      backgroundColor: accentFillColor(context),
                    ),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: textSecondary),
              child: Text(
                '[LOAD SAMPLE DATA]',
                style: GoogleFonts.jetBrainsMono(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSection(
    BuildContext context,
    WorkoutPlanProvider provider,
    Color accent,
  ) {
    // Roll up each plan's training history once, keyed by its index in
    // `provider.plans`, so the card footers don't each hit the repository.
    final sessions = context.watch<WorkoutSessionProvider>().sessions;
    final statsByIndex = {
      for (final stat in PlanStat.compute(provider.plans, sessions))
        stat.planIndex: stat,
    };

    return _CappedWidth(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        // Max-extent (not a fixed column count) so columns scale with the
        // window: 2 on a phone, 5 at the capped desktop measure. A fixed
        // `mainAxisExtent` replaces `childAspectRatio` — the old ratio made
        // cards as tall as the column was wide, which on desktop meant two
        // enormous, mostly-empty boxes.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 220,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: provider.plans.length,
        itemBuilder:
            (context, index) => _buildPlanCard(
              context,
              provider.plans[index],
              index,
              accent,
              statsByIndex[index],
            ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    WorkoutPlan plan,
    int index,
    Color accent,
    PlanStat? stat,
  ) {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final planColor = planColorOf(plan.planColor, context);

    final exerciseNames = plan.exercises.map((e) => e.name).toList();
    final previewLines = exerciseNames.take(3).toList();

    void openWorkout() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutScreen(plan: plan, planIndex: index),
        ),
      );
    }

    return InkWell(
      onTap: openWorkout,
      onLongPress: () => _showPlanOptions(context, plan, index, accent, stat),
      borderRadius: AppRadius.card,
      child: Container(
        // Clips the full-bleed accent strip below to the rounded corners.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border, width: 1),
          borderRadius: AppRadius.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 2, color: planColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Index and title share a line — on its own row the `[01]`
                    // cost 20px of height for four characters.
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 48),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '[${(index + 1).toString().padLeft(2, '0')}]',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  color: textSecondary,
                                  letterSpacing: 0.08,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  _titleCase(plan.name),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                    letterSpacing: 0.04,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: -14,
                          right: 0,
                          child: IconButton(
                            tooltip: 'Plan actions',
                            onPressed:
                                () => _showPlanOptions(
                                  context,
                                  plan,
                                  index,
                                  accent,
                                  stat,
                                ),
                            icon: Icon(
                              LucideIcons.ellipsis,
                              size: 18,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${plan.exercises.length} exercises  ·  '
                      '${_lastTrainedLabel(stat)}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...previewLines.map(
                      (name) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                        child: Text(
                          '· $name',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textSecondary,
                            letterSpacing: 0.02,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (exerciseNames.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                        child: Text(
                          '+${exerciseNames.length - 3} more',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textSecondary.withAlpha(128),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      _planFooter(plan, stat),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: planColor,
                        letterSpacing: 0.06,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `2D AGO · 3 SESSIONS · 5 EX`, degrading to just the exercise count for a
  /// plan that has never been trained.
  String _planFooter(WorkoutPlan plan, PlanStat? stat) {
    if (stat == null || stat.sessionCount == 0) {
      return '${plan.exercises.length} EXERCISES';
    }
    return '${formatRelativeDay(stat.lastTrained!)}'
        '  ·  ${stat.sessionCount} SESSIONS'
        '  ·  ${plan.exercises.length} EX';
  }

  String _lastTrainedLabel(PlanStat? stat) {
    if (stat?.lastTrained == null) return 'Never trained';
    return 'Last trained ${formatRelativeDay(stat!.lastTrained!).toLowerCase()}';
  }

  String _titleCase(String name) {
    return name
        .trim()
        .split(RegExp(r'\s+'))
        .map(
          (word) =>
              word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Widget _buildNewPlanButton(BuildContext context, Color accent) {
    final textSecondary = textSecondaryColor(context);
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlanEditorScreen.create()),
        );
      },
      borderRadius: AppRadius.button,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withAlpha(60)),
          borderRadius: AppRadius.button,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, size: 12, color: textSecondary),
            const SizedBox(width: 8),
            Text(
              '[+ NEW PLAN]',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                letterSpacing: 0.1,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
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
                                  _titleCase(plan.name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                    letterSpacing: 0.04,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  _planFooter(plan, stat),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    color: textSecondary,
                                    letterSpacing: 0.06,
                                  ),
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
                      label: 'CHANGE COLOR',
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
                      label: 'DUPLICATE PLAN',
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
                              '> Plan copied!',
                              style: GoogleFonts.jetBrainsMono(
                                color: onAccentColor(context),
                              ),
                            ),
                            backgroundColor: accentFillColor(context),
                          ),
                        );
                      },
                    ),
                    _PlanActionRow(
                      icon: LucideIcons.pencil,
                      label: 'EDIT PLAN',
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
                      label: 'DELETE PLAN',
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
                      '> ${_titleCase(plan.name)} — COLOR',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SELECT PLAN COLOR',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: textSecondary,
                      ),
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
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final updated = plan.copyWith(
                              planColor: selectedColor,
                            );
                            context.read<WorkoutPlanProvider>().updatePlan(
                              updated,
                            );
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentFillColor(context),
                            foregroundColor: onAccentColor(context),
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.button,
                            ),
                          ),
                          child: Text(
                            '[SAVE]',
                            style: GoogleFonts.jetBrainsMono(),
                          ),
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
/// The plans grid sizes columns by max extent, so an ultra-wide monitor gave it
/// ten columns and a card's three-line preview stretched a hand-span across the
/// desk. Header, grid, and footer button all sit in the same capped measure, so
/// they share one left edge; only the header's ground and its rule still run
/// full-bleed, because a rule is screen furniture rather than content.
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
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: color,
                    letterSpacing: 0.06,
                  ),
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
