import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Recognizes deliberate plan swipes while leaving vertical scrolling and
/// nested horizontal controls to their own gesture recognizers.
class PlanSwipeRegion extends StatefulWidget {
  final Widget child;

  /// The drag committed to the next plan. Called with the finger's release
  /// velocity in logical pixels per second, so content that followed the
  /// finger can carry on out at the speed the hand left it.
  final ValueChanged<double>? onNextPlan;

  /// The drag committed to the previous plan, with the release velocity.
  final ValueChanged<double>? onPreviousPlan;

  /// How far the finger has dragged since the drag was recognised, in
  /// logical pixels. The movement it took to tell a swipe from a scroll is
  /// left out, so content that follows the finger starts from where it is
  /// instead of jumping to catch up, as a page view does. Whether the drag
  /// switches plans is judged on the whole movement.
  final ValueChanged<double>? onDragProgress;

  /// The drag ended without changing plans. Called with the finger's release
  /// velocity in logical pixels per second (0 when the gesture was taken
  /// away), so content that followed the finger can settle carrying it.
  final ValueChanged<double>? onDragCancel;

  const PlanSwipeRegion({
    super.key,
    required this.child,
    this.onNextPlan,
    this.onPreviousPlan,
    this.onDragProgress,
    this.onDragCancel,
  });

  @override
  State<PlanSwipeRegion> createState() => _PlanSwipeRegionState();
}

class _PlanSwipeRegionState extends State<PlanSwipeRegion> {
  /// How far the finger has moved since it touched down.
  double _dragDistance = 0;

  /// [_dragDistance] when the drag was recognised.
  double? _recognisedAt;

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final isSwipe =
        _dragDistance.abs() > 40 ||
        (_dragDistance.abs() > kTouchSlop && velocity.abs() > 300);
    if (isSwipe) {
      if (_dragDistance < 0) {
        if (widget.onNextPlan != null) {
          widget.onNextPlan!(velocity);
        } else {
          widget.onDragCancel?.call(velocity);
        }
      } else {
        if (widget.onPreviousPlan != null) {
          widget.onPreviousPlan!(velocity);
        } else {
          widget.onDragCancel?.call(velocity);
        }
      }
    } else {
      widget.onDragCancel?.call(velocity);
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
                      _recognisedAt = null;
                    }
                    ..onUpdate = (details) {
                      _dragDistance += details.delta.dx;
                      // The first update carries the movement since touch
                      // down (DragStartBehavior.down), the slop included.
                      final recognisedAt = _recognisedAt ??= _dragDistance;
                      widget.onDragProgress?.call(_dragDistance - recognisedAt);
                    }
                    ..onEnd = _onDragEnd
                    ..onCancel = () {
                      _dragDistance = 0;
                      widget.onDragCancel?.call(0);
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
