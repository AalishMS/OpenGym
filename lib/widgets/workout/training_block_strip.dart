import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/training_block.dart';
import '../../models/training_week.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';

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

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final button =
        _blockButton.currentContext!.findRenderObject()! as RenderBox;
    final anchor =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final media = MediaQuery.of(context);
    final rowHeight = math.max(48.0, media.textScaler.scale(14) + 24);
    final others = widget.blocks.where((b) => b.id != block.id).toList();
    final availableHeight = math.max(0.0, anchor.top - media.padding.top - 16);
    final menuHeight = math.min(
      rowHeight * (others.length + 3) + (others.isEmpty ? 0 : 16),
      availableHeight,
    );
    if (menuHeight == 0) return;
    final menuWidth = math.min(260.0, overlay.size.width - 16);
    PopupMenuItem<VoidCallback> item(String label, VoidCallback action) =>
        PopupMenuItem(
          value: action,
          height: rowHeight,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    setState(() => _menuOpen = true);
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(
        anchor.left,
        anchor.top - menuHeight - 8,
        overlay.size.width - anchor.left - menuWidth,
        overlay.size.height - anchor.top + 8,
      ),
      constraints: BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
        maxHeight: menuHeight,
      ),
      menuPadding: EdgeInsets.zero,
      color: surfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: borderColor(context)),
      ),
      items: [
        for (final other in others)
          item(other.name, () => widget.onSelectBlock(other.id)),
        if (others.isNotEmpty) const PopupMenuDivider(height: 16),
        item('Create block', widget.onCreateBlock),
        item('Rename block', () => widget.onRenameBlock(block.id)),
        item('Reorder blocks', widget.onReorderBlocks),
      ],
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
    final buttonStyle = TextButton.styleFrom(
      minimumSize: Size(48, height),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.control),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: LayoutBuilder(
        builder:
            (context, constraints) => Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(160, constraints.maxWidth * .4),
                  ),
                  child: Tooltip(
                    message: block?.name ?? 'Blocks',
                    child: TextButton(
                      key: _blockButton,
                      onPressed:
                          widget.enabled && block != null
                              ? () => _showBlocks(block)
                              : null,
                      style: buttonStyle,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              block?.name ?? 'Blocks',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textPrimaryColor(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _menuOpen
                                ? LucideIcons.chevronUp
                                : LucideIcons.chevronDown,
                            size: 16,
                            color: textSecondaryColor(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final week in weeks)
                          SizedBox(
                            key:
                                week.id == widget.selectedWeekId
                                    ? _selected
                                    : null,
                            child: Semantics(
                              selected: week.id == widget.selectedWeekId,
                              child: TextButton(
                                key: ValueKey('training-week-${week.id}'),
                                style: buttonStyle,
                                onPressed:
                                    widget.enabled
                                        ? () => widget.onSelectWeek(week.id)
                                        : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration:
                                      week.id == widget.selectedWeekId
                                          ? BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: accentColor(context),
                                                width: 2,
                                              ),
                                            ),
                                          )
                                          : null,
                                  child: Text(
                                    'Week ${week.number}',
                                    style: AppTypography.figures(
                                      color:
                                          week.id == widget.selectedWeekId
                                              ? accentColor(context)
                                              : textSecondaryColor(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip:
                      widget.canAddWeek
                          ? 'Add week'
                          : 'Complete this block to add a week',
                  onPressed:
                      widget.enabled && widget.canAddWeek && block != null
                          ? () => widget.onAddWeek(block.id)
                          : null,
                  constraints: BoxConstraints(minWidth: 48, minHeight: height),
                  icon: const Icon(LucideIcons.plus, size: 20),
                ),
              ],
            ),
      ),
    );
  }
}
