import 'package:flutter/gestures.dart';

/// How much more horizontal than vertical a drag must be to switch tabs.
///
/// 2.0 keeps the swipe within ~27° of horizontal. Anything steeper is left to
/// the vertical scrollables underneath, which win the gesture arena once the
/// finger has moved far enough up or down.
const double kTabSwipeAxisRatio = 2.0;

/// A horizontal drag recognizer for tab swiping that only claims the pointer
/// when the movement is clearly sideways.
///
/// The stock [HorizontalDragGestureRecognizer] accepts as soon as the
/// horizontal component passes touch slop, so a diagonal scroll that drifts
/// sideways first gets taken over as a tab swipe. This one also looks at the
/// vertical component, both when competing in the arena and when the drag ends
/// (it can win by default when no scrollable is competing).
class TabSwipeGestureRecognizer extends HorizontalDragGestureRecognizer {
  TabSwipeGestureRecognizer({super.debugOwner});

  Offset _totalOffset = Offset.zero;

  /// Total movement since the pointer went down, in both axes.
  Offset get totalOffset => _totalOffset;

  /// Whether the drag so far is predominantly horizontal.
  bool get isMostlyHorizontal =>
      _totalOffset.dx.abs() >= _totalOffset.dy.abs() * kTabSwipeAxisRatio;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _totalOffset = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && !event.synthesized) {
      _totalOffset += event.localDelta;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return super.hasSufficientGlobalDistanceToAccept(
          pointerDeviceKind,
          deviceTouchSlop,
        ) &&
        isMostlyHorizontal;
  }
}
