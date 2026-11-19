import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/plan_colors.dart';
import '../../data/workout_presets.dart';
import '../../providers/split_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/breakpoints.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../app_button.dart';
import '../app_header.dart';
import '../motion/app_modals.dart';
import '../motion/collapsible.dart';
import '../motion/page_switcher.dart';
import '../raised_card.dart';
import '../statistics/statistics_controls.dart';

class PresetBrowserDialog extends StatefulWidget {
  final BuildContext hostContext;

  const PresetBrowserDialog({required this.hostContext, super.key});

  static Future<void> show(BuildContext context) => showAppDialog<void>(
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

  void _backToCatalog() {
    if (_installing) return;
    setState(() {
      _selected = null;
      _error = null;
    });
  }

  Future<void> _install(WorkoutPreset preset) async {
    if (_installing) return;
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
    final content = PopScope(
      canPop: !_installing && _selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToCatalog();
      },
      child: _BrowserFrame(
        goal: _goal,
        selected: _selected,
        installing: _installing,
        error: _error,
        onClose: _installing ? null : () => Navigator.pop(context),
        onBack: _backToCatalog,
        onGoalChanged: (goal) => setState(() => _goal = goal),
        onSelect:
            (preset) => setState(() {
              _selected = preset;
              _error = null;
            }),
        onInstall: _install,
      ),
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
        borderRadius: AppRadius.dialog,
        side:
            Theme.of(context).brightness == Brightness.dark
                ? BorderSide(color: hairlineColor(context))
                : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 780),
        child: content,
      ),
    );
  }
}

/// Content never stretches past a comfortable reading width, so the wide
/// dialog centres a column instead of pulling rows across 900px.
const double _readableWidth = 640;

class _BrowserFrame extends StatelessWidget {
  final WorkoutPresetGoal goal;
  final WorkoutPreset? selected;
  final bool installing;
  final String? error;
  final VoidCallback? onClose;
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
        // The dialog already sits inside the safe area, so the header must
        // not reserve room for a status bar a second time.
        MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: AppHeader(
            automaticallyImplyLeading: false,
            leading:
                selected == null
                    ? null
                    : AppBackButton(
                      tooltip: 'Back to workout presets',
                      onPressed: onBack,
                      enabled: !installing,
                    ),
            // Details lead with the program's own name, so the header there
            // only carries navigation.
            title: selected == null ? const Text('Workout presets') : null,
            actions: [
              AppIconButton(
                label: 'Close workout presets',
                icon: LucideIcons.x,
                onPressed: onClose,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ),
        Expanded(
          child: _BrowserPages(
            selected: selected,
            catalog: _CatalogOverview(
              goal: goal,
              onGoalChanged: onGoalChanged,
              onSelect: onSelect,
            ),
            // The install bar belongs to the preset it installs, so it
            // arrives and leaves with the details.
            details:
                (preset) => Column(
                  children: [
                    Expanded(
                      child: _PresetDetails(
                        key: ValueKey(preset.id),
                        preset: preset,
                      ),
                    ),
                    _InstallBar(
                      preset: preset,
                      installing: installing,
                      error: error,
                      onInstall: onInstall,
                    ),
                  ],
                ),
          ),
        ),
      ],
    );
  }
}

/// The catalog and a preset's details trade places as the exercise picker's
/// pages do ([PageSwitchTransition]): the details arrive from the end side as
/// the catalog gives way toward the start, and going back reverses it.
///
/// Both pages stay alive the whole time, as they did in an `IndexedStack`:
/// the catalog keeps its goal and scroll position through a trip into the
/// details and back, and at rest the page that isn't showing is offstage.
/// Each page is built once per change rather than on every frame of it, and
/// each scrolls on its own controller. The arriving page takes taps and is
/// announced from its first frame; the leaving one takes neither and can't
/// hold focus. Under reduced motion the page simply changes.
class _BrowserPages extends StatefulWidget {
  final WorkoutPreset? selected;
  final Widget catalog;
  final Widget Function(WorkoutPreset preset) details;

