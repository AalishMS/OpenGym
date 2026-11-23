import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/haptics.dart';
import '../rolling_figure.dart';
import 'set_entry_table.dart';

/// An exercise as the folded log shows it while one is being moved.
@immutable
class ExerciseReorderItem {
  final String name;

  /// What trails the name, such as the number of sets.
  final String detail;

  const ExerciseReorderItem({required this.name, required this.detail});
}

/// Lets the exercises in [child] be put in a new order by holding an
/// exercise's name ([ExerciseReorderHold]) and dragging it.
///
/// The held exercise doesn't carry its card. A card is often taller than the
/// screen: dragged whole, it changes places in uneven jumps and runs the list
/// away whenever it touches an edge. Instead the log folds to one short row
/// per exercise, all the same height. The held row rises under the finger, the
/// others step aside one row at a time as it passes, and pushing it against
/// the top or bottom scrolls the rows at a pace that grows with the push. Let
/// go, the row settles onto its exercise's title in the log, which is scrolled
/// so the exercise lands where it was dropped.
class ExerciseReorderScope extends StatefulWidget {
  /// The exercises, in the order the log shows them.
  final List<ExerciseReorderItem> items;

  /// Moves the exercise at `from` so it ends up at `to`.
  final void Function(int from, int to) onReorder;

  final Widget child;

  const ExerciseReorderScope({
    super.key,
    required this.items,
    required this.onReorder,
    required this.child,
  });

  @override
  State<ExerciseReorderScope> createState() => _ExerciseReorderScopeState();
}

enum _Phase { idle, dragging, placing }

