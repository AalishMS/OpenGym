import 'package:flutter/material.dart';

/// A figure that rolls to its new value instead of blinking: the old value
/// slides out and fades as the new one slides in, upward when the number grew
/// and downward when it fell. With reduced motion it simply changes.
///
/// Only one [Text] remains once the roll settles, so it reads (and finds in
/// tests) exactly like a plain figure.
class RollingFigure extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Key for the settled [Text], for callers that look the figure up.
  final Key? textKey;
  final AlignmentGeometry alignment;
  final int? maxLines;

  const RollingFigure(
    this.text, {
    super.key,
    this.style,
    this.textKey,
    this.alignment = AlignmentDirectional.centerStart,
    this.maxLines,
  });

  @override
  State<RollingFigure> createState() => _RollingFigureState();
}

class _RollingFigureState extends State<RollingFigure> {
  bool _up = true;

  static double? _numberIn(String text) {
    final match = RegExp(r'[-−]?[\d,]*\.?\d+').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(
      match.group(0)!.replaceAll(',', '').replaceAll('−', '-'),
    );
  }

  @override
  void didUpdateWidget(RollingFigure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) return;
    final before = _numberIn(oldWidget.text);
    final after = _numberIn(widget.text);
    if (before != null && after != null && before != after) {
      _up = after > before;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      key: widget.textKey,
      style: widget.style,
      maxLines: widget.maxLines,
    );
    if (MediaQuery.disableAnimationsOf(context)) return text;
    final current = ValueKey(widget.text);
    final direction = _up ? 1.0 : -1.0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder:
          (currentChild, previousChildren) => Stack(
            alignment: widget.alignment,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
      transitionBuilder: (child, animation) {
        final entering = child.key == current;
        final offset = Tween<Offset>(
          // Entering comes from below on the way up; leaving goes above.
          begin: Offset(0, (entering ? 0.35 : -0.35) * direction),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(key: current, child: text),
    );
  }
}
