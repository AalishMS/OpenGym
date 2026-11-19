import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';

/// Fades [child] in and lifts it [AppMotion.lift] pixels into place the first
/// time it is built: the *arrival* of content that is new to the screen.
///
/// Use it for content that appears in front of the reader: exercises added to
/// a plan, the first load of a screen's main group. Give a few items
/// that arrive together increasing [index]es and each starts
/// [AppMotion.stagger] after the last (at most [maxStaggered] steps).
///
/// It plays once per [State]. A rebuild, a returning tab or a route popped
/// back to never replays it, and changing [animate] or [index] afterwards
/// does nothing. That also means a new State plays it again, so don't put it
/// on items of a lazily built list that scroll out and back (they are
/// rebuilt from scratch), and pass `animate: false` for content that was
/// already there, such as a plan's own exercises when its editor opens.
///
/// The child is laid out, hit-testable, findable and in the semantics tree
/// from the first frame; only its opacity and offset move, so nothing waits
/// for the arrival. Under reduced motion it simply appears.
class Entrance extends StatefulWidget {
  /// The most stagger steps an arrival waits, so a long batch doesn't keep
  /// its last item waiting.
  static const int maxStaggered = 6;

  /// Whether to play the arrival. Read once, on the first build.
  final bool animate;

  /// The place in a batch arriving together; 0 starts at once.
  final int index;

  final Widget child;

  const Entrance({
    super.key,
    this.animate = true,
    this.index = 0,
    required this.child,
  });

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double> _progress = kAlwaysCompleteAnimation;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) return;
    final delay =
        AppMotion.stagger * widget.index.clamp(0, Entrance.maxStaggered);
    final total = delay + AppMotion.enter;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: AppMotion.curve,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One tree shape whether or not the arrival plays, so the child keeps its
    // state either way. At rest both layers paint the child as it is. Screen
    // readers get the content from the first frame, as finders and taps do.
    return FadeTransition(
      opacity: _progress,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: _progress,
        builder:
            (context, child) => Transform.translate(
              offset: Offset(0, AppMotion.lift * (1 - _progress.value)),
              child: child,
            ),
        child: widget.child,
      ),
    );
  }
}
