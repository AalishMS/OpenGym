import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Recognizes deliberate plan swipes while leaving vertical scrolling and
/// nested horizontal controls to their own gesture recognizers.
class PlanSwipeRegion extends StatefulWidget {
  final Widget child;
  final VoidCallback? onNextPlan;
  final VoidCallback? onPreviousPlan;

  const PlanSwipeRegion({
    super.key,
    required this.child,
    this.onNextPlan,
    this.onPreviousPlan,
  });

  @override
  State<PlanSwipeRegion> createState() => _PlanSwipeRegionState();
}

class _PlanSwipeRegionState extends State<PlanSwipeRegion> {
  double _dragDistance = 0;

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final isSwipe =
        _dragDistance.abs() > 40 ||
        (_dragDistance.abs() > kTouchSlop && velocity.abs() > 300);
    if (isSwipe) {
      if (_dragDistance < 0) {
        widget.onNextPlan?.call();
      } else {
        widget.onPreviousPlan?.call();
      }
    }
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        if (widget.onNextPlan != null || widget.onPreviousPlan != null)
          _PlanDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_PlanDragGestureRecognizer>(
                () => _PlanDragGestureRecognizer(),
                (instance) {
                  instance
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onlyAcceptDragOnThreshold = true
                    ..onStart = (_) {
                      _dragDistance = 0;
                    }
                    ..onUpdate = (details) {
                      _dragDistance += details.delta.dx;
                    }
                    ..onEnd = _onDragEnd
                    ..onCancel = () {
                      _dragDistance = 0;
                    };
                },
              ),
      },
      child: widget.child,
    );
  }
}

class _PlanDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  int? _pointer;
  Offset _movement = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer == null) {
      _pointer = event.pointer;
      _movement = Offset.zero;
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && event.pointer == _pointer) {
      _movement += event.delta;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    // Check the angle before accepting: horizontal drag update callbacks have
    // already discarded dy, so they cannot disambiguate diagonal gestures.
    return _movement.dx.abs() > _movement.dy.abs() * 1.5 &&
        super.hasSufficientGlobalDistanceToAccept(
          pointerDeviceKind,
          deviceTouchSlop,
        );
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _pointer = null;
    _movement = Offset.zero;
  }
}