class _ExerciseReorderScopeState extends State<ExerciseReorderScope>
    with TickerProviderStateMixin {
  /// The log folding into rows: each row travels from its card's title to
  /// its place in the list as the page closes over the cards.
  late final AnimationController _folded = AnimationController(vsync: this);

  /// The page over the log, which covers the cards well before the rows
  /// have finished gathering.
  late final Animation<double> _shown = CurvedAnimation(
    parent: _folded,
    curve: const Interval(0, 0.6, curve: AppMotion.curve),
    reverseCurve: AppMotion.exit,
  );

  /// How far the held row has risen off the page.
  late final AnimationController _lift = AnimationController(vsync: this);
  late final Animation<double> _lifted = CurvedAnimation(
    parent: _lift,
    curve: AppMotion.curve,
    reverseCurve: AppMotion.exit,
  );

  /// Carries every row from its place in the list onto its exercise's title
  /// in the reordered log, the held row from where it was let go.
  late final AnimationController _place = AnimationController(vsync: this);

  /// Scrolls the rows while the held row is pushed against an edge.
  late final Ticker _scroller = createTicker(_scroll);
  Duration? _lastTick;

  /// The built titles that can pick an exercise up, by index.
  final Map<int, _ExerciseReorderHoldState> _holds = {};

  _Phase _phase = _Phase.idle;
  _ExerciseReorderHoldState? _holder;

  /// [ExerciseReorderScope.items] as they were when the exercise was picked
  /// up, so a rebuild mid-drag can't change what the rows show.
  List<ExerciseReorderItem> _items = const [];
  int _from = 0;
  int _to = 0;

  /// One folded row's height; every row has the same.
  double _row = 56;

  /// The rows' inset from either side, so their names sit where the log's
  /// titles do.
  double _inset = AppSpacing.lg;

  /// Where the first row's top sits. The rows scroll by moving it.
  double _origin = 0;

  /// The finger's height in this widget, and its distance below the top of
  /// the held row, which stays fixed for the drag.
  double _finger = 0;
  double _grab = 0;

  /// Where the held row is drawn while dragged.
  double _heldTop = 0;

  /// Held-row tops past which the rows scroll up or down. A row picked up
  /// near an edge moves them only once it is pushed further that way, so the
  /// order never changes under a finger that hasn't moved.
  double _scrollUpBelow = 0;
  double _scrollDownAbove = 0;

  /// Where each of the other rows comes from as the log folds, and where it
  /// goes as it unfolds: its exercise's title, or past the edge it lies
  /// beyond. By index in [_items].
  Map<int, double> _foldFrom = const {};
  Map<int, double> _landAt = const {};

  /// The held row's travel once let go.
  double _landFrom = 0;
  double _landTo = 0;

  /// The log has been scrolled to the dropped exercise.
  bool _aligned = false;

  /// Screens the log has been moved looking for a card that wasn't built.
  int _seeking = 0;

  @override
  void didUpdateWidget(ExerciseReorderScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The workout changed under the drag (another device's sync, say): the
    // held index may no longer name the same exercise, so put it back.
    if (_phase == _Phase.dragging && !_itemsUnchanged) {
      _finish(commit: false);
    }
  }

  @override
  void dispose() {
    _scroller.dispose();
    _folded.dispose();
    _lift.dispose();
    _place.dispose();
    super.dispose();
  }

  bool get _itemsUnchanged =>
      widget.items.length == _items.length &&
      widget.items[_from].name == _items[_from].name;

  double get _extent => context.size?.height ?? 0;

  void _register(_ExerciseReorderHoldState hold, int index) {
    if (hold.widget.anchor) _holds[index] = hold;
  }

  void _unregister(_ExerciseReorderHoldState hold, int index) {
    if (_holds[index] == hold) _holds.remove(index);
  }

  /// The title that picked the exercise up is gone, and its gesture with it.
  void _released(_ExerciseReorderHoldState hold) {
    if (_holder != hold || _phase != _Phase.dragging) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _holder == hold) _finish(commit: false);
    });
  }

  void _start(_ExerciseReorderHoldState hold, Offset position) {
    if (_phase != _Phase.idle || widget.items.length < 2) return;
    final from = hold.widget.index;
    final box = context.findRenderObject() as RenderBox?;
    // Held by its note or its name, the row rises from the name.
    final title =
        (_holds[from] ?? hold).context.findRenderObject() as RenderBox?;
    if (from >= widget.items.length ||
        box == null ||
        title == null ||
        !box.hasSize ||
        !title.hasSize) {
      return;
    }
    // Picking an exercise up finishes any entry, as a tap elsewhere would.
    SetEntryTable.closeKeypad();
    final style = Theme.of(context).textTheme.titleLarge!;
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 17) *
        (style.height ?? 1.35);
    final rect = MatrixUtils.transformRect(
      title.getTransformTo(box),
      Offset.zero & title.size,
    );
    final extent = box.size.height;
    setState(() {
      _phase = _Phase.dragging;
      _holder = hold;
      _items = List.of(widget.items);
      _from = _to = from;
      _row = math.max(56, line + AppSpacing.md * 2);
      _inset = rect.left;
      // The held row starts over the title, and the rest gather round it.
      _heldTop = (rect.center.dy - _row / 2).clamp(
        0,
        math.max(0, extent - _row),
      );
      _finger = box.globalToLocal(position).dy;
      _grab = _finger - _heldTop;
      _origin = _heldTop - from * _row;
      _scrollUpBelow = math.min(_row, _heldTop);
      _scrollDownAbove = math.max(extent - _row * 2, _heldTop);
      _foldFrom = {
        for (var index = 0; index < _items.length; index++)
          if (index != from)
            index: _awayTop(index, index, above: index < from, box: box),
      };
      _landAt = const {};
    });
    Haptics.lift();
    _folded.duration = AppMotion.of(context, AppMotion.standard);
    _lift.duration = AppMotion.of(context, AppMotion.quick);
    _folded.forward();
    _lift.forward();
  }

  /// Where the row drawn in [slot] stands outside the folded list: over the
  /// title of the card at [index] when that card is built, otherwise just
  /// past the edge it lies beyond.
  double _awayTop(
    int index,
    int slot, {
    required bool above,
    required RenderBox box,
  }) {
    final title = _holds[index]?.context.findRenderObject() as RenderBox?;
    if (title != null && title.attached && title.hasSize) {
      return MatrixUtils.transformPoint(
            title.getTransformTo(box),
            title.size.center(Offset.zero),
          ).dy -
          _row / 2;
    }
    final resting = _origin + slot * _row;
    return above
        ? math.min(resting, -_row)
        : math.max(resting, box.size.height);
  }

  void _update(_ExerciseReorderHoldState hold, Offset position) {
    if (_phase != _Phase.dragging || hold != _holder) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    setState(() {
      _finger = box.globalToLocal(position).dy;
      _follow();
    });
  }

  void _finishFor(_ExerciseReorderHoldState hold, {required bool commit}) {
    if (hold == _holder) _finish(commit: commit);
  }

  /// Places the held row under the finger and works out the slot it is over.
  void _follow() {
    final extent = _extent;
    final top = _finger - _grab;
    // Once the row has been carried clear of an edge, that edge scrolls as
    // soon as the row comes back within a row of it.
    if (top >= _row) _scrollUpBelow = _row;
    if (top <= extent - _row * 2) _scrollDownAbove = extent - _row * 2;
    _heldTop = top.clamp(0, math.max(0, extent - _row));
    // Every row is the same height, so the order changes at fixed lines: as
    // the held row's middle crosses into a slot, it takes it.
    _to = ((_heldTop + _row / 2 - _origin) / _row).floor().clamp(
      0,
      _items.length - 1,
    );
    if (_scrollVelocity() != 0 && !_scroller.isActive) {
      _lastTick = null;
      _scroller.start();
    }
  }

  /// How fast the rows scroll, in pixels a second; positive brings the rows
  /// above into view. It grows with how far past the edge line the held row
  /// is pushed, slowly at first so a nudge moves one row at a time.
  double _scrollVelocity() {
    // A finger held still still wanders a few pixels; that alone never
    // scrolls.
    const slack = 4.0;
    final top = _finger - _grab;
    final fastest = _row * 10;
    final up = _scrollUpBelow - slack - top;
    if (up > 0 && _origin < 0) {
      final push = (up / _row).clamp(0.0, 1.0);
      return fastest * push * push;
    }
    final down = top - _scrollDownAbove - slack;
    if (down > 0 && _origin + _items.length * _row > _extent) {
      final push = (down / _row).clamp(0.0, 1.0);
      return -fastest * push * push;
    }
    return 0;
  }

  void _scroll(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    final velocity = _phase == _Phase.dragging ? _scrollVelocity() : 0.0;
    if (velocity == 0) {
      _scroller.stop();
      return;
    }
    if (last == null) return;
    final seconds =
        (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
    final distance = velocity * seconds;
    setState(() {
      _origin =
          velocity > 0
              ? math.min(0, _origin + distance)
              : math.max(_extent - _items.length * _row, _origin + distance);
      _follow();
    });
  }

  void _finish({required bool commit}) {
    if (_phase != _Phase.dragging) return;
    _scroller.stop();
    final from = _from;
    final to = commit && _itemsUnchanged ? _to : from;
    setState(() {
      _phase = _Phase.placing;
      _to = to;
      _landFrom = _landTo = _heldTop;
      _aligned = false;
      _seeking = 0;
    });
    _place.value = 0;
    if (to != from) {
      Haptics.selection();
      widget.onReorder(from, to);
    }
    // The log under the rows rebuilds in its new order first.
    SchedulerBinding.instance.addPostFrameCallback((_) => _reveal());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Scrolls the log so the dropped exercise's title sits where its row is,
  /// then lands the held row on that title.
  void _reveal() {
    if (!mounted || _phase != _Phase.placing) return;
    final box = context.findRenderObject() as RenderBox?;
    final slot = _origin + _to * _row + _row / 2;
    final hold = _holds[_to];
    final title = hold?.context.findRenderObject() as RenderBox?;
    if (box != null && hold != null && title != null && title.hasSize) {
      final center =
          MatrixUtils.transformPoint(
            title.getTransformTo(box),
            title.size.center(Offset.zero),
          ).dy;
      final position = Scrollable.maybeOf(hold.context)?.position;
      if (!_aligned && position != null && position.hasContentDimensions) {
        _aligned = true;
        final target = (position.pixels + center - slot).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((target - position.pixels).abs() >= 0.5) {
          position.jumpTo(target);
          _again();
          return;
        }
      }
      _land(center);
      return;
    }
    // Its card isn't built, being far from what's on screen: move the log a
    // screen towards it and look again. The rows still cover the log.
    final position =
        _holds.isEmpty
            ? null
            : Scrollable.maybeOf(_holds.values.first.context)?.position;
    if (position != null && position.hasContentDimensions && _seeking++ < 12) {
      final below = _holds.keys.every((index) => index < _to);
      final above = _holds.keys.every((index) => index > _to);
      if (below || above) {
        final target = (position.pixels +
                position.viewportDimension * (below ? 1 : -1))
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (target != position.pixels) {
          position.jumpTo(target);
          _again();
          return;
        }
      }
    }
    _land(slot);
  }

  void _again() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _reveal());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _land(double center) {
    final box = context.findRenderObject() as RenderBox?;
    final built = _holds.keys;
    final firstBuilt = built.isEmpty ? 0 : built.reduce(math.min);
    setState(() {
      _landFrom = _heldTop;
      _landTo = center - _row / 2;
      _landAt = {
        if (box != null)
          for (var index = 0; index < _items.length; index++)
            if (index != _from)
              index: _awayTop(
                _slotOf(index),
                _slotOf(index),
                above: _slotOf(index) < firstBuilt,
                box: box,
              ),
      };
    });
    final duration = AppMotion.of(context, AppMotion.standard);
    _place.duration = duration;
    _lift.reverseDuration = duration;
    _folded.reverseDuration = duration;
    _lift.reverse();
    _folded.reverse();
    _place.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || _phase != _Phase.placing) return;
      setState(() {
        _phase = _Phase.idle;
        _holder = null;
        _items = const [];
      });
    });
  }

  /// The slot row [index] is drawn in while the held row is over [_to].
  int _slotOf(int index) {
    if (_from < _to && index > _from && index <= _to) return index - 1;
    if (_to < _from && index >= _to && index < _from) return index + 1;
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final active = _phase != _Phase.idle;
    return _ReorderScopeMarker(
      state: this,
      enabled: widget.items.length > 1,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          ExcludeSemantics(excluding: active, child: widget.child),
          if (active)
            Positioned.fill(
              key: const ValueKey('exercise-reorder'),
              // Once let go, taps reach the log as the rows fade from it.
              child: IgnorePointer(
                ignoring: _phase == _Phase.placing,
                child: ExcludeSemantics(child: _buildFolded(context)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFolded(BuildContext context) {
    final duration = AppMotion.of(context, AppMotion.standard);
    final page = backgroundColor(context);
    final hairline = hairlineColor(context);
    // Complete, so the column is measured with what the figure inherits.
    final number = DefaultTextStyle.of(
      context,
    ).style.merge(_numberStyle(context));
    // Wide enough for the longest number, so the names line up.
    final measure = TextPainter(
      text: TextSpan(text: '${_items.length}.', style: number),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final numberWidth = measure.width.ceilToDouble() + AppSpacing.sm;
    measure.dispose();
    return AnimatedBuilder(
      animation: Listenable.merge([_folded, _lift, _place]),
      builder: (context, _) {
        final shown = _shown.value;
        final placing = _phase == _Phase.placing;
        final folding = AppMotion.move.transform(_folded.value);
        final landing = AppMotion.move.transform(_place.value);
        // The numbers open a column before the names as the log folds, and
        // close it as the names land back on their titles.
        final numbered = placing ? 1 - landing : folding;
        Widget content(ExerciseReorderItem item, int place) => _RowContent(
          item: item,
          place: place,
          numberStyle: number,
          numberWidth: numberWidth,
          numbered: numbered,
          detailOpacity: shown,
        );
        // A row at rest in the list, or on its way between the list and a
        // title in the log.
        double travel(double resting, double? away) {
          if (away == null) return resting;
          return placing
              ? lerpDouble(resting, away, landing)!
              : lerpDouble(away, resting, folding)!;
        }

        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Color.lerp(page.withAlpha(0), page, shown)!,
                ),
              ),
              for (var index = 0; index < _items.length; index++)
                if (index != _from)
                  TweenAnimationBuilder<double>(
                    key: ValueKey(index),
                    tween: Tween(end: _slotOf(index).toDouble()),
                    duration: duration,
                    curve: AppMotion.move,
                    builder:
                        (context, slot, child) => Positioned(
                          top: travel(
                            _origin + slot * _row,
                            placing ? _landAt[index] : _foldFrom[index],
                          ),
                          left: _inset,
                          right: _inset,
                          height: _row,
                          child: child!,
                        ),
                    // The name is the title it came from; the rule and the
                    // detail belong to the list, and come and go with it.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color:
                                Color.lerp(
                                  hairline.withAlpha(0),
                                  hairline,
                                  shown,
                                )!,
                          ),
                        ),
                      ),
                      child: content(_items[index], _slotOf(index) + 1),
                    ),
                  ),
              Positioned(
                top:
                    placing
                        ? lerpDouble(_landFrom, _landTo, landing)
                        : _heldTop,
                left: _inset - AppSpacing.sm,
                right: _inset - AppSpacing.sm,
                height: _row,
                child: _HeldRow(
                  lift: _lifted.value,
                  child: content(_items[_from], _to + 1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

TextStyle _numberStyle(BuildContext context) {
  final name = Theme.of(context).textTheme.titleLarge!;
  return AppTypography.figures(
    fontSize: name.fontSize,
    fontWeight: name.fontWeight,
    height: name.height,
    color: textSecondaryColor(context),
  );
}

class _ReorderScopeMarker extends InheritedWidget {
  final _ExerciseReorderScopeState state;

  /// There is more than one exercise to put in order.
  final bool enabled;

  const _ReorderScopeMarker({
    required this.state,
    required this.enabled,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ReorderScopeMarker oldWidget) =>
      state != oldWidget.state || enabled != oldWidget.enabled;
}

/// Part of an exercise, its name or its note, which picks the exercise at
/// [index] up when held inside an [ExerciseReorderScope].
///
/// There is no handle to show the gesture: a tap explains it, and moving an
/// exercise from its menu mentions it once.
class ExerciseReorderHold extends StatefulWidget {
  final int index;

  /// Whether this is the exercise's name, which the folded row rises from
  /// and lands back on. Its other parts pick it up too, from the name.
  final bool anchor;
  final Widget child;

  const ExerciseReorderHold({
    super.key,
    required this.index,
    this.anchor = true,
    required this.child,
  });

  @override
  State<ExerciseReorderHold> createState() => _ExerciseReorderHoldState();
}

class _ExerciseReorderHoldState extends State<ExerciseReorderHold> {
  _ExerciseReorderScopeState? _scope;
  bool _enabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final marker =
        context.dependOnInheritedWidgetOfExactType<_ReorderScopeMarker>();
    _enabled = marker?.enabled ?? false;
    final scope = marker?.state;
    if (scope == _scope) return;
    _scope?._unregister(this, widget.index);
    _scope = scope;
    _scope?._register(this, widget.index);
  }

  @override
  void didUpdateWidget(ExerciseReorderHold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index && oldWidget.anchor == widget.anchor) {
      return;
    }
    _scope?._unregister(this, oldWidget.index);
    _scope?._register(this, widget.index);
  }

  @override
  void dispose() {
    _scope?._unregister(this, widget.index);
    _scope?._released(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    if (scope == null || !_enabled) return widget.child;
    return Tooltip(
      message: 'Hold and drag to reorder',
      // A tap is how the gesture is found; the hold itself belongs to it.
      triggerMode: TooltipTriggerMode.tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Screen readers move exercises from the exercise menu.
        excludeFromSemantics: true,
        onLongPressStart:
            (details) => scope._start(this, details.globalPosition),
        onLongPressMoveUpdate:
            (details) => scope._update(this, details.globalPosition),
        onLongPressEnd: (_) => scope._finishFor(this, commit: true),
        onLongPressCancel: () => scope._finishFor(this, commit: false),
        child: widget.child,
      ),
    );
  }
}

/// A folded exercise: its place in the order, its name, and its detail at
/// the trailing edge.
class _RowContent extends StatelessWidget {
  final ExerciseReorderItem item;

  /// The place it will take, counting from 1. It rolls to a new number as
  /// the row moves.
  final int place;
  final TextStyle numberStyle;
  final double numberWidth;

  /// How far the number column has opened: 0 puts the name where its title
  /// is in the log.
  final double numbered;

  /// The detail's opacity, so it shows only while the log is folded.
  final double detailOpacity;

  const _RowContent({
    required this.item,
    required this.place,
    required this.numberStyle,
    required this.numberWidth,
    required this.numbered,
    required this.detailOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        ClipRect(
          child: SizedBox(
            width: numberWidth * numbered,
            child: OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              minWidth: numberWidth,
              maxWidth: numberWidth,
              child: Opacity(
                opacity: numbered,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                  child: RollingFigure(
                    '$place.',
                    style: numberStyle,
                    maxLines: 1,
                    alignment: AlignmentDirectional.centerEnd,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            item.name,
            style: textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Opacity(
          opacity: detailOpacity,
          child: Text(
            item.detail,
            style: textTheme.bodySmall?.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// The exercise being moved. It starts as its title in the log, rises onto
/// the raised ground as it lifts, and sinks back into the page as it lands.
class _HeldRow extends StatelessWidget {
  /// 0 resting in the page, 1 lifted.
  final double lift;
  final Widget child;

  const _HeldRow({required this.lift, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = surfaceColor(context);
    final hairline = hairlineColor(context);
    return Transform.scale(
      scale: 1 + 0.025 * lift,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(surface.withAlpha(0), surface, lift),
          borderRadius: AppRadius.card,
          // Dark mode raises with an edge, as a raised card does; a shadow
          // has nothing to fall on there.
          border:
              dark
                  ? Border.all(
                    color: Color.lerp(hairline.withAlpha(0), hairline, lift)!,
                  )
                  : null,
          boxShadow: [
            if (!dark)
              BoxShadow(
                color: Theme.of(
                  context,
                ).shadowColor.withAlpha((45 * lift).round()),
                blurRadius: 20 * lift,
                offset: Offset(0, 6 * lift),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: child,
        ),
      ),
    );
  }
}
