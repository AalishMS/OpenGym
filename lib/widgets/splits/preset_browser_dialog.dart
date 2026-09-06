import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/plan_colors.dart';
import '../../data/workout_presets.dart';
import '../../providers/split_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../app_button.dart';

class PresetBrowserDialog extends StatefulWidget {
  final BuildContext hostContext;

  const PresetBrowserDialog({required this.hostContext, super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => PresetBrowserDialog(hostContext: context),
  );

  @override
  State<PresetBrowserDialog> createState() => _PresetBrowserDialogState();
}

class _PresetBrowserDialogState extends State<PresetBrowserDialog> {
  WorkoutPreset? _selected;
  bool _installing = false;
  String? _error;

  Future<void> _install(WorkoutPreset preset) async {
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      final result = await widget.hostContext
          .read<SplitProvider>()
          .installPreset(preset);
      if (!mounted || !widget.hostContext.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.maybeOf(widget.hostContext)?.showSnackBar(
        SnackBar(
          backgroundColor: accentFillColor(widget.hostContext),
          content: Text(
            '${result.splitName} added and selected',
            style: Theme.of(widget.hostContext).textTheme.bodyMedium?.copyWith(
              color: onAccentColor(widget.hostContext),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error =
            error is StateError
                ? error.message
                : 'Could not add this program. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;
    final content = _BrowserFrame(
      selected: _selected,
      installing: _installing,
      error: _error,
      onClose: () => Navigator.pop(context),
      onBack:
          () => setState(() {
            _selected = null;
            _error = null;
          }),
      onSelect:
          (preset) => setState(() {
            _selected = preset;
            _error = null;
          }),
      onInstall: _install,
    );
    if (compact) {
      return Dialog.fullscreen(
        backgroundColor: backgroundColor(context),
        child: SafeArea(child: content),
      );
    }
    return Dialog(
      backgroundColor: backgroundColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: borderColor(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 780),
        child: content,
      ),
    );
  }
}

class _BrowserFrame extends StatelessWidget {
  final WorkoutPreset? selected;
  final bool installing;
  final String? error;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final ValueChanged<WorkoutPreset> onSelect;
  final ValueChanged<WorkoutPreset> onInstall;

  const _BrowserFrame({
    required this.selected,
    required this.installing,
    required this.error,
    required this.onClose,
    required this.onBack,
    required this.onSelect,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _BrowserHeader(
          preset: selected,
          onBack: selected == null ? null : onBack,
          onClose: onClose,
        ),
        Expanded(
          child:
              selected == null
                  ? _CatalogOverview(onSelect: onSelect)
                  : _PresetDetails(preset: selected!),
        ),
        if (selected != null)
          _InstallBar(
            preset: selected!,
            installing: installing,
            error: error,
            onInstall: onInstall,
          ),
      ],
    );
  }
}

class _BrowserHeader extends StatelessWidget {
  final WorkoutPreset? preset;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  const _BrowserHeader({
    required this.preset,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            if (onBack != null)
              AppIconButton(
                label: 'Back to workout presets',
                icon: LucideIcons.chevronLeft,
                onPressed: onBack,
              )
            else
              const SizedBox(width: 48),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    preset?.name ?? 'Workout presets',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                  if (preset == null)
                    Text(
                      'Built in, ready to make your own',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: textSecondaryColor(context),
                      ),
                    ),
                ],
              ),
            ),
            AppIconButton(
              label: 'Close workout presets',
              icon: LucideIcons.x,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogOverview extends StatelessWidget {
  final ValueChanged<WorkoutPreset> onSelect;

  const _CatalogOverview({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('preset-catalog'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Choose a schedule you can repeat consistently. You can edit every plan after adding it.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: textSecondaryColor(context),
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final goal in WorkoutPresetGoal.values) ...[
          _GoalHeading(goal: goal),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 720 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3;
              final presets =
                  workoutPresets
                      .where((preset) => preset.goal == goal)
                      .toList();
              if (!wide) {
                return Column(
                  children: [
                    for (final preset in presets) ...[
                      _PresetCard(
                        preset: preset,
                        onTap: () => onSelect(preset),
                      ),
                      if (preset != presets.last)
                        const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              }
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.95,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                children: [
                  for (final preset in presets)
                    _PresetCard(preset: preset, onTap: () => onSelect(preset)),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
    );
  }
}

class _GoalHeading extends StatelessWidget {
  final WorkoutPresetGoal goal;

  const _GoalHeading({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 24,
          decoration: BoxDecoration(
            color: accentColor(context),
            borderRadius: AppRadius.micro,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          _goalLabel(goal),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: textPrimaryColor(context)),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final WorkoutPreset preset;
  final VoidCallback onTap;

  const _PresetCard({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final accent = accentColor(context);

    return Semantics(
      button: true,
      label: '${preset.name}, ${preset.days} training days, ${preset.duration}',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: surfaceColor(context),
            border: Border.all(color: borderColor(context)),
            borderRadius: AppRadius.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    preset.id,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: textPrimary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${preset.days} days · ${preset.duration} · ${preset.splitStyle}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    LucideIcons.userCheck,
                    size: 13,
                    color: accent,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      preset.bestFit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '7-day rotation',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: textSecondary.withAlpha(150),
                            fontSize: 10,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _ScheduleStrip(preset: preset),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: textSecondary.withAlpha(120),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleStrip extends StatelessWidget {
  final WorkoutPreset preset;

  const _ScheduleStrip({required this.preset});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${preset.scheduleSlots.length}-day schedule with ${preset.days} workouts',
      child: Row(
        children: [
          for (var index = 0; index < preset.scheduleSlots.length; index++) ...[
            Expanded(child: _ScheduleCell(preset: preset, slotIndex: index)),
            if (index < preset.scheduleSlots.length - 1)
              const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _ScheduleCell extends StatelessWidget {
  final WorkoutPreset preset;
  final int slotIndex;

  const _ScheduleCell({required this.preset, required this.slotIndex});

  @override
  Widget build(BuildContext context) {
    final planIndex = preset.scheduleSlots[slotIndex];
    final color =
        planIndex == null
            ? borderColor(context)
            : planColorOf(
              kPlanColors[preset.plans[planIndex].colorSlot],
              context,
            );
    return Tooltip(
      message:
          planIndex == null
              ? 'Day ${slotIndex + 1}: Rest'
              : preset.plans[planIndex].name,
      child: Container(
        height: 7,
        decoration: BoxDecoration(color: color, borderRadius: AppRadius.micro),
      ),
    );
  }
}

class _PresetDetails extends StatelessWidget {
  final WorkoutPreset preset;

  const _PresetDetails({required this.preset});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: ValueKey('preset-details-${preset.id}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _PresetOverviewCard(preset: preset),
        const SizedBox(height: AppSpacing.sm),
        _PresetBestFitBanner(bestFit: preset.bestFit),
        const SizedBox(height: AppSpacing.lg),
        Text(
          preset.summary,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: textPrimaryColor(context),
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          preset.schedule,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: textSecondaryColor(context),
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ScheduleStrip(preset: preset),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Workout days',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: textPrimaryColor(context)),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var index = 0; index < preset.plans.length; index++) ...[
          _PlanExpansion(plan: preset.plans[index], position: index),
          if (index < preset.plans.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Before you start',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: textPrimaryColor(context)),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final guidance in workoutPresetGuidance)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accentColor(context),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    guidance,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textSecondaryColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PresetOverviewCard extends StatelessWidget {
  final WorkoutPreset preset;

  const _PresetOverviewCard({required this.preset});

  @override
  Widget build(BuildContext context) {
    final border = borderColor(context);
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: border),
        borderRadius: AppRadius.card,
      ),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _OverviewMetric(
              icon: LucideIcons.calendar,
              value: '${preset.days} days',
              caption: 'Per week',
            ),
          ),
          Container(width: 1, height: 28, color: border),
          Expanded(
            child: _OverviewMetric(
              icon: LucideIcons.clock,
              value: preset.duration,
              caption: 'Per session',
            ),
          ),
          Container(width: 1, height: 28, color: border),
          Expanded(
            child: _OverviewMetric(
              icon: LucideIcons.target,
              value: _goalLabel(preset.goal),
              caption: 'Focus',
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String caption;

  const _OverviewMetric({
    required this.icon,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _PresetBestFitBanner extends StatelessWidget {
  final String bestFit;

  const _PresetBestFitBanner({required this.bestFit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.userCheck, size: 14, color: accentColor(context)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Best fit: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              bestFit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanExpansion extends StatelessWidget {
  final WorkoutPresetPlan plan;
  final int position;

  const _PlanExpansion({required this.plan, required this.position});

  @override
  Widget build(BuildContext context) {
    final planColor = planColorOf(kPlanColors[plan.colorSlot], context);
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.card,
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        leading: Container(
          width: 3,
          height: 28,
          decoration: BoxDecoration(
            color: planColor,
            borderRadius: AppRadius.micro,
          ),
        ),
        title: Text(
          plan.name,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: textPrimaryColor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${plan.exercises.length} exercises',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: textSecondaryColor(context)),
        ),
        children: [
          for (var index = 0; index < plan.exercises.length; index++)
            _ExercisePrescription(
              exercise: plan.exercises[index],
              showDivider: index > 0,
            ),
        ],
      ),
    );
  }
}

class _ExercisePrescription extends StatelessWidget {
  final WorkoutPresetExercise exercise;
  final bool showDivider;

  const _ExercisePrescription({
    required this.exercise,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderColor(context);
    final accent = accentColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration:
          showDivider
              ? BoxDecoration(
                border: Border(top: BorderSide(color: border)),
              )
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                exercise.prescription,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Seed ${exercise.seedReps.join(' / ')}  ·  RIR ${exercise.rir}  ·  Rest ${exercise.rest}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textSecondary,
            ),
          ),
          if (exercise.note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.info, size: 13, color: accent),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    exercise.note!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: accent,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (exercise.substitutions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    LucideIcons.shuffle,
                    size: 13,
                    color: textSecondary.withAlpha(140),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Alternatives: ${exercise.substitutions.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InstallBar extends StatelessWidget {
  final WorkoutPreset preset;
  final bool installing;
  final String? error;
  final ValueChanged<WorkoutPreset> onInstall;

  const _InstallBar({
    required this.preset,
    required this.installing,
    required this.error,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SplitProvider>();
    final blockReason = provider.presetInstallBlockReason;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stack =
                constraints.maxWidth < 460 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final message = Text(
              error ??
                  blockReason ??
                  'Adds ${preset.days} ordered workout plans',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    error != null || blockReason != null
                        ? errorColor(context)
                        : textSecondaryColor(context),
              ),
            );
            final button = AppButton.primary(
              key: const ValueKey('install-preset-action'),
              label: 'Use this split',
              onPressed:
                  installing || blockReason != null
                      ? null
                      : () => onInstall(preset),
              child:
                  installing
                      ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: onAccentColor(context),
                        ),
                      )
                      : null,
            );
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  message,
                  const SizedBox(height: AppSpacing.sm),
                  button,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: message),
                const SizedBox(width: AppSpacing.md),
                button,
              ],
            );
          },
        ),
      ),
    );
  }
}

String _goalLabel(WorkoutPresetGoal goal) => switch (goal) {
  WorkoutPresetGoal.hypertrophy => 'Hypertrophy',
  WorkoutPresetGoal.strength => 'Strength',
  WorkoutPresetGoal.hybrid => 'Strength + hypertrophy',
};
