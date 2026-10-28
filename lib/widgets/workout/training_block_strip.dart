import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/training_block.dart';
import '../../models/training_week.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';

/// Stateless selection contract: the screen owns expansion and destination.
/// The only local state is scroll position and the selected item's anchor.
class TrainingBlockStrip extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Map<String, List<TrainingWeek>> weeksByBlock;
  final String? selectedWeekId;
  final String? expandedBlockId;
  final ValueChanged<String> onSelectWeek;
  final ValueChanged<String> onExpandBlock;
  final ValueChanged<String> onManageBlock;
  final VoidCallback onCreateBlock;
  final bool enabled;

  const TrainingBlockStrip({
    super.key,
    required this.blocks,
    required this.weeksByBlock,
    required this.selectedWeekId,
    required this.expandedBlockId,
    required this.onSelectWeek,
    required this.onExpandBlock,
    required this.onManageBlock,
    required this.onCreateBlock,
    this.enabled = true,
  });

  @override
  State<TrainingBlockStrip> createState() => _TrainingBlockStripState();
}

class _TrainingBlockStripState extends State<TrainingBlockStrip> {
  final _scroll = ScrollController();
  final _selected = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant TrainingBlockStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedWeekId != widget.selectedWeekId ||
        oldWidget.expandedBlockId != widget.expandedBlockId) {
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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _inlineRegion({
    required Duration duration,
    required Alignment alignment,
    required Widget child,
  }) =>
      duration == Duration.zero
          ? child
          : AnimatedSize(
            duration: duration,
            alignment: alignment,
            child: child,
          );

  @override
  Widget build(BuildContext context) {
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180);
    final height = math.max(
      56.0,
      MediaQuery.textScalerOf(context).scale(14) + 28,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
      ),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final block in widget.blocks)
              _inlineRegion(
                duration: duration,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed:
                          widget.enabled
                              ? () => widget.onExpandBlock(block.id)
                              : null,
                      onLongPress:
                          widget.enabled
                              ? () => widget.onManageBlock(block.id)
                              : null,
                      style: TextButton.styleFrom(
                        minimumSize: Size(48, height),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.control,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              block.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textPrimaryColor(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            widget.expandedBlockId == block.id
                                ? LucideIcons.chevronDown
                                : LucideIcons.chevronRight,
                            size: 16,
                            color: textSecondaryColor(context),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Block actions for ${block.name}',
                      constraints: BoxConstraints(
                        minWidth: 48,
                        minHeight: height,
                      ),
                      onPressed:
                          widget.enabled
                              ? () => widget.onManageBlock(block.id)
                              : null,
                      icon: const Icon(LucideIcons.ellipsis, size: 18),
                    ),
                    if (widget.expandedBlockId == block.id)
                      for (final week
                          in widget.weeksByBlock[block.id] ?? <TrainingWeek>[])
                        SizedBox(
                          key:
                              week.id == widget.selectedWeekId
                                  ? _selected
                                  : null,
                          child: Semantics(
                            selected: week.id == widget.selectedWeekId,
                            child: TextButton(
                              key: ValueKey('training-week-${week.id}'),
                              style: TextButton.styleFrom(
                                minimumSize: Size(48, height),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: AppRadius.control,
                                ),
                              ),
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
            IconButton(
              tooltip: 'Create block',
              onPressed: widget.enabled ? widget.onCreateBlock : null,
              constraints: BoxConstraints(minWidth: 48, minHeight: height),
              icon: const Icon(LucideIcons.plus, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