  const _BrowserPages({
    required this.selected,
    required this.catalog,
    required this.details,
  });

  @override
  State<_BrowserPages> createState() => _BrowserPagesState();
}

class _BrowserPagesState extends State<_BrowserPages>
    with SingleTickerProviderStateMixin {
  // 0 is the catalog, 1 a preset's details.
  late final AnimationController _axis = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
    value: widget.selected == null ? 0 : 1,
  )..addStatusListener(_onStatus);
  late final Animation<double> _catalog = ReverseAnimation(_axis);

  /// The preset whose details show, kept while they leave.
  WorkoutPreset? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.selected;
  }

  void _onStatus(AnimationStatus status) {
    if (!mounted) return;
    // The direction of travel turns with the status; back at the catalog,
    // the details go, as the stack used to let them.
    setState(() {
      if (status.isDismissed) _shown = null;
    });
  }

  @override
  void didUpdateWidget(_BrowserPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != null) _shown = widget.selected;
    if ((widget.selected == null) == (oldWidget.selected == null)) return;
    final details = widget.selected != null;
    if (MediaQuery.disableAnimationsOf(context)) {
      _axis.value = details ? 1 : 0;
      if (!details) _shown = null;
    } else if (details) {
      _axis.forward();
    } else {
      _axis.reverse();
    }
  }

  @override
  void dispose() {
    _axis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    // Which way the pages travel this time; at rest either reads the same.
    final deeper = _axis.status == AnimationStatus.forward;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageSwitchTransition(
          animation: _catalog,
          forward: deeper,
          child: widget.catalog,
        ),
        PageSwitchTransition(
          animation: _axis,
          forward: deeper,
          child:
              shown == null ? const SizedBox.shrink() : widget.details(shown),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        _GoalSelector(selected: goal, onChanged: onGoalChanged),
        const SizedBox(height: AppSpacing.md),
        Text(
          _goalBlurb(goal),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: textSecondaryColor(context),
            height: 1.45,
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

/// Three goals share one segmented track; large text falls back to a
/// scrolling row so no label has to be cut short.
class _GoalSelector extends StatelessWidget {
  final WorkoutPresetGoal selected;
  final ValueChanged<WorkoutPresetGoal> onChanged;

  const _GoalSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return ScrollingPills<WorkoutPresetGoal>(
        values: WorkoutPresetGoal.values,
        selected: selected,
        labelFor: _goalLabel,
        onSelected: onChanged,
        keyPrefix: 'preset-goal',
      );
    }
    // The list stretches its children; aligning lets the track keep its own
    // maximum width in the wide dialog.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SegmentedPills<WorkoutPresetGoal>(
        values: WorkoutPresetGoal.values,
        selected: selected,
        labelFor: _goalLabel,
        semanticLabelFor: _goalName,
        onSelected: onChanged,
        keyPrefix: 'preset-goal',
      ),
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
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);

    return Semantics(
      button: true,
      label:
          '${preset.name}, ${preset.days} days a week, ${preset.duration}, '
          'best for ${preset.bestFit}',
      excludeSemantics: true,
      child: RaisedCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.name,
                          style: textTheme.titleMedium?.copyWith(
                            color: textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          preset.bestFit,
                          style: textTheme.bodySmall?.copyWith(
                            color: textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Row(
                  children: [
                    _RhythmDots(preset: preset),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${preset.days} days',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: '  ·  ${preset.duration}'),
                          ],
                        ),
                        textAlign: TextAlign.end,
                        style: AppTypography.figures(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The catalog's at-a-glance rhythm: a filled square per training day and an
/// empty one per rest day, in the accent alone. Plan colours only mean
/// something once the days they mark are listed, so they wait for details.
class _RhythmDots extends StatelessWidget {
  final WorkoutPreset preset;

  const _RhythmDots({required this.preset});

  @override
  Widget build(BuildContext context) {
    const size = 10.0;
    final slots = preset.scheduleSlots;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < slots.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.xs),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: slots[index] == null ? null : accentColor(context),
              border:
                  slots[index] == null
                      ? Border.all(color: borderColor(context))
                      : null,
              borderRadius: AppRadius.micro,
            ),
          ),
        ],
      ],
    );
  }
}

