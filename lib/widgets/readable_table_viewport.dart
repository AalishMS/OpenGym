import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Measure the requested text size, including the current accessibility scale.
double readableTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

/// Keep table columns readable; compact windows scroll instead of shrinking ink.
class ReadableTableViewport extends StatefulWidget {
  final double minimumWidth;
  final Widget child;
  final bool showScrollbar;

  const ReadableTableViewport({
    required this.minimumWidth,
    required this.child,
    this.showScrollbar = true,
    super.key,
  });

  @override
  State<ReadableTableViewport> createState() => _ReadableTableViewportState();
}

class _ReadableTableViewportState extends State<ReadableTableViewport> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // A table that fits must not compete with its parent's swipe gesture.
      if (widget.minimumWidth <= constraints.maxWidth) {
        return SizedBox(width: constraints.maxWidth, child: widget.child);
      }
      final showScrollbar =
          widget.showScrollbar && widget.minimumWidth > constraints.maxWidth;
      final scrollView = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.only(bottom: showScrollbar ? 12 : 0),
          child: SizedBox(
            width: math.max(widget.minimumWidth, constraints.maxWidth),
            child: widget.child,
          ),
        ),
      );
      return widget.showScrollbar
          ? Scrollbar(
            controller: _controller,
            thumbVisibility: showScrollbar,
            child: scrollView,
          )
          : scrollView;
    },
  );
}
