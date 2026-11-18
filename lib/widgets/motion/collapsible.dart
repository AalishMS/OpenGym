import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';

/// Opens and closes [child] by growing and fading it from the top, and drops
/// it from the tree once closed: the *continuity* of a region that folds
/// away, so the content around it moves rather than jumps.
///
/// Use it for anything that expands in place: a card's details, an inline
/// palette or message, an advanced section. A closed region holds no
/// controls or semantics, so tests and screen readers don't find what can't
/// be seen. It starts at rest; only a change of [open] animates, so a region
/// that is open when the screen appears is simply there. Opening and closing
/// take the same [AppMotion.standard], so reversing midway keeps its pace.
/// Under reduced motion it opens and closes at once.
///
/// Don't use it to show or hide a whole screen's content, or for content
/// swapped for other content in the same place (use `StateSwitcher`).
class Collapsible extends StatefulWidget {
  final bool open;
  final Widget child;

  const Collapsible({super.key, required this.open, required this.child});

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
    value: widget.open ? 1 : 0,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
    reverseCurve: AppMotion.exit,
  );

  void _onStatus(AnimationStatus status) {
    // Settling changes the clip, and closing drops the child.
    if (!status.isAnimating && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(Collapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    _controller.duration = AppMotion.of(context, AppMotion.standard);
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && _controller.isDismissed) return const SizedBox.shrink();
    return ClipRect(
      // Clip only while moving, so a settled region can paint past its edge
      // (focus rings, shadows).
      clipBehavior: _controller.isAnimating ? Clip.hardEdge : Clip.none,
      child: SizeTransition(
        sizeFactor: _progress,
        alignment: AlignmentDirectional.topStart,
        child: FadeTransition(opacity: _progress, child: widget.child),
      ),
    );
  }
}
