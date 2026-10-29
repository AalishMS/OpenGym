import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/training_block.dart';
import '../../models/training_week.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// `4 weeks` for a block's intended length, falling back to the weeks this
/// workout can see when a migrated block has no stored length.
String trainingBlockLengthLabel(TrainingBlock block, List<TrainingWeek> weeks) {
  final count = block.plannedWeekCount ?? weeks.length;
  return count == 1 ? '1 week' : '$count weeks';
}

/// The screen owns selection; only the week list scrolls between fixed controls.
class TrainingBlockStrip extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Map<String, List<TrainingWeek>> weeksByBlock;
  final String? selectedWeekId;
  final ValueChanged<String> onSelectWeek;
  final ValueChanged<String> onSelectBlock;
  final ValueChanged<String> onRenameBlock;
  final VoidCallback onReorderBlocks;
  final VoidCallback onCreateBlock;
  final ValueChanged<String> onAddWeek;
  final bool enabled;
  final bool canAddWeek;

  const TrainingBlockStrip({
    super.key,
    required this.blocks,
    required this.weeksByBlock,
    required this.selectedWeekId,
    required this.onSelectWeek,
    required this.onSelectBlock,
    required this.onRenameBlock,
    required this.onReorderBlocks,
    required this.onCreateBlock,
    required this.onAddWeek,
    this.enabled = true,
    this.canAddWeek = true,
  });

  @override
  State<TrainingBlockStrip> createState() => _TrainingBlockStripState();
}

class _TrainingBlockStripState extends State<TrainingBlockStrip> {
  final _scroll = ScrollController();
  final _selected = GlobalKey();
  final _blockButton = GlobalKey();
  bool _menuOpen = false;
  bool _fadeStart = false;
  bool _fadeEnd = false;

