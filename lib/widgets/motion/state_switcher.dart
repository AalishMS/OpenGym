import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';

/// Swaps one piece of content for another in the same place with a quick
/// cross-fade: the *change* from one state to the next, such as loading to
/// content, an empty state to a list, or one label for another.
///
/// Give each state its own key (`ValueKey('loading')`, `ValueKey(text)`); a
/// new key is a new state, and the same key just rebuilds in place. The
/// arriving content fades in over [AppMotion.quick] on [AppMotion.curve]; the
/// leaving content gives way on [AppMotion.exit] and stops taking taps, gives
/// up keyboard focus and leaves the semantics tree the moment it starts to
/// go, so a fading button can't be pressed twice. Both are stacked at [alignment] while they cross,
/// so the layout doesn't jump. With [animateSize] the space they take eases
/// to the new size over [AppMotion.standard] instead of snapping. Under
/// reduced motion the content simply changes.
///
/// Don't use it for a value that should roll (`RollingFigure`), for a region
/// that opens and closes (`Collapsible`), or for whole pages.
class StateSwitcher extends StatelessWidget {
  /// The content showing now, keyed by its state.
  final Widget child;

  /// Whether the space the content takes eases to its new size.
  final bool animateSize;

  /// Where both states sit while they cross, and where a size change grows
  /// from.
  final AlignmentGeometry alignment;

  const StateSwitcher({
    super.key,
    required this.child,
    this.animateSize = false,
    this.alignment = AlignmentDirectional.topStart,
  });

  @override
  Widget build(BuildContext context) {
    final Widget switcher = AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.quick),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.exit,
      layoutBuilder:
          (current, previous) => Stack(
            alignment: alignment,
            children: [...previous, if (current != null) current],
          ),
      transitionBuilder: _crossing,
      child: child,
    );
    // AnimatedSize asserts when a size change is given no time, and under
    // reduced motion there is nothing to ease.
    if (!animateSize || MediaQuery.disableAnimationsOf(context)) {
      return switcher;
    }
    return AnimatedSize(
      duration: AppMotion.standard,
      curve: AppMotion.curve,
      alignment: alignment,
      child: switcher,
    );
  }

  // A tear-off rather than a closure, so a rebuild doesn't make the switcher
  // rebuild its leaving content's transitions.
  static Widget _crossing(Widget child, Animation<double> animation) =>
      _Crossing(animation: animation, child: child);
}

/// One side of the cross: fades with the switcher, is announced from the
/// moment it arrives, and once it is leaving takes no taps and says nothing
/// to screen readers.
class _Crossing extends StatusTransitionWidget {
  final Widget child;

  const _Crossing({required super.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    final leaving = !animation.isForwardOrCompleted;
    return IgnorePointer(
      ignoring: leaving,
      // A leaving control can't keep keyboard focus either, or Enter would
      // still press a button that is fading away.
      child: ExcludeFocus(
        excluding: leaving,
        child: ExcludeSemantics(
          excluding: leaving,
          // The arriving state is announced from its first frame, before it
          // can be seen, as it is findable and tappable.
          child: FadeTransition(
            opacity: animation,
            alwaysIncludeSemantics: !leaving,
            child: child,
          ),
        ),
      ),
    );
  }
}
