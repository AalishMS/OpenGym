import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';

/// Describes the visible bounds when a control's hit area is larger than its
/// contents, or its icon and label live in separate parts of a native widget.
class GuidedTourTarget extends StatelessWidget {
  final Widget child;
  final GlobalKey? additionalTarget;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  const GuidedTourTarget({
    required this.child,
    this.additionalTarget,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.borderRadius = AppRadius.button,
    super.key,
  });

  @override
  Widget build(BuildContext context) => child;
}

class GuidedTourStep {
  final GlobalKey target;
  final String title;
  final String body;
  final ScrollController? scrollController;
  final bool scrollToEnd;
  final IconData icon;
  final String label;

  const GuidedTourStep({
    required this.target,
    required this.title,
    required this.body,
    this.scrollController,
    this.scrollToEnd = false,
    this.icon = LucideIcons.dumbbell,
    this.label = 'Quick tour',
  });
}

/// A modal spotlight over the real UI. It never taps a target or creates data.
class GuidedTour extends StatefulWidget {
  final List<GuidedTourStep> steps;
  final VoidCallback onClose;

  const GuidedTour({required this.steps, required this.onClose, super.key});

  @override
  State<GuidedTour> createState() => _GuidedTourState();
}

class _GuidedTourState extends State<GuidedTour> with WidgetsBindingObserver {
  final GlobalKey _overlayKey = GlobalKey();
  int _index = 0;
  int _revision = 0;
  Rect? _targetRect;
  BorderRadius _targetRadius = AppRadius.card;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_trackTarget);
  }

  @override
  void dispose() {
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepare();
  }

  @override
  void didChangeMetrics() => _prepare();

  Rect? _measureTarget() {
    final target =
        widget.steps[_index].target.currentContext?.findRenderObject();
    final overlay = _overlayKey.currentContext?.findRenderObject();
    if (target is! RenderBox ||
        overlay is! RenderBox ||
        !target.attached ||
        !target.hasSize ||
        !overlay.hasSize) {
      return null;
    }
    var rect = MatrixUtils.transformRect(
      target.getTransformTo(overlay),
      Offset.zero & target.size,
    );
    final anchor = widget.steps[_index].target.currentWidget;
    if (anchor is GuidedTourTarget) {
      final additional =
          anchor.additionalTarget?.currentContext?.findRenderObject();
      if (additional is RenderBox &&
          additional.attached &&
          additional.hasSize) {
        rect = rect.expandToInclude(
          MatrixUtils.transformRect(
            additional.getTransformTo(overlay),
            Offset.zero & additional.size,
          ),
        );
      }
      final inset = anchor.padding;
      rect = Rect.fromLTRB(
        rect.left - inset.left,
        rect.top - inset.top,
        rect.right + inset.right,
        rect.bottom + inset.bottom,
      );
      _targetRadius = anchor.borderRadius;
    } else {
      // The outer radius follows the button's parallel outline: 10 + 4px.
      rect = rect.inflate(AppSpacing.xs);
      _targetRadius = AppRadius.card;
    }
    // Leave space for the stroke on every edge, including near a safe area.
    rect = rect.intersect((Offset.zero & overlay.size).deflate(2));
    return rect.isEmpty ? null : rect;
  }

  void _trackTarget(Duration timestamp) {
    if (!mounted) return;
    if (_targetRect != null) {
      final rect = _measureTarget();
      if (rect != null && rect != _targetRect) {
        setState(() => _targetRect = rect);
      } else if (rect == null) {
        _prepare();
      }
    }
    // Follow layout animations as frames arrive, without requesting idle
    // frames or running a timer when nothing is changing.
    WidgetsBinding.instance.addPostFrameCallback(_trackTarget);
  }

  void _prepare() {
    final revision = ++_revision;
    _targetRect = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || revision != _revision) return;
      if (_index >= widget.steps.length) {
        widget.onClose();
        return;
      }
      final step = widget.steps[_index];
      // A lazy Home list may not have built New plan yet. Scroll it into the
      // viewport before looking up the target, then allow layout to settle.
      for (var attempt = 0; attempt < 4; attempt++) {
        final controller = step.scrollController;
        if (controller != null && controller.hasClients) {
          controller.jumpTo(
            step.scrollToEnd ? controller.position.maxScrollExtent : 0,
          );
        }
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || revision != _revision) return;
        final targetContext = step.target.currentContext;
        if (targetContext == null || !targetContext.mounted) continue;
        await Scrollable.ensureVisible(targetContext, alignment: .15);
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || revision != _revision) return;
        final rect = _measureTarget();
        if (rect == null) continue;
        setState(() => _targetRect = rect);
        return;
      }
      // Data can disappear while the tour is open. An absent target must not
      // strand the user on a dimmed screen.
      _next();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _next() {
    if (_index + 1 >= widget.steps.length) {
      widget.onClose();
      return;
    }
    setState(() {
      _index++;
      _targetRect = null;
    });
    _prepare();
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
    _prepare();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final step = widget.steps[_index];
    final padding = MediaQuery.paddingOf(context);
    final rect = _targetRect;
    return Stack(
      key: _overlayKey,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SpotlightPainter(
              target: rect,
              scrim: Theme.of(context).colorScheme.scrim.withAlpha(190),
              radius: _targetRadius,
            ),
          ),
        ),
        if (rect != null)
          Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('tutorial-highlight'),
                decoration: BoxDecoration(
                  border: Border.all(color: accentColor(context), width: 2),
                  borderRadius: _targetRadius,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor(context).withAlpha(45),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _BubbleLayout(target: rect, safePadding: padding),
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              namesRoute: true,
              label: 'Tutorial',
              liveRegion: true,
              child: Material(
                key: const ValueKey('tutorial-bubble'),
                color: surfaceColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.card,
                  side: BorderSide(color: borderColor(context)),
                ),
                clipBehavior: Clip.antiAlias,
                elevation: 8,
                shadowColor: Theme.of(context).colorScheme.scrim.withAlpha(90),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 240;
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!compact)
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: accentMutedColor(context),
                                    borderRadius: AppRadius.control,
                                  ),
                                  child: Icon(
                                    step.icon,
                                    size: 18,
                                    color: accentColor(context),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    step.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium?.copyWith(
                                      color: textSecondaryColor(context),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_index + 1} of ${widget.steps.length}',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: accentColor(context)),
                                ),
                              ],
                            ),
                          if (compact)
                            Text(
                              '${_index + 1} of ${widget.steps.length}',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: accentColor(context)),
                            ),
                          SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.md,
                          ),
                          ExcludeSemantics(
                            child: Row(
                              children: [
                                for (var i = 0; i < widget.steps.length; i++)
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right:
                                            i == widget.steps.length - 1
                                                ? 0
                                                : AppSpacing.xs,
                                      ),
                                      child: AnimatedContainer(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                                  context,
                                                )
                                                ? Duration.zero
                                                : const Duration(
                                                  milliseconds: 180,
                                                ),
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color:
                                              i <= _index
                                                  ? accentFillColor(context)
                                                  : borderColor(context),
                                          borderRadius: AppRadius.micro,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: compact ? AppSpacing.sm : AppSpacing.lg,
                          ),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    step.body,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.copyWith(
                                      color: textSecondaryColor(context),
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          OverflowBar(
                            alignment: MainAxisAlignment.spaceBetween,
                            overflowAlignment: OverflowBarAlignment.end,
                            spacing: AppSpacing.sm,
                            overflowSpacing: AppSpacing.xs,
                            children: [
                              TextButton(
                                onPressed: widget.onClose,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                  ),
                                ),
                                child: const Text('Skip'),
                              ),
                              if (_index > 0)
                                TextButton(
                                  onPressed: rect == null ? null : _back,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                    ),
                                  ),
                                  child: const Text('Back'),
                                ),
                              ElevatedButton(
                                onPressed: rect == null ? null : _next,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg,
                                  ),
                                ),
                                child: Text(
                                  _index == widget.steps.length - 1
                                      ? 'Done'
                                      : 'Next',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? target;
  final Color scrim;
  final BorderRadius radius;

  const _SpotlightPainter({
    required this.target,
    required this.scrim,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    if (target != null) {
      path.addRRect(radius.toRRect(target!));
    }
    canvas.drawPath(path, Paint()..color = scrim);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      target != oldDelegate.target ||
      scrim != oldDelegate.scrim ||
      radius != oldDelegate.radius;
}

/// Uses the bubble's measured size, rather than assuming a fixed text height.
class _BubbleLayout extends SingleChildLayoutDelegate {
  final Rect? target;
  final EdgeInsets safePadding;

  const _BubbleLayout({required this.target, required this.safePadding});

  Rect _bounds(Size size) => Rect.fromLTRB(
    AppSpacing.lg,
    safePadding.top + AppSpacing.lg,
    size.width - AppSpacing.lg,
    size.height - safePadding.bottom - AppSpacing.lg,
  );

  Rect _region(Size size) {
    final bounds = _bounds(size);
    final rect = target;
    if (rect == null) return bounds;
    final candidates = [
      Rect.fromLTRB(
        bounds.left,
        rect.bottom + AppSpacing.md,
        bounds.right,
        bounds.bottom,
      ),
      Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.right,
        rect.top - AppSpacing.md,
      ),
      Rect.fromLTRB(
        rect.right + AppSpacing.md,
        bounds.top,
        bounds.right,
        bounds.bottom,
      ),
      Rect.fromLTRB(
        bounds.left,
        bounds.top,
        rect.left - AppSpacing.md,
        bounds.bottom,
      ),
    ];
    Rect? best;
    double bestScore = -1;
    for (final candidate in candidates) {
      if (candidate.width < 180 || candidate.height < 140) continue;
      final score =
          math.min(candidate.width, 360.0) * math.min(candidate.height, 320.0);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best ?? bounds;
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final region = _region(constraints.biggest);
    return BoxConstraints(
      maxWidth: math.min(360, region.width),
      maxHeight: region.height,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _region(size);
    final rect = target;
    final wantedY =
        rect == null
            ? bounds.center.dy - childSize.height / 2
            : bounds.top >= rect.bottom
            ? bounds.top
            : bounds.bottom <= rect.top
            ? bounds.bottom - childSize.height
            : rect.center.dy - childSize.height / 2;
    final wantedX = (rect?.center.dx ?? bounds.center.dx) - childSize.width / 2;
    return Offset(
      wantedX.clamp(bounds.left, bounds.right - childSize.width),
      wantedY.clamp(bounds.top, bounds.bottom - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) =>
      target != oldDelegate.target || safePadding != oldDelegate.safePadding;
}
