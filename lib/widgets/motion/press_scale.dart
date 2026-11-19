import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/motion.dart';

/// Builds a tappable object, handing it the callback that reports when its
/// ink is pressed.
typedef PressScaleBuilder =
    Widget Function(
      BuildContext context,
      ValueChanged<bool> onHighlightChanged,
    );

/// A tappable *object* gives slightly under the finger: it eases to
/// [AppMotion.scale] while pressed and back when released.
///
/// Use it for things that stand forward and are picked up as a whole: a
/// raised card (`RaisedCard` already applies it), a large tile, a picker
/// card. Don't use it for list rows, text buttons or icon buttons; Material
/// ink is their touch response, and a row that shrinks reads as broken.
///
/// The press follows the object's own [InkWell]: pass `onHighlightChanged`
/// from [builder] to it. That keeps the give in step with the ripple (it
/// waits out a scroll's touch slop just as the ink does) and adds no gesture
/// recognizer, so it can't swallow a tap, a long press or a drag, and it
/// leaves semantics untouched. A disabled InkWell never highlights, so a
/// disabled object never gives. Under reduced motion it stays still.
///
/// ```dart
/// PressScale(
///   builder: (context, onHighlightChanged) => Material(
///     child: InkWell(
///       onTap: onOpen,
///       onHighlightChanged: onHighlightChanged,
///       child: content,
///     ),
///   ),
/// )
/// ```
class PressScale extends StatefulWidget {
  final PressScaleBuilder builder;

  /// Whether the object gives at all. Turning this off keeps the same widget
  /// tree, so an object that is sometimes a card and sometimes a plain row
  /// keeps its state as it changes.
  final bool enabled;

  const PressScale({super.key, required this.builder, this.enabled = true});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _onHighlightChanged(bool pressed) {
    if (pressed == _pressed || !mounted) return;
    // InkWell reports a press ending during a build when its handlers are
    // removed mid-press; wait for the frame rather than rebuild inside it.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && pressed != _pressed) setState(() => _pressed = pressed);
      });
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final give =
        _pressed && widget.enabled && !MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: give ? AppMotion.scale : 1,
      duration: AppMotion.quick,
      curve: AppMotion.curve,
      child: widget.builder(context, _onHighlightChanged),
    );
  }
}
