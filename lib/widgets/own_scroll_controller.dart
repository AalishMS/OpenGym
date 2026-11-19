import 'package:flutter/widgets.dart';

/// Gives a scroll view a [ScrollController] of its own for as long as it is
/// mounted, and tells the screen which one is newest.
///
/// A page or state that crosses with another copy of itself (`PageSwitcher`,
/// `StateSwitcher`) keeps the leaving copy mounted while the arriving one is
/// built. Had both taken one controller from the screen, that controller
/// would hold two positions for the length of the crossing, and anything
/// that reads its one position throws: the desktop scrollbar fading out, a
/// wheel scroll over its track, a thumb drag. With this each copy owns its
/// own controller and the leaving copy keeps its place. [onAttach] hands the
/// screen each new controller as its copy arrives, for scrolling the copy on
/// show back to the top, and [onDetach] reports one going with its copy.
class OwnScrollController extends StatefulWidget {
  /// Whether the scroll view's offset is kept in its `PageStorage`, as
  /// [ScrollController.keepScrollOffset].
  final bool keepScrollOffset;

  /// Called with the controller when this copy arrives.
  final ValueChanged<ScrollController>? onAttach;

  /// Called with the controller when this copy goes, just before it is
  /// disposed.
  final ValueChanged<ScrollController>? onDetach;

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  const OwnScrollController({
    super.key,
    this.keepScrollOffset = true,
    this.onAttach,
    this.onDetach,
    required this.builder,
  });

  @override
  State<OwnScrollController> createState() => _OwnScrollControllerState();
}

class _OwnScrollControllerState extends State<OwnScrollController> {
  late final ScrollController _controller = ScrollController(
    keepScrollOffset: widget.keepScrollOffset,
  );

  @override
  void initState() {
    super.initState();
    widget.onAttach?.call(_controller);
  }

  @override
  void dispose() {
    widget.onDetach?.call(_controller);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
