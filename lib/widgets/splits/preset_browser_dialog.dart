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
  // Lives here rather than in the catalog so the chosen goal survives a trip
  // into a preset's details and back.
  WorkoutPresetGoal _goal = WorkoutPresetGoal.hypertrophy;
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
      goal: _goal,
      selected: _selected,
      installing: _installing,
      error: _error,
      onClose: () => Navigator.pop(context),
      onBack:
          () => setState(() {
            _selected = null;
            _error = null;
          }),
      onGoalChanged: (goal) => setState(() => _goal = goal),
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
  final WorkoutPresetGoal goal;
  final WorkoutPreset? selected;
  final bool installing;
  final String? error;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final ValueChanged<WorkoutPresetGoal> onGoalChanged;
  final ValueChanged<WorkoutPreset> onSelect;
  final ValueChanged<WorkoutPreset> onInstall;

  const _BrowserFrame({
    required this.goal,
    required this.selected,
    required this.installing,
    required this.error,
    required this.onClose,
    required this.onBack,
    required this.onGoalChanged,
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
                  ? _CatalogOverview(
                    goal: goal,
                    onGoalChanged: onGoalChanged,
                    onSelect: onSelect,
                  )
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
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                  if (preset == null)
                    Text(
                      'Pick one, then edit it to suit you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
  final WorkoutPresetGoal goal;
  final ValueChanged<WorkoutPresetGoal> onGoalChanged;
  final ValueChanged<WorkoutPreset> onSelect;

  const _CatalogOverview({
    required this.goal,
    required this.onGoalChanged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final presets =
        workoutPresets.where((preset) => preset.goal == goal).toList();
    return ListView(
      key: const ValueKey('preset-catalog'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _GoalFilter(selected: goal, onChanged: onGoalChanged),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _goalBlurb(goal),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: textSecondaryColor(context),
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 720 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.3
                    ? 2
                    : 1;
            return Column(
              children: [
                for (var row = 0; row < presets.length; row += columns) ...[
                  if (row > 0) const SizedBox(height: AppSpacing.md),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < columns; col++) ...[
                          if (col > 0) const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child:
                                row + col < presets.length
                                    ? _PresetCard(
                                      preset: presets[row + col],
                                      onTap: () => onSelect(presets[row + col]),
                                    )
                                    : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GoalFilter extends StatelessWidget {
  final WorkoutPresetGoal selected;
  final ValueChanged<WorkoutPresetGoal> onChanged;

  const _GoalFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final goal in WorkoutPresetGoal.values)
          ChoiceChip(
            label: Text(_goalLabel(goal)),
            selected: goal == selected,
            showCheckmark: false,
            onSelected: (_) => onChanged(goal),
            labelStyle: labelStyle?.copyWith(
              color:
                  goal == selected
                      ? onAccentColor(context)
                      : textPrimaryColor(context),
            ),
            side: BorderSide(
              color:
                  goal == selected
                      ? accentFillColor(context)
                      : borderColor(context),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
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
    final textTheme = Theme.of(context).textTheme;
    final textSecondary = textSecondaryColor(context);

    return Semantics(
      button: true,
      label:
          '${preset.name}, ${preset.days} days a week, ${preset.duration}, '
          'best for ${preset.bestFit}',
      excludeSemantics: true,
      child: Material(
        color: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: borderColor(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.name,
                        style: textTheme.titleSmall?.copyWith(
                          color: textPrimaryColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _DaysBadge(days: preset.days),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${preset.duration} · ${preset.bestFit}',
                  style: textTheme.bodySmall?.copyWith(color: textSecondary),
                ),
                const Spacer(),
                const SizedBox(height: AppSpacing.md),
                _ScheduleStrip(preset: preset),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DaysBadge extends StatelessWidget {
  final int days;

  const _DaysBadge({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.chip,
      ),
      child: Text(
        '$days days',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accentColor(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One cell per day of the rotation: a plan's colour on training days, a
/// border-coloured cell on rest days. [numbered] makes the cells tall enough
/// to carry the plan's number, matching the badges in the workout day list.
class _ScheduleStrip extends StatelessWidget {
  final WorkoutPreset preset;
  final bool numbered;

  const _ScheduleStrip({required this.preset, this.numbered = false});

  @override
  Widget build(BuildContext context) {
    final slots = preset.scheduleSlots;
    final description = [
      for (var index = 0; index < slots.length; index++)
        'Day ${index + 1} '
            '${slots[index] == null ? 'rest' : preset.plans[slots[index]!].name}',
    ].join(', ');
    return Semantics(
      label: '${slots.length}-day rotation: $description',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var index = 0; index < slots.length; index++) ...[
            if (index > 0)
              SizedBox(width: numbered ? AppSpacing.xs : AppSpacing.xxs),
            Expanded(
              child: _ScheduleCell(
                preset: preset,
                slotIndex: index,
                numbered: numbered,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleCell extends StatelessWidget {
  final WorkoutPreset preset;
  final int slotIndex;
  final bool numbered;

  const _ScheduleCell({
    required this.preset,
    required this.slotIndex,
    required this.numbered,
  });

  @override
  Widget build(BuildContext context) {
    final planIndex = preset.scheduleSlots[slotIndex];
    final ground =
        planIndex == null
            ? borderColor(context)
            : _planColor(preset.plans[planIndex], context);
    if (!numbered) {
      return Container(
        height: 6,
        decoration: BoxDecoration(color: ground, borderRadius: AppRadius.micro),
      );
    }
    return Tooltip(
      message:
          planIndex == null
              ? 'Day ${slotIndex + 1}: Rest'
              : 'Day ${slotIndex + 1}: ${preset.plans[planIndex].name}',
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: ground, borderRadius: AppRadius.badge),
        child:
            planIndex == null
                ? null
                : Text(
                  '${planIndex + 1}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: onColor(ground),
                    fontWeight: FontWeight.w700,
                  ),
                ),
      ),
    );
  }
}

class _PresetDetails extends StatelessWidget {
  final WorkoutPreset preset;

  const _PresetDetails({required this.preset});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    return ListView(
      key: ValueKey('preset-details-${preset.id}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          preset.summary,
          style: textTheme.bodyLarge?.copyWith(color: textPrimary, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _InfoChip(
              icon: LucideIcons.calendar,
              label: '${preset.days} days a week',
            ),
            _InfoChip(icon: LucideIcons.clock, label: preset.duration),
            _InfoChip(icon: LucideIcons.userCheck, label: preset.bestFit),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionTitle(
          title: 'Schedule',
          trailing: '${preset.scheduleSlots.length}-day rotation',
        ),
        const SizedBox(height: AppSpacing.sm),
        _ScheduleStrip(preset: preset, numbered: true),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _sentenceCase(preset.schedule),
          style: textTheme.bodySmall?.copyWith(
            color: textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle(title: 'Workout days'),
        const SizedBox(height: AppSpacing.sm),
        for (var index = 0; index < preset.plans.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          _PlanExpansion(plan: preset.plans[index], number: index + 1),
        ],
        const SizedBox(height: AppSpacing.xl),
        const _TipsPanel(),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              color: textPrimaryColor(context),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: textTheme.bodySmall?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xxs,
        vertical: AppSpacing.xs + AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accentColor(context)),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
  final int number;

  const _PlanExpansion({required this.plan, required this.number});

  @override
  Widget build(BuildContext context) {
    final planColor = _planColor(plan, context);
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
          AppSpacing.sm,
        ),
        leading: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: planColor,
            borderRadius: AppRadius.badge,
          ),
          child: Text(
            '$number',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: onColor(planColor),
              fontWeight: FontWeight.w700,
            ),
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
    final textTheme = Theme.of(context).textTheme;
    final accent = accentColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration:
          showDivider
              ? BoxDecoration(
                border: Border(top: BorderSide(color: borderColor(context))),
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
                  style: textTheme.bodyMedium?.copyWith(
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                exercise.prescription.replaceAll(' x ', ' × '),
                style: textTheme.bodyMedium?.copyWith(
                  color: textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Rest ${exercise.rest} · ${exercise.rir} reps in reserve',
            style: textTheme.bodySmall?.copyWith(color: textSecondary),
          ),
          if (exercise.note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _DetailLine(
              icon: LucideIcons.info,
              iconColor: accent,
              text: exercise.note!,
              textColor: accent,
            ),
          ],
          if (exercise.substitutions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _DetailLine(
              icon: LucideIcons.shuffle,
              iconColor: textSecondary,
              text: 'Or swap for ${exercise.substitutions.join(', ')}',
              textColor: textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color textColor;

  const _DetailLine({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 13, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: textColor, height: 1.35),
          ),
        ),
      ],
    );
  }
}

/// General lifting advice is the same for every preset, so it starts folded
/// away instead of competing with the preset's own details.
class _TipsPanel extends StatelessWidget {
  const _TipsPanel();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
        leading: Icon(
          LucideIcons.lightbulb,
          size: 18,
          color: accentColor(context),
        ),
        title: Text(
          'Tips before you start',
          style: textTheme.titleSmall?.copyWith(
            color: textPrimaryColor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          for (final guidance in workoutPresetGuidance)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: accentColor(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      guidance,
                      style: textTheme.bodySmall?.copyWith(
                        color: textSecondaryColor(context),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                  'Adds ${preset.days} workout plans you can edit',
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

Color _planColor(WorkoutPresetPlan plan, BuildContext context) =>
    planColorOf(kPlanColors[plan.colorSlot], context);

String _sentenceCase(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String _goalLabel(WorkoutPresetGoal goal) => switch (goal) {
  WorkoutPresetGoal.hypertrophy => 'Hypertrophy',
  WorkoutPresetGoal.strength => 'Strength',
  WorkoutPresetGoal.hybrid => 'Strength + hypertrophy',
};

String _goalBlurb(WorkoutPresetGoal goal) => switch (goal) {
  WorkoutPresetGoal.hypertrophy =>
    'Build muscle size with moderate weights and more reps.',
  WorkoutPresetGoal.strength =>
    'Lift heavier on the main lifts with fewer reps and longer rests.',
  WorkoutPresetGoal.hybrid =>
    'Heavy lifting and muscle building in the same week.',
};
