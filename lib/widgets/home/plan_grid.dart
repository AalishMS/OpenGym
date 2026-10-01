import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/workout_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../utils/format.dart';
import '../../utils/plan_stats.dart';
import 'plan_card.dart';

/// Keeps cards in one keyed child list, including moves across grid rows.
/// Row heights follow the content so larger text still has room to grow.
class PlanGrid extends StatefulWidget {
  final List<WorkoutPlan> plans;
  final Map<int, PlanStat> stats;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onShowActions;
  final void Function(String fromId, String toId) onMove;

  const PlanGrid({
    required this.plans,
    required this.stats,
    required this.onOpen,
    required this.onShowActions,
    required this.onMove,
    super.key,
  });

  @override
  State<PlanGrid> createState() => _PlanGridState();
}

class _PlanGridState extends State<PlanGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _motion.value = 1;
  }

  @override
  void didUpdateWidget(PlanGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.plans.map((plan) => plan.id).toList();
    final after = widget.plans.map((plan) => plan.id).toList();
    if (!listEquals(before, after) &&
        setEquals(before.toSet(), after.toSet())) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PlanGridLayout(
      motion: _motion,
      textDirection: Directionality.of(context),
      children: [
        for (var index = 0; index < widget.plans.length; index++)
          _DraggablePlanCard(
            key: ValueKey(widget.plans[index].id),
            plan: widget.plans[index],
            index: index,
            stat: widget.stats[index],
            canDrag: widget.plans.length > 1,
            onOpen: () => widget.onOpen(index),
            onShowActions: () => widget.onShowActions(index),
            onMove: widget.onMove,
          ),
      ],
    );
  }
}

class _DraggablePlanCard extends StatefulWidget {
  final WorkoutPlan plan;
  final int index;
  final PlanStat? stat;
  final bool canDrag;
  final VoidCallback onOpen;
  final VoidCallback onShowActions;
  final void Function(String fromId, String toId) onMove;

  const _DraggablePlanCard({
    required this.plan,
    required this.index,
    required this.stat,
    required this.canDrag,
    required this.onOpen,
    required this.onShowActions,
    required this.onMove,
    super.key,
  });

  @override
  State<_DraggablePlanCard> createState() => _DraggablePlanCardState();
}

class _DraggablePlanCardState extends State<_DraggablePlanCard> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 160);
    final grip = Tooltip(
      message: 'Drag to reorder ${titleCase(widget.plan.name)}',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            LucideIcons.gripVertical,
            size: 18,
            color: textSecondaryColor(context),
          ),
        ),
      ),
    );

    Widget card(Widget? handle) => PlanCard(
      plan: widget.plan,
      index: widget.index,
      stat: widget.stat,
      onOpen: widget.onOpen,
      onShowActions: widget.onShowActions,
      reorderHandle: handle,
    );

    return LayoutBuilder(
      builder:
          (context, constraints) => DragTarget<String>(
            onWillAcceptWithDetails:
                (details) => details.data != widget.plan.id && !_dragging,
            onAcceptWithDetails: (details) {
              HapticFeedback.selectionClick();
              widget.onMove(details.data, widget.plan.id!);
            },
            builder:
                (context, candidates, _) => Stack(
                  fit: StackFit.passthrough,
                  children: [
                    AnimatedOpacity(
                      duration: duration,
                      opacity: _dragging ? 0.3 : 1,
                      child: card(
                        !widget.canDrag
                            ? null
                            : Draggable<String>(
                              data: widget.plan.id!,
                              maxSimultaneousDrags: 1,
                              // Anchor the full-card preview at the grip under the finger.
                              // The listener itself is only the 48px handle.
                              dragAnchorStrategy: (
                                draggable,
                                context,
                                position,
                              ) {
                                final cardBox =
                                    this.context.findRenderObject()!
                                        as RenderBox;
                                return cardBox.globalToLocal(position);
                              },
                              onDragStarted: () {
                                HapticFeedback.lightImpact();
                                setState(() => _dragging = true);
                              },
                              onDragEnd: (_) {
                                if (mounted) setState(() => _dragging = false);
                              },
                              feedback: MediaQuery(
                                data: MediaQuery.of(context),
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height:
                                      constraints.hasBoundedHeight
                                          ? constraints.maxHeight
                                          : null,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: 1),
                                    duration: duration,
                                    curve: Curves.easeOutCubic,
                                    builder:
                                        (context, lift, child) =>
                                            Transform.scale(
                                              scale: 1 + 0.025 * lift,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  borderRadius: AppRadius.card,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Theme.of(context)
                                                          .shadowColor
                                                          .withAlpha(45),
                                                      blurRadius: 20 * lift,
                                                      offset: Offset(
                                                        0,
                                                        6 * lift,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: child,
                                              ),
                                            ),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: card(grip),
                                    ),
                                  ),
                                ),
                              ),
                              child: grip,
                            ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.card,
                            border: Border.all(
                              color:
                                  candidates.isEmpty
                                      ? Colors.transparent
                                      : accentColor(context),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }
}

class _PlanGridLayout extends MultiChildRenderObjectWidget {
  final Animation<double> motion;
  final TextDirection textDirection;

  const _PlanGridLayout({
    required this.motion,
    required this.textDirection,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlanGrid(motion, textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderPlanGrid renderObject) {
    renderObject.textDirection = textDirection;
  }
}

class _PlanGridParentData extends ContainerBoxParentData<RenderBox> {
  Offset? target;
  Offset start = Offset.zero;
}

/// Layout and hit testing use the same interpolated offsets, so moving cards
/// remain tappable at their visible positions. No duplicate measuring widgets.
class _RenderPlanGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PlanGridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PlanGridParentData> {
  final Animation<double> motion;
  TextDirection _textDirection;
  double? _lastWidth;
  double _lastProgress = 1;
  static const double _gap = 10;

  _RenderPlanGrid(this.motion, this._textDirection);

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _lastWidth = null;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    motion.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    motion.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PlanGridParentData) {
      child.parentData = _PlanGridParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final columns = (width / 340).floor().clamp(1, 3);
    final cardWidth = (width - _gap * (columns - 1)) / columns;
    final animate = _lastWidth == width;
    _lastWidth = width;
    final progress = Curves.easeInOutCubic.transform(motion.value);
    final restarted = progress < _lastProgress;
    _lastProgress = progress;
    double top = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      final row = <RenderBox>[];
      double height = 0;
      for (var column = 0; column < columns && child != null; column++) {
        child.layout(
          BoxConstraints.tightFor(width: cardWidth),
          parentUsesSize: true,
        );
        height = math.max(height, child.size.height);
        row.add(child);
        child = childAfter(child);
      }
      for (var column = 0; column < row.length; column++) {
        final item = row[column];
        item.layout(
          BoxConstraints.tight(Size(cardWidth, height)),
          parentUsesSize: true,
        );
        final visualColumn =
            _textDirection == TextDirection.ltr ? column : columns - column - 1;
        final target = Offset(visualColumn * (cardWidth + _gap), top);
        final data = item.parentData! as _PlanGridParentData;
        if (data.target != target || restarted) {
          data.start = data.offset;
          if (data.target == null || !animate) data.start = target;
          data.target = target;
        }
        data.offset =
            animate ? Offset.lerp(data.start, target, progress)! : target;
      }
      top += height + (child == null ? 0 : _gap);
    }
    size = constraints.constrain(Size(width, top));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
