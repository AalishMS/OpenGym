import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';

/// Trades one page for another along a shared horizontal axis: the
/// *continuity* of going one step deeper into a set of pages, or back out.
///
/// Give each page its own key; a new key is a new page, and the same key just
/// rebuilds in place (so typing more into a search keeps its results page).
/// Over [AppMotion.standard] the arriving page fades in as it slides the last
/// [AppMotion.shift] pixels into place, from the end side when [forward] and
/// from the start side going back, while the leaving page clears out the
/// other way in the first third. Both directions mirror in right-to-left
/// layouts. Both pages fill the switcher's place while they cross.
///
/// The arriving page is laid out, tappable and announced from its first
/// frame. The leaving page takes no taps, gives up keyboard focus and leaves
/// the semantics tree the moment it starts to go. Under reduced motion the
/// page simply changes.
///
/// Each page must own its scroll position, because both are attached while
/// they cross and a controller with two positions throws wherever its one
/// position is read (the desktop scrollbar, for one). So pages don't inherit
/// the route's primary scroll controller, and a caller must never hand both
/// pages one controller of its own: give each page its own, as
/// `OwnScrollController` does. Each page is built once per change and moves
/// as it is; nothing in it is rebuilt on the frames of the trade.
///
/// For pages that must stay alive while the other shows, drive
/// [PageSwitchTransition] with an animation of your own instead. Don't use it
/// for peers that aren't deeper or shallower than each other (the main tabs
/// fade), or for one state of a control crossing to the next (use
/// `StateSwitcher`).
class PageSwitcher extends StatelessWidget {
  /// Whether this change goes deeper (arriving from the end side) rather
  /// than back. A page already leaving follows the latest direction too.
  final bool forward;

  /// The page showing now, keyed by its identity.
  final Widget child;

  const PageSwitcher({super.key, required this.forward, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.standard),
      layoutBuilder:
          (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
      // A new closure each build, so a page already leaving picks up the
      // latest direction too.
      transitionBuilder:
          (page, animation) => PageSwitchTransition(
            animation: animation,
            forward: forward,
            child: page,
          ),
      child: child,
    );
  }
}

/// One side of a [PageSwitcher] trade, driven by an animation of the
/// caller's: the page arrives while [animation] runs forward and leaves while
/// it runs in reverse, by its status rather than by which page it is. So a
/// page returned to before it finished leaving keeps leaving instead of
/// flashing back in beside its replacement, and a trade reversed midway
/// turns both pages round.
///
/// Use it to trade two pages that must both stay alive, such as a catalog
/// that keeps its scroll position through a trip into a detail page and back:
/// give the deeper page the animation and the other its `ReverseAnimation`,
/// and pass the direction the trade is travelling as [forward]. A page whose
/// animation is dismissed is offstage but keeps its state.
///
/// It has the same timing and rules as [PageSwitcher] when the animation is
/// linear over [AppMotion.standard], scroll controllers included; under
/// reduced motion, jump the animation rather than running it. Build both
/// pages outside anything that rebuilds per frame and pass them in.
class PageSwitchTransition extends StatusTransitionWidget {
  /// How a leaving page fades over the trade: it clears out in the first 35%.
  /// Public so a trade driven differently (the workout's plan switch, whose
  /// leaving page carries a swipe's speed) keeps the same shape.
  static const Interval leavingFade = Interval(0, 0.35);

  /// How an arriving page fades over the trade: from 30% on, so the two pages
  /// never read as one.
  static const Interval arrivingFade = Interval(0.3, 1, curve: AppMotion.curve);

  /// Whether the trade goes deeper: the arriving page comes from the end
  /// side and the leaving one goes toward the start.
  final bool forward;

  final Widget child;

  const PageSwitchTransition({
    super.key,
    required super.animation,
    required this.forward,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final arriving = animation.isForwardOrCompleted;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // +1 moves pages toward the start: arriving from the right in LTR.
    final direction = (forward ? 1.0 : -1.0) * (rtl ? -1.0 : 1.0);
    // One shape however the page stands, so its state survives every trade.
    return Offstage(
      offstage: animation.isDismissed,
      child: IgnorePointer(
        ignoring: !arriving,
        // A leaving control can't keep keyboard focus either, or Enter
        // would still press a button on its way out.
        child: ExcludeFocus(
          excluding: !arriving,
          child: ExcludeSemantics(
            excluding: !arriving,
            child: AnimatedBuilder(
              animation: animation,
              // Built here, once per status, and passed through every frame.
              // Without a primary controller of its own to take, each page's
              // scroll view scrolls on its own.
              child: PrimaryScrollController.none(child: child),
              builder: (context, child) {
                final t = animation.value;
                final double dx;
                final double opacity;
                if (arriving) {
                  dx = 1 - AppMotion.curve.transform(t);
                  opacity = arrivingFade.transform(t);
                } else {
                  final progress = 1 - t;
                  dx = -AppMotion.curve.transform(progress);
                  opacity = 1 - leavingFade.transform(progress);
                }
                // The arriving page is announced from its first frame,
                // before it can be seen, as it is findable and tappable.
                return Opacity(
                  opacity: opacity,
                  alwaysIncludeSemantics: arriving,
                  child: Transform.translate(
                    offset: Offset(dx * AppMotion.shift * direction, 0),
                    child: child,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