  TrainingBlock? get _block =>
      widget.blocks
          .where(
            (block) =>
                widget.weeksByBlock[block.id]?.any(
                  (week) => week.id == widget.selectedWeekId,
                ) ??
                false,
          )
          .firstOrNull ??
      widget.blocks.firstOrNull;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateFades);
    _reveal();
  }

  @override
  void didUpdateWidget(covariant TrainingBlockStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedWeekId != widget.selectedWeekId ||
        oldWidget.blocks != widget.blocks ||
        oldWidget.weeksByBlock != widget.weeksByBlock) {
      _reveal();
    }
  }

  /// Fades only the edge that hides more weeks, so a short block reads as a
  /// complete row and a long one hints that it scrolls.
  void _updateFades() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final start = position.pixels > position.minScrollExtent + 1;
    final end = position.pixels < position.maxScrollExtent - 1;
    if (start != _fadeStart || end != _fadeEnd) {
      setState(() {
        _fadeStart = start;
        _fadeEnd = end;
      });
    }
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateFades();
      final selected = _selected.currentContext;
      if (selected != null) {
        Scrollable.ensureVisible(
          selected,
          alignment: .65,
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
        );
      }
    });
  }

  Future<void> _showBlocks(TrainingBlock block) async {
    if (_menuOpen || !widget.enabled) return;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final button =
        _blockButton.currentContext!.findRenderObject()! as RenderBox;
    final anchor =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final media = MediaQuery.of(context);
    final maxHeight = anchor.top - media.padding.top - AppSpacing.lg;
    if (maxHeight < 48) return;
    setState(() => _menuOpen = true);
    final action = await navigator.push<VoidCallback>(
      _BlockMenuRoute(
        anchor: anchor,
        media: media,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        menu: _BlockMenu(
          blocks: widget.blocks,
          weeksByBlock: widget.weeksByBlock,
          currentId: block.id,
          onSelectBlock: widget.onSelectBlock,
          onCreateBlock: widget.onCreateBlock,
          onRenameBlock: () => widget.onRenameBlock(block.id),
          onReorderBlocks: widget.onReorderBlocks,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (widget.enabled) action?.call();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = math.max(
      56.0,
      MediaQuery.textScalerOf(context).scale(14) + 28,
    );
    final block = _block;
    final weeks = widget.weeksByBlock[block?.id] ?? <TrainingWeek>[];
    final canAdd = widget.enabled && widget.canAddWeek && block != null;
    // A Material, not a plain DecoratedBox: the tabs' ink needs a surface of
    // its own, or splashes paint behind the bar's opaque ground.
    return Material(
      color: backgroundColor(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor(context))),
        ),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder:
                (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.min(168, constraints.maxWidth * .42),
                          ),
                          child: _BlockButton(
                            key: _blockButton,
                            name: block?.name ?? 'Blocks',
                            open: _menuOpen,
                            onPressed:
                                widget.enabled && block != null
                                    ? () => _showBlocks(block)
                                    : null,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          final ramp = (24 / bounds.width).clamp(0.0, 0.4);
                          return LinearGradient(
                            // dstIn reads alpha only — these are mask stops,
                            // not UI colours, so opaque/transparent is all
                            // that black and white mean here.
                            colors: const [
                              Colors.transparent,
                              Colors.black,
                              Colors.black,
                              Colors.transparent,
                            ],
                            stops: [
                              0,
                              _fadeStart ? ramp : 0,
                              _fadeEnd ? 1 - ramp : 1,
                              1,
                            ],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: NotificationListener<ScrollMetricsNotification>(
                          onNotification: (_) {
                            _updateFades();
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: _scroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final week in weeks)
                                  _WeekTab(
                                    key:
                                        week.id == widget.selectedWeekId
                                            ? _selected
                                            : null,
                                    buttonKey: ValueKey(
                                      'training-week-${week.id}',
                                    ),
                                    number: week.number,
                                    selected: week.id == widget.selectedWeekId,
                                    onPressed:
                                        widget.enabled
                                            ? () => widget.onSelectWeek(week.id)
                                            : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Center(
                        child: IconButton(
                          tooltip:
                              widget.canAddWeek
                                  ? 'Add week'
                                  : 'Complete this block to add a week',
                          onPressed:
                              canAdd ? () => widget.onAddWeek(block.id) : null,
                          // Once the block's last week is done, the plus is
                          // the next step, so it gains a ground to say so.
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(40),
                            minimumSize: const Size.square(40),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.control,
                            ),
                            backgroundColor:
                                canAdd ? accentFillColor(context) : null,
                            foregroundColor:
                                canAdd ? onAccentColor(context) : null,
                          ),
                          icon: const Icon(LucideIcons.plus, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

/// The selected block's name on a quiet ground: a ground means tappable, and
/// this opens the block menu above it.
class _BlockButton extends StatelessWidget {
  final String name;
  final bool open;
  final VoidCallback? onPressed;

  const _BlockButton({
    super.key,
    required this.name,
    required this.open,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    return Semantics(
      button: true,
      expanded: open,
      hint: 'Opens the block menu',
      child: Tooltip(
        message: name,
        child: Material(
          color: open ? accentMutedColor(context) : surfaceColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.control,
            side: BorderSide(color: borderColor(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            splashColor: accent.withAlpha(36),
            highlightColor: accent.withAlpha(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.layers,
                      size: 16,
                      color: enabled ? accent : textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              enabled
                                  ? textPrimaryColor(context)
                                  : textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // Points the way the menu opens, then flips to close it.
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration:
                          MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                      child: Icon(
                        LucideIcons.chevronUp,
                        size: 14,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A week label underlined like the plan tabs above the workout, so the two
/// strips that frame the log speak the same language.
class _WeekTab extends StatelessWidget {
  final Key buttonKey;
  final int number;
  final bool selected;
  final VoidCallback? onPressed;

  const _WeekTab({
    super.key,
    required this.buttonKey,
    required this.number,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    return Semantics(
      selected: selected,
      child: InkWell(
        key: buttonKey,
        onTap: onPressed,
        borderRadius: AppRadius.control,
        splashColor: accent.withAlpha(36),
        highlightColor: accent.withAlpha(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              child: AnimatedContainer(
                duration:
                    MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                // Top padding matches the underline's depth, so the label
                // shares a centre line with the block button beside it.
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  'Week $number',
                  style: AppTypography.figures(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? accent : textSecondaryColor(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anchors the block menu above its button. A route rather than an overlay
/// entry, so Back and an outside tap close it like any other menu.
class _BlockMenuRoute extends PopupRoute<VoidCallback> {
  final Rect anchor;
  final MediaQueryData media;
  final CapturedThemes themes;
  final Widget menu;

  _BlockMenuRoute({
    required this.anchor,
    required this.media,
    required this.themes,
    required this.menu,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Close block menu';

  @override
  Duration get transitionDuration =>
      media.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration =>
      media.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => MediaQuery(
    data: media,
    child: themes.wrap(
      CustomSingleChildLayout(
        delegate: _BlockMenuLayout(anchor: anchor, padding: media.padding),
        child: menu,
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        // Grows out of the block button, which sits under its left edge.
        alignment: Alignment.bottomLeft,
        scale: Tween<double>(begin: .94, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

class _BlockMenuLayout extends SingleChildLayoutDelegate {
  static const double _gap = AppSpacing.sm;
  final Rect anchor;
  final EdgeInsets padding;

  const _BlockMenuLayout({required this.anchor, required this.padding});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.min(292.0, constraints.maxWidth - AppSpacing.lg);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0, anchor.top - _gap - padding.top - AppSpacing.sm),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left =
        anchor.left
            .clamp(
              AppSpacing.sm,
              math.max(
                AppSpacing.sm,
                size.width - childSize.width - AppSpacing.sm,
              ),
            )
            .toDouble();
    return Offset(left, anchor.top - _gap - childSize.height);
  }

  @override
  bool shouldRelayout(_BlockMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}

/// Blocks to pick from, then the commands under a rule — the same shape as the
/// split switcher on Home, so both "which workspace am I in" menus match.
class _BlockMenu extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Map<String, List<TrainingWeek>> weeksByBlock;
  final String currentId;
  final ValueChanged<String> onSelectBlock;
  final VoidCallback onCreateBlock;
  final VoidCallback onRenameBlock;
  final VoidCallback onReorderBlocks;

  const _BlockMenu({
    required this.blocks,
    required this.weeksByBlock,
    required this.currentId,
    required this.onSelectBlock,
    required this.onCreateBlock,
    required this.onRenameBlock,
    required this.onReorderBlocks,
  });

  @override
  State<_BlockMenu> createState() => _BlockMenuState();
}

class _BlockMenuState extends State<_BlockMenu> {
  final _current = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = _current.currentContext;
      if (mounted && current != null) {
        Scrollable.ensureVisible(current, alignment: .5);
      }
    });
  }

  void _close(VoidCallback? action) => Navigator.pop(context, action);

  @override
  Widget build(BuildContext context) {
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final scaler = MediaQuery.textScalerOf(context);
    final count = widget.blocks.length;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Training blocks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              count == 1 ? '1 block' : '$count blocks',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: textSecondary),
            ),
          ),
        ],
      ),
    );
    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in widget.blocks)
          _BlockMenuRow(
            key: block.id == widget.currentId ? _current : null,
            name: block.name,
            caption: trainingBlockLengthLabel(
              block,
              widget.weeksByBlock[block.id] ?? const [],
            ),
            selected: block.id == widget.currentId,
            onTap:
                () => _close(
                  block.id == widget.currentId
                      ? null
                      : () => widget.onSelectBlock(block.id),
                ),
          ),
      ],
    );
    final actions = [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Divider(height: 1, thickness: 1, color: border),
      ),
      _BlockMenuAction(
        icon: LucideIcons.plus,
        label: 'Create block',
        onTap: () => _close(widget.onCreateBlock),
      ),
      _BlockMenuAction(
        icon: LucideIcons.pencilLine,
        label: 'Rename block',
        onTap: () => _close(widget.onRenameBlock),
      ),
      _BlockMenuAction(
        icon: LucideIcons.arrowUpDown,
        label: 'Reorder blocks',
        caption: count < 2 ? 'Needs 2 blocks' : null,
        onTap: count < 2 ? null : () => _close(widget.onReorderBlocks),
      ),
    ];

    return Material(
      color: surfaceColor(context),
      elevation: 8,
      shadowColor: backgroundColor(context).withAlpha(128),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The commands stay pinned below a scrolling block list while at
          // least one block row still fits; past that, everything scrolls.
          // Heights assume a generous 1.6 line height so the estimate errs
          // towards scrolling rather than overflowing.
          double line(double size) => scaler.scale(size) * 1.6;
          final row = math.max(48.0, line(14) + line(12) + AppSpacing.lg);
          final action = math.max(48.0, line(14));
          final pinned =
              AppSpacing.sm * 2 +
              line(12) +
              AppSpacing.sm +
              AppSpacing.sm * 2 +
              1 +
              action * 3 +
              row;
          final content =
              constraints.maxHeight >= pinned
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Flexible(child: SingleChildScrollView(child: rows)),
                      ...actions,
                    ],
                  )
                  : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [header, rows, ...actions],
                    ),
                  );
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: content,
          );
        },
      ),
    );
  }
}

class _BlockMenuRow extends StatelessWidget {
  final String name;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  const _BlockMenuRow({
    super.key,
    required this.name,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? accentMutedColor(context) : null,
          borderRadius: AppRadius.control,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.control,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              // Radio-style leading mark: the blocks read as "pick one of
              // these", unlike the icon-led commands under the rule.
              child: Row(
                children: [
                  Icon(
                    selected ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 18,
                    color: selected ? accent : textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: textPrimaryColor(context),
                          ),
                        ),
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Secondary grey is too faint on the selected
                          // row's accent wash, so it takes the primary ink.
                          style: AppTypography.figures(
                            fontSize: 12,
                            color:
                                selected
                                    ? textPrimaryColor(context)
                                    : textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A command row under the block list: accent icon plus a one-line label.
class _BlockMenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;

  const _BlockMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final textSecondary = textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.control,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? accentColor(context) : textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: enabled ? textPrimaryColor(context) : textSecondary,
                  ),
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
