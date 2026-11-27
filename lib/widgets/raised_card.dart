import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/radii.dart';
import 'motion/press_scale.dart';

/// A card that lifts off the page: the raised surface, a soft shadow in light
/// mode and a hairline edge in dark mode, where a shadow has nothing to fall on.
///
/// Reserve it for the few things that should stand forward — the workout
/// launcher, the next plan, a preset to pick. Lists are rows on the page, and
/// a card is never nested in another ground.
///
/// A raised card with [onTap] or [onLongPress] gives slightly under the
/// finger ([PressScale]) as well as taking the ink; a plain row ([raised]
/// false) takes only the ink, as list rows do.
class RaisedCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  /// Paints the card as a plain row instead, keeping the same shape and ink
  /// so a row can rise into a card (and settle back) without moving.
  final bool raised;

  /// Makes [onTap] and [onLongPress] a convenience for a finger or a mouse
  /// only: the card takes no keyboard focus and a screen reader doesn't
  /// offer it as a button. Use it when a control inside the card already
  /// carries the same action, so assistive technology meets it once.
  final bool pointerOnly;

  const RaisedCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = AppRadius.card,
    this.raised = true,
    this.pointerOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget card(Widget content) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: raised ? raisedShadow(context) : null,
      ),
      child: Material(
        color: raised ? surfaceColor(context) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side:
              raised && dark
                  ? BorderSide(color: hairlineColor(context))
                  : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );

    if (onTap == null && onLongPress == null) return card(child);
    // Off rather than absent for a plain row, so a row rising into a card
    // (and settling back) keeps the same tree.
    return PressScale(
      enabled: raised,
      builder:
          (context, onHighlightChanged) => card(
            InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              onHighlightChanged: onHighlightChanged,
              excludeFromSemantics: pointerOnly,
              canRequestFocus: !pointerOnly,
              borderRadius: borderRadius,
              child: child,
            ),
          ),
    );
  }
}

/// The [RaisedCard] look as a [BoxDecoration], for panels that are laid out
/// with a [DecoratedBox] or [Container] rather than tapped.
BoxDecoration raisedDecoration(
  BuildContext context, {
  BorderRadius borderRadius = AppRadius.card,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: surfaceColor(context),
    borderRadius: borderRadius,
    border: dark ? Border.all(color: hairlineColor(context)) : null,
    boxShadow: raisedShadow(context),
  );
}
