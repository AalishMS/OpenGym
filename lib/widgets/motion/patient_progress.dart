import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../theme/motion.dart';

/// Shows a progress indicator only for work that is still going after
/// [AppMotion.patience]: the *feedback* of a wait that is real.
///
/// Most saves, sign-in checks and local loads finish within a frame or two,
/// and an indicator that appeared and vanished that fast would only flicker,
/// or shove the page if it takes room. So [child] waits unpainted for
/// [AppMotion.patience] and is revealed only if the work is still in flight:
/// faded in over [AppMotion.quick] in place, or, with [fold], folded open as
/// a region over [AppMotion.standard] like `Collapsible`, moving what is
/// below it. Work that ends before then leaves no trace.
///
/// Pass the progress as [child] while the work is in flight and null once it
/// is done. Leaving, it keeps showing the last progress it had (so a label
/// doesn't change on its way out), fades or folds away on [AppMotion.exit],
/// and takes no taps, focus or semantics from the moment the work ends. Work
/// that resumes while it leaves brings it straight back.
///
/// The child is in the tree from the moment the work starts, so finders and
/// tests see it at once. Faded in place it is in the semantics tree from the
/// start too, so a screen reader hears the progress label at once while only
/// the painting waits; folded, it takes no room until it opens, and the
/// framework drops a node with no size, so it is announced as it opens. Until
/// it is revealed it takes no taps. Under reduced motion it still waits, then
/// appears and goes without motion.
class PatientProgress extends StatefulWidget {
  /// Whether it opens as a region that takes room, rather than fading in
  /// over what is already there.
  final bool fold;

  /// The progress to show while work is in flight; null when there is none.
  final Widget? child;

  const PatientProgress({super.key, this.fold = false, required this.child});

  @override
  State<PatientProgress> createState() => _PatientProgressState();
}

class _PatientProgressState extends State<PatientProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _shown = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
    reverseCurve: AppMotion.exit,
  );
  Timer? _wait;

  /// The progress on show: the latest while the work runs, the last one
  /// while it leaves, and null once it has gone.
  late Widget? _progress = widget.child;

  Duration get _duration => widget.fold ? AppMotion.standard : AppMotion.quick;

  bool get _busy => widget.child != null;

  @override
  void initState() {
    super.initState();
    if (_busy) _wait = Timer(AppMotion.patience, _reveal);
  }

  void _reveal() {
    _wait = null;
    if (!mounted || !_busy) return;
    _controller.duration = AppMotion.of(context, _duration);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (!mounted) return;
    // Taps follow whether it can be seen, and once it has gone the last
    // progress goes with it.
    setState(() {
      if (status.isDismissed && !_busy) _progress = null;
    });
  }

  @override
  void didUpdateWidget(PatientProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_busy) _progress = widget.child;
    if (_busy == (oldWidget.child != null)) return;
    _controller.duration = AppMotion.of(context, _duration);
    if (_busy) {
      if (_controller.isDismissed) {
        _wait?.cancel();
        _wait = Timer(AppMotion.patience, _reveal);
      } else {
        // Work resumed while it was leaving: it stays.
        _controller.forward();
      }
    } else {
      _wait?.cancel();
      _wait = null;
      if (_controller.isDismissed) {
        // Done before it was worth showing: it leaves without a trace.
        _progress = null;
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _shown.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return const SizedBox.shrink();
    final leaving = !_busy;
    Widget shown = IgnorePointer(
      ignoring: leaving || _controller.isDismissed,
      child: ExcludeFocus(
        excluding: leaving,
        child: ExcludeSemantics(
          excluding: leaving,
          child: FadeTransition(
            opacity: _shown,
            alwaysIncludeSemantics: !leaving,
            child: progress,
          ),
        ),
      ),
    );
    if (widget.fold) {
      shown = ClipRect(
        child: SizeTransition(
          sizeFactor: _shown,
          alignment: AlignmentDirectional.topStart,
          child: shown,
        ),
      );
    }
    return shown;
  }
}
