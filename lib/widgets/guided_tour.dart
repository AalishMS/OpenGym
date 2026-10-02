import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';

class GuidedTourStep {
  final GlobalKey target;
  final String title;
  final String body;
  final ScrollController? scrollController;
  final bool scrollToEnd;

  const GuidedTourStep({
    required this.target,
    required this.title,
    required this.body,
    this.scrollController,
    this.scrollToEnd = false,
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
    if (target is! RenderBox || overlay is! RenderBox || !target.hasSize) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      target.getTransformTo(overlay),
      Offset.zero & target.size,
    ).intersect(Offset.zero & overlay.size);
    return rect.isEmpty ? null : rect.inflate(6);
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
                  borderRadius: AppRadius.button,
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
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_index + 1} of ${widget.steps.length}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                step.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                step.body,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: TextButton(
                              onPressed: widget.onClose,
                              child: const Text('Skip'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: ElevatedButton(
                              onPressed: rect == null ? null : _next,
                              child: Text(
                                _index == widget.steps.length - 1
                                    ? 'Done'
                                    : 'Next',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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

  const _SpotlightPainter({required this.target, required this.scrim});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    if (target != null) {
      path.addRRect(AppRadius.button.toRRect(target!));
    }
    canvas.drawPath(path, Paint()..color = scrim);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      target != oldDelegate.target || scrim != oldDelegate.scrim;
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
      if (candidate.width < 160 || candidate.height < 96) continue;
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
