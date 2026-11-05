import 'package:flutter/material.dart';

/// A plan name that flies from Home's Next up card into the workout header,
/// so starting a workout reads as opening that card rather than jumping to a
/// new page. The size and weight ease between the two styles in flight.
///
/// Without a [tag] it is just the text, which keeps the header usable when
/// the workout was opened from anywhere else.
class PlanTitleHero extends StatelessWidget {
  final String? tag;
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const PlanTitleHero({
    super.key,
    required this.tag,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
    if (tag == null) return title;
    return Hero(
      tag: tag!,
      flightShuttleBuilder: _shuttle,
      // Material keeps the text's ink in flight, above the route transition.
      child: Material(type: MaterialType.transparency, child: title),
    );
  }

  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final from = fromHeroContext.findAncestorWidgetOfExactType<PlanTitleHero>();
    final to = toHeroContext.findAncestorWidgetOfExactType<PlanTitleHero>();
    if (from == null || to == null) {
      return (toHeroContext.widget as Hero).child;
    }
    final fromStyle = DefaultTextStyle.of(fromHeroContext).style.merge(
      from.style,
    );
    final toStyle = DefaultTextStyle.of(toHeroContext).style.merge(to.style);
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder:
            (context, _) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                animation.value < .5 ? from.text : to.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle.lerp(
                  fromStyle,
                  toStyle,
                  Curves.easeInOut.transform(animation.value),
                ),
              ),
            ),
      ),
    );
  }
}
