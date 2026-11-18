import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';

/// Opens and closes [child] by growing and fading it from the top, and drops
/// it from the tree once closed: the *continuity* of a region that folds
/// away, so the content around it moves rather than jumps.
///
/// Use it for anything that expands in place: a card's details, an inline
/// palette or message, an advanced section. A closed region holds no
/// controls or semantics, so tests and screen readers don't find what can't
/// be seen. A region on its way out is already inert: from the moment [open]
/// turns false it takes no taps, gives up keyboard focus (a field folding
/// away lets go of the keyboard) and leaves the semantics tree, while it
/// keeps painting what it held.
///
/// It starts at rest; only a change of [open] animates, so a region that is
/// open when the screen appears is simply there. Opening and closing take the
/// same [AppMotion.standard], so reversing midway keeps its pace. Under
/// reduced motion it opens and closes at once.
///
/// For something that has just gone and should fold out of its place, such
/// as a deleted row, start it open with [initiallyOpen] and [open] false: it
/// folds away from its first frame and reports [onClosed], so the caller can
/// drop it.
///
/// Don't use it to show or hide a whole screen's content, or for content
/// swapped for other content in the same place (use `StateSwitcher`).
class Collapsible extends StatefulWidget {
  final bool open;

  /// Where the region starts; by default where [open] says, so it is simply
  /// there. When it differs, the region moves to [open] from its first frame.
  final bool? initiallyOpen;

  /// Called once the region has finished closing.
  final VoidCallback? onClosed;

  final Widget child;

  const Collapsible({
    super.key,
    required this.open,
    this.initiallyOpen,
    this.onClosed,
    required this.child,
  });

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
    value: (widget.initiallyOpen ?? widget.open) ? 1 : 0,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
    reverseCurve: AppMotion.exit,
  );
  bool _started = false;

  /// Whether this close has been reported, so a close given no time, which
  /// may finish without reporting its status, is still told once.
  bool _closeReported = false;

  void _onStatus(AnimationStatus status) {
    if (status.isAnimating || !mounted) return;
    // Settling changes the clip, and closing drops the child.
    setState(() {});
    if (status.isDismissed && !widget.open) _reportClosed();
  }

  /// Tells the caller the region has gone. A close given no time finishes
  /// while the tree is being built, where the caller can't rebuild, so that
  /// one waits for the frame.
  void _reportClosed() {
    final onClosed = widget.onClosed;
    if (onClosed == null || _closeReported) return;
    _closeReported = true;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.open && _controller.isDismissed) onClosed();
      });
      return;
    }
    onClosed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.initiallyOpen == null || widget.initiallyOpen == widget.open) {
      return;
    }
    _moveTo(widget.open);
  }

  @override
  void didUpdateWidget(Collapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    _moveTo(widget.open);
  }

  void _moveTo(bool open) {
    _closeReported = false;
    _controller.duration = AppMotion.of(context, AppMotion.standard);
    if (open) {
      _controller.forward();
    } else {
      _controller.reverse();
      if (_controller.isDismissed) _reportClosed();
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
    final closing = !widget.open;
    if (closing && _controller.isDismissed) return const SizedBox.shrink();
    return FoldTransition(
      sizeFactor: _progress,
      // Clip only while moving, so a settled region can paint past its edge:
      // a raised card's shadow, a focus ring.
      clip: _controller.isAnimating,
      child: FadeTransition(
        opacity: _progress,
        // One shape open or closing, so what it holds keeps its state if it
        // opens again midway.
        child: IgnorePointer(
          ignoring: closing,
          child: ExcludeFocus(
            excluding: closing,
            child: ExcludeSemantics(excluding: closing, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Shows the top [sizeFactor] of [child]'s height, as a vertical
/// [SizeTransition] does, but clips only when [clip] is set.
///
/// [SizeTransition] always clips to its own box, so a card inside one loses
/// the part of its shadow that falls outside, even while nothing is moving:
/// the shadow is cut square at the box's edges and reads as a grey band.
/// [Collapsible] clips while it folds, when the child really is taller than
/// the space it has, and not once it has settled.
class FoldTransition extends AnimatedWidget {
  /// How much of the child's height shows, from 0 to 1.
  Animation<double> get sizeFactor => listenable as Animation<double>;

  final bool clip;
  final Widget child;

  const FoldTransition({
    super.key,
    required Animation<double> sizeFactor,
    required this.clip,
    required this.child,
  }) : super(listenable: sizeFactor);

  @override
  Widget build(BuildContext context) => ClipRect(
    clipBehavior: clip ? Clip.hardEdge : Clip.none,
    child: Align(
      alignment: AlignmentDirectional.topStart,
      heightFactor: sizeFactor.value.clamp(0.0, 1.0),
      child: child,
    ),
  );
}
