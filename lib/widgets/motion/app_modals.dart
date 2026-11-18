import 'package:flutter/material.dart';

import '../../theme/motion.dart';

// Every dialog and modal sheet in the app opens through these two functions,
// so all of them arrive and leave the same way. `test/motion_test.dart` fails
// if `lib/` calls `showDialog` or `showModalBottomSheet` directly.
//
// They take the same arguments as the Material functions they wrap and return
// the same result; only the animation differs. Neither the dialog theme nor
// the bottom sheet theme can carry an animation in this SDK, which is why
// these exist.

/// A dialog fades in while it settles from [AppMotion.scale] to full size over
/// [AppMotion.standard] on [AppMotion.curve], and leaves with a plain fade on
/// [AppMotion.exit]. Material's own dialog is a 150ms fade either way.
///
/// `showDialog` takes one duration for both directions, so the departure is
/// shorter in effect rather than in time: the exit curve clears most of the
/// dialog in the first half. The dialog takes taps from its first frame, and
/// once it starts to leave, taps pass through to the page. Under reduced
/// motion it appears and disappears at once.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => _DialogArrival(child: builder(dialogContext)),
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle:
        MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
              duration: AppMotion.standard,
              curve: AppMotion.curve,
              reverseCurve: AppMotion.exit,
            ),
  );
}

/// A modal bottom sheet keeps the platform's slide up from the bottom edge,
/// on the app's timing: it rises over [AppMotion.enter] on [AppMotion.curve]
/// and drops away over [AppMotion.standard] on [AppMotion.exit]. Material's
/// own is 250ms in and 200ms out on its legacy decelerate curve. Dragging it
/// still follows the finger. Under reduced motion it appears and disappears
/// at once.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  // Material's own default, which it keeps private.
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
    sheetAnimationStyle: appSheetAnimationStyle(context),
  );
}

/// The sheet timing [showAppSheet] uses, for a sheet pushed as its own
/// [ModalBottomSheetRoute] (pass it as `sheetAnimationStyle`).
AnimationStyle appSheetAnimationStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
          duration: AppMotion.enter,
          reverseDuration: AppMotion.standard,
          curve: AppMotion.curve,
          reverseCurve: AppMotion.exit,
        );

/// Settles the dialog from [AppMotion.scale] to full size as its route
/// arrives. The route's own fade carries the rest; leaving, the scale holds
/// at full size so the departure is a plain fade.
class _DialogArrival extends StatelessWidget {
  final Widget child;

  const _DialogArrival({required this.child});

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    return _ArrivalScale(animation: animation, child: child);
  }
}

class _ArrivalScale extends AnimatedWidget {
  final Widget child;

  const _ArrivalScale({
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final settled =
        animation.status == AnimationStatus.reverse
            ? 1.0
            : AppMotion.curve.transform(animation.value);
    return Transform.scale(
      scale: AppMotion.scale + (1 - AppMotion.scale) * settled,
      child: child,
    );
  }
}
