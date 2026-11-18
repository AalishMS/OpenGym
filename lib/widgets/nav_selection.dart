import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// Eases one navigation destination between selected and not over
/// [AppMotion.standard], in step with the bar's rule or the rail's
/// indicator, rather than snapping as the Material widgets would. It hands
/// [builder] the selection's progress, 0 to 1, for the colours that ease;
/// the label's weight takes [selected] at once instead, because the bundled
/// fonts are static weights, and a weight eased through them steps and
/// shifts a centred label mid-change. It starts at rest, so navigation never
/// animates on arrival. Under reduced motion the change is immediate.
class NavSelection extends StatelessWidget {
  final bool selected;
  final Widget Function(BuildContext context, double t) builder;

  const NavSelection({
    super.key,
    required this.selected,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.curve,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// A destination's attention dot, such as Settings while an update waits. It
/// fades in and out over [AppMotion.quick] rather than popping, keeping the
/// badge's own size and place.
class NavBadge extends StatelessWidget {
  final bool visible;
  final Widget child;

  const NavBadge({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    final ground = accentFillColor(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.curve,
      child: child,
      builder:
          (context, t, child) => Badge(
            isLabelVisible: t > 0,
            smallSize: 7,
            backgroundColor: ground.withValues(alpha: ground.a * t),
            child: child,
          ),
    );
  }
}