class _PresetDetails extends StatelessWidget {
  final WorkoutPreset preset;

  const _PresetDetails({required this.preset, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Centring through padding rather than a narrower list keeps the
        // whole dialog scrollable, margins included.
        final side = math.max(
          AppSpacing.lg,
          (constraints.maxWidth - _readableWidth) / 2 + AppSpacing.lg,
        );
        return ListView(
          key: ValueKey('preset-details-${preset.id}'),
          padding: EdgeInsets.fromLTRB(
            side,
            AppSpacing.xl,
            side,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              '${_goalName(preset.goal)} · ${preset.splitStyle}',
              style: textTheme.labelMedium?.copyWith(
                color: accentColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              preset.name,
              style: textTheme.displaySmall?.copyWith(
                color: textPrimaryColor(context),
                fontSize: 26,
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              preset.summary,
              style: textTheme.bodyMedium?.copyWith(
                color: textSecondaryColor(context),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SpecSheet(preset: preset),
            const SizedBox(height: AppSpacing.xxl),
            _SectionTitle(
              title: 'Schedule',
              trailing:
                  preset.scheduleSlots.length == 7
                      ? 'Weekly'
                      : '${preset.scheduleSlots.length}-day rotation',
            ),
            const SizedBox(height: AppSpacing.md),
            _ScheduleStrip(preset: preset),
            const SizedBox(height: AppSpacing.md),
            Text(
              _sentenceCase(preset.schedule),
              style: textTheme.bodySmall?.copyWith(
                color: textSecondaryColor(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _SectionTitle(title: 'Workout days'),
            const SizedBox(height: AppSpacing.md),
            // One grouped panel, with the days as rows inside it.
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: raisedDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < preset.plans.length; index++) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        indent: AppSpacing.md + 40 + AppSpacing.md,
                        color: hairlineColor(context),
                      ),
                    _DayCard(plan: preset.plans[index], number: index + 1),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _SectionTitle(title: 'Before you start'),
            const SizedBox(height: AppSpacing.sm),
            const _Guidance(),
          ],
        );
      },
    );
  }
}

/// Days, session length and size as figures, with who it suits underneath.
class _SpecSheet extends StatelessWidget {
  final WorkoutPreset preset;

  const _SpecSheet({required this.preset});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hairline = hairlineColor(context);
    final exercises = preset.plans.fold<int>(
      0,
      (sum, plan) => sum + plan.exercises.length,
    );
    final minutes =
        preset.duration.endsWith(' min')
            ? preset.duration.substring(0, preset.duration.length - 4)
            : preset.duration;
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final weekly = preset.scheduleSlots.length == 7;
    final stats = [
      _Stat(
        value: '${preset.days}',
        label:
            weekly
                ? 'days a week'
                : 'of every ${preset.scheduleSlots.length} days',
        semanticLabel:
            weekly
                ? '${preset.days} days a week'
                : '${preset.days} of every ${preset.scheduleSlots.length} days',
        inline: stacked,
      ),
      _Stat(
        value: minutes,
        label: 'min a session',
        semanticLabel: '${preset.duration} a session',
        inline: stacked,
      ),
      _Stat(
        value: '$exercises',
        label: 'exercises',
        semanticLabel: '$exercises exercises in total',
        inline: stacked,
      ),
    ];
    return DecoratedBox(
      decoration: raisedDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Large text reads the figures as rows, so no range is cut short.
          if (stacked)
            for (var index = 0; index < stats.length; index++)
              Container(
                decoration:
                    index == 0
                        ? null
                        : BoxDecoration(
                          border: Border(top: BorderSide(color: hairline)),
                        ),
                child: stats[index],
              )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < stats.length; index++) ...[
                    if (index > 0)
                      SizedBox(width: 1, child: ColoredBox(color: hairline)),
                    Expanded(child: stats[index]),
                  ],
                ],
              ),
            ),
          for (final fact in [
            ('Best for  ', preset.bestFit),
            ('Starts with  ', '${preset.blockWeeks}-week block'),
          ])
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: hairline)),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: fact.$1),
                    TextSpan(
                      text: fact.$2,
                      style: TextStyle(
                        color: textPrimaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                style: textTheme.bodySmall?.copyWith(
                  color: textSecondaryColor(context),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final String semanticLabel;

  /// Figure and label side by side, for the stacked large-text layout.
  final bool inline;

  const _Stat({
    required this.value,
    required this.label,
    required this.semanticLabel,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final figure = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.figures(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: textPrimaryColor(context),
      ),
    );
    final caption = Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: textSecondaryColor(context)),
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: inline ? AppSpacing.lg : AppSpacing.md,
          vertical: inline ? AppSpacing.md : AppSpacing.lg,
        ),
        child:
            inline
                ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    figure,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: caption),
                  ],
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    figure,
                    const SizedBox(height: AppSpacing.xxs),
                    caption,
                  ],
                ),
      ),
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
            style: textTheme.titleLarge?.copyWith(
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

/// One cell per day of the rotation, labelled with its weekday (or its
/// position in a longer rotation). Training days carry the number and colour
/// of the workout day they run, matching the list below and Home's markers.
class _ScheduleStrip extends StatelessWidget {
  final WorkoutPreset preset;

  const _ScheduleStrip({required this.preset});

  static const List<String> _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final slots = preset.scheduleSlots;
    final weekly = slots.length == _weekdays.length;
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
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Expanded(
              // A rotation has no weekdays to name, and position numbers
              // would compete with the workout numbers in the cells.
              child:
                  weekly
                      ? Column(
                        children: [
                          _ScheduleCell(preset: preset, slotIndex: index),
                          const SizedBox(
                            height: AppSpacing.xs + AppSpacing.xxs,
                          ),
                          Text(
                            _weekdays[index],
                            style: AppTypography.figures(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ],
                      )
                      : _ScheduleCell(preset: preset, slotIndex: index),
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

  const _ScheduleCell({required this.preset, required this.slotIndex});

  @override
  Widget build(BuildContext context) {
    final planIndex = preset.scheduleSlots[slotIndex];
    final label =
        planIndex == null
            ? 'Day ${slotIndex + 1}: Rest'
            : 'Day ${slotIndex + 1}: ${preset.plans[planIndex].name}';
    if (planIndex == null) {
      return Tooltip(
        message: label,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: controlFillColor(context),
            borderRadius: AppRadius.button,
          ),
          child: Container(
            width: 6,
            height: 2,
            decoration: BoxDecoration(
              color: borderColor(context),
              borderRadius: AppRadius.micro,
            ),
          ),
        ),
      );
    }
    final planColor = _planColor(preset.plans[planIndex], context);
    final ground = _planWash(planColor, context);
    return Tooltip(
      message: label,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ground,
          border: Border(bottom: BorderSide(color: planColor, width: 3)),
          borderRadius: AppRadius.button,
        ),
        child: Text(
          '${planIndex + 1}',
          style: AppTypography.figures(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: onColor(ground),
          ),
        ),
      ),
    );
  }
}

