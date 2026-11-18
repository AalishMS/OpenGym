import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';

/// Fades a whole surface in where it has just replaced another: the *change*
/// of what a place on screen is, such as one main tab for another, another
/// split's plans on Home, or the login screen in place of the app.
///
/// When [identity] changes, [child] fades in from [floor] to full over
/// [AppMotion.quick] on [AppMotion.curve]. What it replaced is not kept: the
/// caller swaps the content at once, and only the new content's opacity
/// moves, so nothing from the old surface can be read, tapped or focused on
/// its way out. Use `StateSwitcher` instead when the two states should cross,
/// and `PageSwitcher` when one page goes deeper than the other.
///
/// It starts from [floor] rather than from nothing because the old surface is
/// already gone: a fade from zero would spend its first frame on the bare
/// page, a blink that reads as a flicker (black, in dark mode). From the
/// floor, the first frame already shows what replaced it, and the rest of the
/// fade still marks the change.
///
/// It plays only for a change the reader can see. It lands at rest when
/// [enabled] is false, when its tickers are muted (a change made under a
/// pushed page or on another tab), under reduced motion, and when the
/// identity changes to or from null, which stands for nothing shown yet (the
/// first load). A rebuild with the same identity replays nothing. The child
/// is laid out, tappable and announced from its first frame.
class SurfaceFade extends StatefulWidget {
  /// How opaque a replacing surface is on its first frame.
  static const double floor = 0.4;

  /// What the surface is. A change of it fades the child in.
  final Object? identity;

  /// Whether a change of [identity] plays, read at the moment it changes.
  final bool enabled;

  final Widget child;

  const SurfaceFade({
    super.key,
    required this.identity,
    this.enabled = true,
    required this.child,
  });

  @override
  State<SurfaceFade> createState() => _SurfaceFadeState();
}

class _SurfaceFadeState extends State<SurfaceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.quick,
    value: 1,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: SurfaceFade.floor,
    end: 1,
  ).chain(CurveTween(curve: AppMotion.curve)).animate(_controller);

  @override
  void didUpdateWidget(SurfaceFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity == oldWidget.identity) return;
    final seen =
        widget.enabled &&
        widget.identity != null &&
        oldWidget.identity != null &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (seen) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    alwaysIncludeSemantics: true,
    child: widget.child,
  );
}