/// A workout day that folds open to its exercises. Days start folded so the
/// list reads as the program's shape first.
class _DayCard extends StatefulWidget {
  final WorkoutPresetPlan plan;
  final int number;

  const _DayCard({required this.plan, required this.number});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final plan = widget.plan;
    final planColor = _planColor(plan, context);
    final ground = _planWash(planColor, context);
    final sets = plan.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.seedReps.length,
    );
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ground,
                        borderRadius: AppRadius.button,
                      ),
                      child: Text(
                        '${widget.number}',
                        style: AppTypography.figures(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: onColor(ground),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            style: textTheme.titleMedium?.copyWith(
                              color: textPrimaryColor(context),
                            ),
                          ),
                          Text(
                            '${plan.exercises.length} exercises · $sets sets',
                            style: textTheme.bodySmall?.copyWith(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: AppMotion.of(context, AppMotion.quick),
                      curve: AppMotion.curve,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 20,
                        color: textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The exercises fold open and away, and leave the tree once
          // folded, so a closed day holds nothing for a screen reader.
          Collapsible(
            open: _expanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final exercise in plan.exercises)
                  _ExercisePrescription(exercise: exercise),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExercisePrescription extends StatelessWidget {
  final WorkoutPresetExercise exercise;

  const _ExercisePrescription({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final detailStyle = textTheme.bodySmall?.copyWith(
      color: textSecondary,
      height: 1.4,
    );

    // Rules are inset to the text, so the rows read as one list rather than
    // a stack of boxes.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: hairlineColor(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
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
                const SizedBox(width: AppSpacing.md),
                Text(
                  _range(exercise.prescription.replaceAll(' x ', ' × ')),
                  style: AppTypography.figures(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Rest ${_range(exercise.rest)} · ${_range(exercise.rir)} reps in reserve',
              style: detailStyle,
            ),
            if (exercise.note != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                exercise.note!,
                style: detailStyle?.copyWith(color: accentColor(context)),
              ),
            ],
            if (exercise.substitutions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Or swap for ${_listPhrase(exercise.substitutions)}',
                style: detailStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// General lifting advice is the same for every preset, so it sits last as a
/// short numbered list rather than another card.
class _Guidance extends StatelessWidget {
  const _Guidance();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < workoutPresetGuidance.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration:
                index == 0
                    ? null
                    : BoxDecoration(
                      border: Border(
                        top: BorderSide(color: hairlineColor(context)),
                      ),
                    ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: AppSpacing.xl,
                  child: Text(
                    '${index + 1}',
                    style: AppTypography.figures(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accentColor(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    workoutPresetGuidance[index],
                    style: textTheme.bodyMedium?.copyWith(
                      color: textPrimaryColor(context),
                      height: 1.4,
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
    final problem = error ?? blockReason;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(top: BorderSide(color: hairlineColor(context))),
      ),
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _readableWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (problem != null) ...[
                  Text(
                    problem,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: errorColor(context)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                AppButton.primary(
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
                ),
                if (problem == null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Adds ${preset.days} workout plans you can edit',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textSecondaryColor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _planColor(WorkoutPresetPlan plan, BuildContext context) =>
    planColorOf(kPlanColors[plan.colorSlot], context);

/// The same opaque plan tint Home uses behind its plan markers.
Color _planWash(Color planColor, BuildContext context) =>
    Color.alphaBlend(planColor.withAlpha(40), surfaceColor(context));

/// Rules inside and around cards are a step quieter than the theme border,
/// which is solved to stand out as a control edge.
/// Numeric ranges read with an en dash: `6-10` becomes `6–10`.
String _range(String text) => text.replaceAll('-', '–');

String _listPhrase(List<String> items) =>
    items.length < 2
        ? items.join()
        : '${items.sublist(0, items.length - 1).join(', ')} or ${items.last}';

String _sentenceCase(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String _goalLabel(WorkoutPresetGoal goal) => switch (goal) {
  WorkoutPresetGoal.hypertrophy => 'Hypertrophy',
  WorkoutPresetGoal.strength => 'Strength',
  WorkoutPresetGoal.hybrid => 'Hybrid',
};

String _goalName(WorkoutPresetGoal goal) => switch (goal) {
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
