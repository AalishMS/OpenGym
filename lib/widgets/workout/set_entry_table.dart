import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/semantic_colors.dart';
import '../readable_table_viewport.dart';

/// A display snapshot. Editing it never mutates a session or a plan implicitly.
class SetEntry {
  final double weight;
  final int reps;
  final String? previous;
  final String? annotation;
  final int? rpe;

  const SetEntry({
    required this.weight,
    required this.reps,
    this.previous,
    this.annotation,
    this.rpe,
  });

  bool get isPrMarker {
    final note = annotation?.trim().toLowerCase().replaceAll(
      RegExp(r'[.!]+$'),
      '',
    );
    return note == 'pr' || note == 'new pr' || note == 'pr attempt';
  }
}

String entryWeight(double weight) =>
    weight.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

enum _SetField { weight, reps, rpe }

/// Marks the value fields so a tap on one re-targets the open keypad instead of
/// dismissing it.
const Object _kValueField = Object();

Widget _valueFieldTarget(Widget child) => MetaData(
  metaData: _kValueField,
  behavior: HitTestBehavior.translucent,
  child: child,
);

const double _kSetNumberWidth = 32;
const double _kColumnGap = 8;
const int _kPreviousFlex = 6;
const int _kWeightFlex = 5;
const int _kRepsFlex = 4;
const int _kRpeFlex = 4;

double _numberWidth(BuildContext context, bool numberIsAction) => [
  numberIsAction ? 48.0 : _kSetNumberWidth,
  readableTextWidth(context, 'Set', Theme.of(context).textTheme.titleSmall!),
  readableTextWidth(context, '999', Theme.of(context).textTheme.titleMedium!),
  readableTextWidth(
        context,
        'PR',
        Theme.of(
          context,
        ).textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w700),
      ) +
      8,
].reduce(math.max);

double _detailsWidth(BuildContext context) => math.max(
  48,
  readableTextWidth(context, '@10', Theme.of(context).textTheme.labelLarge!) +
      16,
);

double _minimumTableWidth(
  BuildContext context,
  List<SetEntry> sets, {
  required bool showHistoryColumns,
  required bool showPrevious,
  required bool showRpe,
  required bool numberIsAction,
  required bool trailing,
}) {
  final valueStyle = Theme.of(context).textTheme.titleLarge!.copyWith(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  double widest(Iterable<String> values, TextStyle style) => values.fold(
    48,
    (width, value) =>
        math.max(width, readableTextWidth(context, value, style) + 16),
  );
  final weight = widest([
    '999.99',
    ...sets.map((set) => entryWeight(set.weight)),
  ], valueStyle);
  final reps = widest(['999', ...sets.map((set) => '${set.reps}')], valueStyle);
  final previous = widest(
    ['Previous', ...sets.map((set) => set.previous ?? '—')],
    Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 16,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  final rpe = widest(['@10', 'RPE'], Theme.of(context).textTheme.labelLarge!);
  final unit = [
    weight / _kWeightFlex,
    reps / (showRpe ? _kRepsFlex : _kWeightFlex),
    if (showRpe) rpe / _kRpeFlex,
    if (showHistoryColumns && showPrevious) previous / _kPreviousFlex,
  ].reduce(math.max);
  final flex =
      _kWeightFlex +
      (showRpe ? _kRepsFlex + _kRpeFlex : _kWeightFlex) +
      (showHistoryColumns && showPrevious ? _kPreviousFlex : 0);
  return unit * flex +
      (showHistoryColumns
          ? _numberWidth(context, numberIsAction) + _kColumnGap
          : 0) +
      (showHistoryColumns && showPrevious ? _kColumnGap : 0) +
      _kColumnGap * (showRpe ? 2 : 1) +
      (trailing ? _detailsWidth(context) : 0);
}

double _rpeColumnWidth(
  BuildContext context,
  double width, {
  bool showHistoryColumns = true,
  bool showPrevious = true,
  bool numberIsAction = false,
  bool trailing = false,
}) {
  final historyWidth =
      showHistoryColumns
          ? _numberWidth(context, numberIsAction) +
              _kColumnGap +
              (showPrevious ? _kColumnGap : 0)
          : 0;
  final flexibleWidth =
      width -
      historyWidth -
      2 * _kColumnGap -
      (trailing ? _detailsWidth(context) : 0);
  final flex =
      _kWeightFlex +
      _kRepsFlex +
      _kRpeFlex +
      (showHistoryColumns && showPrevious ? _kPreviousFlex : 0);
  final rpeWidth = flexibleWidth * _kRpeFlex / flex;
  return rpeWidth < 48 ? 48 : rpeWidth;
}

/// An exercise heading whose action is centered over the log's RPE column.
class SetEntryHeading extends StatelessWidget {
  final Widget title;
  final Widget action;

  const SetEntryHeading({super.key, required this.title, required this.action});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rpeWidth = _rpeColumnWidth(context, constraints.maxWidth);
      return Row(
        children: [
          Expanded(child: title),
          SizedBox(width: rpeWidth, height: 48, child: Center(child: action)),
        ],
      );
    },
  );
}

/// Shared by prescribed sets, live sets, and the set detail dialogs.
class SetEntryTable extends StatefulWidget {
  static final ValueNotifier<double> _keyboardHeight = ValueNotifier(0);

  /// Space needed at the end of a workout list to reveal its last set.
  static ValueListenable<double> get keyboardHeight => _keyboardHeight;

  final List<SetEntry> sets;
  final void Function(int index, double weight, int reps) onChanged;
  final void Function(int index, int? rpe)? onRpeChanged;
  final ValueChanged<int>? onDetails;
  final ValueChanged<int>? onDelete;
  final VoidCallback? onEntryFinished;
  final bool showHistoryColumns;
  final bool showPrevious;
  final bool continuousLog;

  /// The host list adds [keyboardHeight] below its content, so the table does
  /// not pad itself. Without it the padding sits inside the table's card.
  final bool hostReservesSpace;

  const SetEntryTable({
    super.key,
    required this.sets,
    required this.onChanged,
    this.onRpeChanged,
    this.onDetails,
    this.onDelete,
    this.onEntryFinished,
    this.showHistoryColumns = true,
    this.showPrevious = true,
    this.continuousLog = false,
    this.hostReservesSpace = false,
  });

  @override
  State<SetEntryTable> createState() => _SetEntryTableState();
}

class _SetEntryTableState extends State<SetEntryTable> {
  static _SetEntryTableState? _activeKeyboard;
  final _keyboardKey = GlobalKey<_SetKeyboardState>();
  OverlayEntry? _overlay;
  OverlayEntry? _dismissOverlay;
  Offset? _tapStart;
  int? _tapPointer;
  LocalHistoryEntry? _history;
  bool _changed = false;
  bool _disposing = false;
  final Map<int, GlobalKey> _rowKeys = {};
  List<SetEntry> get sets => widget.sets;
  void Function(int, double, int) get onChanged => widget.onChanged;
  void Function(int, int?)? get onRpeChanged => widget.onRpeChanged;
  ValueChanged<int>? get onDetails => widget.onDetails;
  ValueChanged<int>? get onDelete => widget.onDelete;
  bool get continuousLog => widget.continuousLog;
  bool get _hostReserves => widget.continuousLog || widget.hostReservesSpace;
  bool get showHistoryColumns => widget.showHistoryColumns;

  double get _keyboardSpace =>
      _keypadSheetHeight(Overlay.of(context).context) + 12;

  void _close() => _history?.remove();

  @override
  void didUpdateWidget(SetEntryTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keyboard = _keyboardKey.currentState;
    if (keyboard == null) return;
    if (keyboard.widget.sets.length != sets.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    } else if (!identical(oldWidget.sets, sets)) {
      keyboard.widget.sets.setAll(0, sets);
    }
  }

  void _removeKeyboard() {
    if (_activeKeyboard == this) {
      _activeKeyboard = null;
      // Row disposal can happen while the workout list is building.
      if (_disposing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_activeKeyboard == null) SetEntryTable._keyboardHeight.value = 0;
        });
      } else {
        SetEntryTable._keyboardHeight.value = 0;
      }
    }
    _removeOverlays();
    _history = null;
    if (mounted && !_disposing) {
      setState(() {});
      if (_changed) widget.onEntryFinished?.call();
    }
  }

  void _removeOverlays() {
    for (final entry in [_dismissOverlay, _overlay]) {
      entry?.remove();
      entry?.dispose();
    }
    _dismissOverlay = null;
    _overlay = null;
  }

  // A tap is a pointer that goes down and up without travelling. It closes the
  // keypad unless it landed on a value field, which re-targets the keypad. The
  // listener is translucent and never claims a gesture, so the tap still
  // reaches whatever was underneath it and scrolling is unaffected.
  void _trackPointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        _tapPointer = _tapPointer == null ? event.pointer : -1;
        _tapStart = _tapPointer == event.pointer ? event.position : null;
      case PointerMoveEvent():
        if (event.pointer == _tapPointer &&
            _tapStart != null &&
            (event.position - _tapStart!).distance > kTouchSlop) {
          _tapStart = null;
        }
      case PointerUpEvent():
        final start = _tapStart;
        final wasTap = event.pointer == _tapPointer && start != null;
        if (event.pointer == _tapPointer || _tapPointer == -1) {
          _tapPointer = null;
          _tapStart = null;
        }
        // Deferred until the tap itself has been handled, so a target that
        // pops the route (toolbar Back) still finds the keypad to dismiss
        // first, as it always has.
        if (wasTap && !_hitsValueField(event.position)) {
          scheduleMicrotask(_close);
        }
      default:
        _tapPointer = null;
        _tapStart = null;
    }
  }

  bool _hitsValueField(Offset position) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      position,
      View.of(context).viewId,
    );
    return result.path.any((entry) {
      final target = entry.target;
      return target is RenderMetaData && target.metaData == _kValueField;
    });
  }

  @override
  void dispose() {
    _disposing = true;
    // Remove the overlay before its owning row disappears.
    _removeOverlays();
    _history?.remove();
    super.dispose();
  }

  void _open(BuildContext context, int index, _SetField field) {
    if (_overlay != null) {
      _keyboardKey.currentState?._select(index, field);
      return;
    }
    _activeKeyboard?._close();
    _activeKeyboard = this;
    SetEntryTable._keyboardHeight.value = _hostReserves ? _keyboardSpace : 0;
    FocusManager.instance.primaryFocus?.unfocus();
    _changed = false;
    _history = LocalHistoryEntry(onRemove: _removeKeyboard);
    ModalRoute.of(context)!.addLocalHistoryEntry(_history!);
    _dismissOverlay = OverlayEntry(
      builder:
          (_) => Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _trackPointer,
              onPointerMove: _trackPointer,
              onPointerUp: _trackPointer,
              onPointerCancel: _trackPointer,
            ),
          ),
    );
    _overlay = OverlayEntry(
      builder:
          (overlayContext) => Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Theme(
              data: Theme.of(context),
              // Slides up once on open; switching fields reuses the sheet.
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: 0),
                duration:
                    MediaQuery.disableAnimationsOf(overlayContext)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder:
                    (_, offset, child) => FractionalTranslation(
                      translation: Offset(0, offset),
                      child: child,
                    ),
                child: BottomSheet(
                  onClosing: _close,
                  backgroundColor: _keypadTrayColor(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.sheet,
                    side: BorderSide(color: borderColor(context)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  enableDrag: false,
                  builder:
                      (_) => _SetKeyboard(
                        key: _keyboardKey,
                        sets: List.of(sets),
                        initialIndex: index,
                        initialField: field,
                        onClose: _close,
                        onEditingChanged: () {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        onSelectionChanged: _revealRow,
                        onChanged: (index, weight, reps) {
                          _changed = true;
                          onChanged(index, weight, reps);
                        },
                        onRpeChanged:
                            onRpeChanged == null
                                ? null
                                : (index, rpe) {
                                  _changed = true;
                                  onRpeChanged!(index, rpe);
                                },
                      ),
                ),
              ),
            ),
          ),
    );
    Overlay.of(context).insertAll([_dismissOverlay!, _overlay!]);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlay != null) {
        _keyboardKey.currentState?._keyboardFocus.requestFocus();
        setState(() {});
        _revealRow(index);
      }
    });
  }

  void _revealRow(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _rowKeys[index]?.currentContext;
      if (!mounted || _overlay == null || rowContext == null) return;
      final box = rowContext.findRenderObject() as RenderBox?;
      final keyboardBox =
          _keyboardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || keyboardBox == null) return;
      final top = box.localToGlobal(Offset.zero).dy;
      // Measure where the sheet settles, not where its slide-in currently is.
      final overlayBox =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (overlayBox == null) return;
      final keyboardTop =
          overlayBox.localToGlobal(Offset(0, overlayBox.size.height)).dy -
          keyboardBox.size.height;
      // The editor nests a shrink-wrapped reorder list inside the page scroll.
      // Skip disabled and horizontal viewports to reach the one that can move.
      rowContext.visitAncestorElements((element) {
        if (element is! StatefulElement || element.state is! ScrollableState) {
          return true;
        }
        final scrollable = element.state as ScrollableState;
        final position = scrollable.position;
        if (axisDirectionToAxis(position.axisDirection) != Axis.vertical ||
            !position.physics.allowImplicitScrolling) {
          return true;
        }
        final viewport =
            position.context.notificationContext?.findRenderObject()
                as RenderBox?;
        if (viewport == null) return true;
        final viewportTop = viewport.localToGlobal(Offset.zero).dy;
        final available =
            math.min(keyboardTop, viewportTop + viewport.size.height) - 12;
        final delta =
            top < viewportTop + 12
                ? top - viewportTop - 12
                : math.max(0.0, top + box.size.height - available);
        final target = (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((target - position.pixels).abs() > .5) {
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
        return false;
      });
    });
  }

  Future<void> _showDelete(
    BuildContext context,
    int index, {
    Offset? position,
  }) async {
    _close();
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final row = context.findRenderObject()! as RenderBox;
    final anchor = overlay.globalToLocal(
      position ?? row.localToGlobal(row.size.center(Offset.zero)),
    );
    final delete = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: true,
          height: 48,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 18, color: errorColor(context)),
              const SizedBox(width: AppSpacing.sm),
              Text('Delete set', style: TextStyle(color: errorColor(context))),
            ],
          ),
        ),
      ],
    );
    if (delete == true && context.mounted) onDelete?.call(index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final numberIsAction = onDetails != null && onDelete != null;
      final showTrailing =
          onDetails != null || (onDelete != null && !continuousLog);
      final showPrevious =
          widget.showPrevious &&
          (!numberIsAction ||
              constraints.maxWidth >=
                  400 * MediaQuery.textScalerOf(context).scale(1));
      final table = Column(
        children: [
          _EntryHeader(
            trailing: showTrailing,
            showHistoryColumns: showHistoryColumns,
            showRpe: onRpeChanged != null,
            numberIsAction: numberIsAction,
            showPrevious: showPrevious,
            continuousLog: continuousLog,
          ),
          for (var index = 0; index < sets.length; index++)
            Padding(
              padding: EdgeInsets.only(bottom: continuousLog ? 4 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder:
                        (rowContext) => Semantics(
                          container: continuousLog && onDelete != null,
                          label:
                              continuousLog && onDelete != null
                                  ? 'Set ${index + 1} actions'
                                  : null,
                          customSemanticsActions:
                              continuousLog && onDelete != null
                                  ? {
                                    const CustomSemanticsAction(
                                          label: 'Delete set',
                                        ):
                                        () => _showDelete(rowContext, index),
                                  }
                                  : null,
                          child: GestureDetector(
                            key: ValueKey('set_entry_row_$index'),
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart:
                                continuousLog && onDelete != null
                                    ? (details) => _showDelete(
                                      rowContext,
                                      index,
                                      position: details.globalPosition,
                                    )
                                    : null,
                            child: _EntryRow(
                              key: _rowKeys.putIfAbsent(
                                index,
                                () => GlobalKey(),
                              ),
                              showHistoryColumns: showHistoryColumns,
                              showPrevious: showPrevious,
                              continuousLog: continuousLog,
                              index: index,
                              editing:
                                  _overlay == null
                                      ? null
                                      : _keyboardKey.currentState,
                              previous: sets[index].previous,
                              weight: entryWeight(sets[index].weight),
                              reps: '${sets[index].reps}',
                              rpe: sets[index].rpe,
                              isPrMarker: sets[index].isPrMarker,
                              onDetails:
                                  onDetails != null && onDelete != null
                                      ? () {
                                        _close();
                                        onDetails!(index);
                                      }
                                      : null,
                              onWeight:
                                  () => _open(context, index, _SetField.weight),
                              onReps:
                                  () => _open(context, index, _SetField.reps),
                              onRpe:
                                  onRpeChanged == null
                                      ? null
                                      : () =>
                                          _open(context, index, _SetField.rpe),
                              trailing:
                                  showTrailing
                                      ? Semantics(
                                        label:
                                            onDelete != null
                                                ? 'Delete set'
                                                : 'Set details',
                                        button: true,
                                        container: true,
                                        excludeSemantics: true,
                                        onTap:
                                            () =>
                                                (onDelete ?? onDetails)!(index),
                                        child: IconButton(
                                          iconSize: 32,
                                          tooltip:
                                              onDelete != null
                                                  ? 'Delete set'
                                                  : 'Set details',
                                          onPressed:
                                              () => (onDelete ?? onDetails)!(
                                                index,
                                              ),
                                          icon:
                                              onDelete == null &&
                                                      sets[index].rpe != null
                                                  ? _effort(
                                                    context,
                                                    sets[index].rpe!,
                                                  )
                                                  : Icon(
                                                    onDelete != null
                                                        ? Icons.close
                                                        : Icons.more_horiz,
                                                    size: 18,
                                                    color:
                                                        onDelete != null
                                                            ? errorColor(
                                                              context,
                                                            )
                                                            : textSecondaryColor(
                                                              context,
                                                            ),
                                                  ),
                                        ),
                                      )
                                      : null,
                            ),
                          ),
                        ),
                  ),
                  if ((sets[index].annotation?.trim().isNotEmpty ?? false) &&
                      !sets[index].isPrMarker)
                    Padding(
                      padding: const EdgeInsets.only(left: 40, top: 6),
                      child: Text(
                        sets[index].annotation!,
                        style: _quiet(context),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
      // Workout rows use the card's existing column geometry. A horizontal
      // viewport would widen them and compete with plan navigation swipes.
      final bottom = _overlay == null || _hostReserves ? 0.0 : _keyboardSpace;
      if (continuousLog) {
        return table;
      }
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: ReadableTableViewport(
          minimumWidth: _minimumTableWidth(
            context,
            sets,
            showHistoryColumns: showHistoryColumns,
            showPrevious: showPrevious,
            showRpe: onRpeChanged != null,
            numberIsAction: numberIsAction,
            trailing: showTrailing,
          ),
          child: table,
        ),
      );
    },
  );
}

TextStyle _quiet(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: textSecondaryColor(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

Widget _effort(BuildContext context, int rpe) => Semantics(
  label: 'RPE $rpe',
  excludeSemantics: true,
  child: Text(
    '@$rpe',
    maxLines: 1,
    softWrap: false,
    style: Theme.of(context).textTheme.labelLarge!.copyWith(
      fontWeight: FontWeight.w700,
      color: rpeColor(rpe, context),
    ),
  ),
);

/// Header and data share the exact same column geometry at every width.
Widget _columns(
  List<Widget> cells, {
  Widget? trailing,
  bool showHistoryColumns = true,
  bool showRpe = false,
  bool numberIsAction = false,
  bool showPrevious = true,
}) => LayoutBuilder(
  builder:
      (context, constraints) => Row(
        children: [
          if (showHistoryColumns) ...[
            SizedBox(
              width: _numberWidth(context, numberIsAction),
              child: cells[0],
            ),
            const SizedBox(width: _kColumnGap),
            if (showPrevious) ...[
              Expanded(flex: _kPreviousFlex, child: cells[1]),
              const SizedBox(width: _kColumnGap),
            ],
          ],
          Expanded(flex: _kWeightFlex, child: cells[2]),
          const SizedBox(width: _kColumnGap),
          Expanded(flex: showRpe ? _kRepsFlex : _kWeightFlex, child: cells[3]),
          if (showRpe) ...[
            const SizedBox(width: _kColumnGap),
            SizedBox(
              width: _rpeColumnWidth(
                context,
                constraints.maxWidth,
                showHistoryColumns: showHistoryColumns,
                showPrevious: showPrevious,
                numberIsAction: numberIsAction,
                trailing: trailing != null,
              ),
              child: cells[4],
            ),
          ],
          if (trailing != null)
            SizedBox(width: _detailsWidth(context), child: trailing),
        ],
      ),
);

class _EntryHeader extends StatelessWidget {
  final bool trailing;
  final bool showHistoryColumns;
  final bool showRpe;
  final bool numberIsAction;
  final bool showPrevious;
  final bool continuousLog;
  const _EntryHeader({
    this.trailing = false,
    this.showHistoryColumns = true,
    this.showRpe = false,
    this.numberIsAction = false,
    this.showPrevious = true,
    this.continuousLog = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _columns(
      [
        for (final label in [
          'Set',
          continuousLog ? 'Previous' : 'Prev',
          'Kg',
          'Reps',
          if (showRpe) 'RPE',
        ])
          Text(
            label,
            textAlign: TextAlign.center,
            style: (continuousLog
                    ? Theme.of(context).textTheme.labelMedium!
                    : Theme.of(context).textTheme.titleSmall!)
                .copyWith(
                  fontWeight: continuousLog ? FontWeight.w400 : null,
                  color: textSecondaryColor(context),
                ),
          ),
      ],
      trailing: trailing ? const SizedBox() : null,
      showHistoryColumns: showHistoryColumns,
      showRpe: showRpe,
      numberIsAction: numberIsAction,
      showPrevious: showPrevious,
    ),
  );
}

class _EntryRow extends StatelessWidget {
  final int index;
  final _SetKeyboardState? editing;
  final String? previous;
  final String weight;
  final String reps;
  final int? rpe;
  final bool isPrMarker;
  final VoidCallback? onDetails;
  final VoidCallback onWeight;
  final VoidCallback onReps;
  final VoidCallback? onRpe;
  final Widget? trailing;
  final bool showHistoryColumns;
  final bool showPrevious;
  final bool continuousLog;

  const _EntryRow({
    super.key,
    required this.index,
    this.editing,
    this.previous,
    required this.weight,
    required this.reps,
    this.rpe,
    this.isPrMarker = false,
    this.onDetails,
    required this.onWeight,
    required this.onReps,
    this.onRpe,
    this.trailing,
    this.showHistoryColumns = true,
    this.showPrevious = true,
    this.continuousLog = false,
  });

  @override
  Widget build(BuildContext context) => _columns(
    [
      _setNumber(context),
      Semantics(
        label: 'Previous set ${index + 1}: ${previous ?? 'no history'}',
        child: Text(
          previous ?? '—',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: continuousLog ? 13 : 16,
            fontWeight: continuousLog ? FontWeight.w400 : FontWeight.w600,
            color: textSecondaryColor(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      _valueFieldTarget(
        _field(context, weight, 'Kg', onWeight, _SetField.weight),
      ),
      _valueFieldTarget(_field(context, reps, 'Reps', onReps, _SetField.reps)),
      if (onRpe != null) _valueFieldTarget(_rpeReadout(context)),
    ],
    trailing: trailing,
    showHistoryColumns: showHistoryColumns,
    showRpe: onRpe != null,
    numberIsAction: onDetails != null,
    showPrevious: showPrevious,
  );

  Widget _setNumber(BuildContext context) {
    final number = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${index + 1}',
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
            fontWeight: continuousLog ? FontWeight.w400 : FontWeight.w700,
            color: continuousLog ? textSecondaryColor(context) : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (isPrMarker) ...[
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label: 'Personal record',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: accentFillColor(context),
                borderRadius: AppRadius.badge,
              ),
              child: Text(
                'PR',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: onAccentColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    if (onDetails == null) return Center(child: number);
    return Semantics(
      label: 'Set ${index + 1} details${isPrMarker ? ', personal record' : ''}',
      button: true,
      excludeSemantics: true,
      onTap: onDetails,
      child: Tooltip(
        message: 'Set ${index + 1} details',
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.control,
          child: InkWell(
            borderRadius: AppRadius.control,
            onTap: onDetails,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                border: Border.all(color: borderColor(context)),
                borderRadius: AppRadius.control,
              ),
              child: Center(child: number),
            ),
          ),
        ),
      ),
    );
  }

  bool _active(_SetField field) =>
      editing?._index == index && editing?._field == field;

  Widget _rpeReadout(BuildContext context) {
    if (_active(_SetField.rpe)) {
      return _field(context, editing!._input, 'RPE', onRpe!, _SetField.rpe);
    }
    final value =
        continuousLog ? '${rpe ?? '—'}' : (rpe == null ? '@—' : '@$rpe');
    return Semantics(
      label:
          rpe == null
              ? 'Set ${index + 1} RPE value, not set'
              : 'Set ${index + 1} RPE value $rpe',
      value: value,
      button: true,
      container: true,
      excludeSemantics: true,
      onTap: onRpe,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.field,
        child: InkWell(
          onTap: onRpe,
          borderRadius: AppRadius.field,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child:
                  continuousLog || rpe == null
                      ? Text(
                        value,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          fontWeight:
                              continuousLog ? FontWeight.w400 : FontWeight.w700,
                          color: textSecondaryColor(context),
                        ),
                      )
                      : _effort(context, rpe!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String value,
    String label,
    VoidCallback onTap,
    _SetField field,
  ) => Semantics(
    label: 'Set ${index + 1} $label',
    container: true,
    excludeSemantics: true,
    onTap: onTap,
    value:
        _active(field)
            ? (field == _SetField.rpe
                ? (editing!._input.isEmpty
                    ? 'Not set'
                    : '${editing!._input} out of 10')
                : '${editing!._input.isEmpty ? '0' : editing!._input} ${field == _SetField.weight ? 'kilograms' : 'repetitions'}')
            : value,
    selected: _active(field),
    liveRegion: _active(field),
    button: true,
    child: Material(
      color: Colors.transparent,
      borderRadius: AppRadius.field,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.field,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.all(AppSpacing.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  continuousLog
                      ? surfaceColor(context)
                      : backgroundColor(context),
              border:
                  continuousLog
                      ? null
                      : Border.all(color: borderColor(context)),
              borderRadius: AppRadius.field,
            ),
            child: _EntryValue(
              value: _active(field) ? editing!._input : value,
              active: _active(field),
              selected: _active(field) && editing!._replace,
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontSize: continuousLog ? 18 : 20,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.bold,
                color: textPrimaryColor(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SetKeyboard extends StatefulWidget {
  final List<SetEntry> sets;
  final int initialIndex;
  final _SetField initialField;
  final VoidCallback onClose;
  final VoidCallback onEditingChanged;
  final ValueChanged<int> onSelectionChanged;
  final void Function(int, double, int) onChanged;
  final void Function(int, int?)? onRpeChanged;

  const _SetKeyboard({
    super.key,
    required this.sets,
    required this.initialIndex,
    required this.initialField,
    required this.onClose,
    required this.onEditingChanged,
    required this.onSelectionChanged,
    required this.onChanged,
    this.onRpeChanged,
  });

  @override
  State<_SetKeyboard> createState() => _SetKeyboardState();
}

class _SetKeyboardState extends State<_SetKeyboard> {
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'Set numeric entry');
  late int _index = widget.initialIndex;
  late _SetField _field = widget.initialField;
  late String _input = _value;
  bool _replace = true;

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_hasNext) {
        _next();
      } else {
        widget.onClose();
      }
    } else if (key == LogicalKeyboardKey.backspace) {
      _type('delete');
    } else if (key == LogicalKeyboardKey.delete) {
      _clear();
    } else {
      final digit =
          {
            LogicalKeyboardKey.numpad0: '0',
            LogicalKeyboardKey.numpad1: '1',
            LogicalKeyboardKey.numpad2: '2',
            LogicalKeyboardKey.numpad3: '3',
            LogicalKeyboardKey.numpad4: '4',
            LogicalKeyboardKey.numpad5: '5',
            LogicalKeyboardKey.numpad6: '6',
            LogicalKeyboardKey.numpad7: '7',
            LogicalKeyboardKey.numpad8: '8',
            LogicalKeyboardKey.numpad9: '9',
            LogicalKeyboardKey.numpadDecimal: '.',
          }[key] ??
          event.character ??
          key.keyLabel;
      if (!RegExp(r'^[0-9.]$').hasMatch(digit)) return KeyEventResult.ignored;
      _type(digit);
    }
    return KeyEventResult.handled;
  }

  SetEntry get _set => widget.sets[_index];
  String get _value => switch (_field) {
    _SetField.weight => entryWeight(_set.weight),
    _SetField.reps => '${_set.reps}',
    _SetField.rpe => _set.rpe?.toString() ?? '',
  };

  void _select(int index, _SetField field) => setState(() {
    _index = index;
    _field = field;
    _input = _value;
    _replace = true;
    _keyboardFocus.requestFocus();
    widget.onEditingChanged();
    widget.onSelectionChanged(index);
  });

  void _publish() {
    // Clearing weight or reps sets it to zero. Clearing RPE removes the
    // optional value. Reps and RPE are always integral.
    final value = double.tryParse(_input) ?? 0;
    final updated = SetEntry(
      weight: _field == _SetField.weight ? value : _set.weight,
      reps: _field == _SetField.reps ? value.toInt() : _set.reps,
      previous: _set.previous,
      annotation: _set.annotation,
      rpe:
          _field == _SetField.rpe
              ? (_input.isEmpty ? null : value.toInt())
              : _set.rpe,
    );
    widget.sets[_index] = updated;
    if (_field == _SetField.rpe) {
      widget.onRpeChanged?.call(_index, updated.rpe);
    } else {
      widget.onChanged(_index, updated.weight, updated.reps);
    }
    widget.onEditingChanged();
  }

  void _type(String key) => setState(() {
    if (key == '.' && _field != _SetField.weight) return;
    var next = _replace ? '' : _input;
    if (key == 'delete') {
      next =
          _replace || _input.isEmpty
              ? ''
              : _input.substring(0, _input.length - 1);
    } else if (key == '.') {
      if (next.contains('.')) return;
      next = next.isEmpty ? '0.' : '$next.';
    } else {
      next = next == '0' ? key : '$next$key';
    }
    final value = double.tryParse(next) ?? 0;
    if (_field == _SetField.rpe) {
      if (key != 'delete' && (value < 1 || value > 10)) return;
    } else if (next.length > 6 || value > 999) {
      return;
    }
    if (next.contains('.') && next.split('.').last.length > 2) return;
    _input = next;
    _replace = false;
    _publish();
  });

  void _clear() => setState(() {
    _input = '';
    _replace = true;
    _publish();
  });

  void _adjust(double delta) => setState(() {
    if (_field == _SetField.rpe ||
        (_field == _SetField.reps && delta.abs() != 1)) {
      return;
    }
    if (_field == _SetField.weight) {
      _input = entryWeight((_set.weight + delta).clamp(0, 999).toDouble());
    } else {
      _input = (_set.reps + delta.toInt()).clamp(0, 999).toString();
    }
    _replace = true;
    _publish();
  });

  void _next() {
    if (_field == _SetField.weight) {
      _select(_index, _SetField.reps);
    } else if (_index + 1 < widget.sets.length) {
      _select(_index + 1, _SetField.weight);
    }
  }

  bool get _hasNext =>
      _field == _SetField.weight || _index + 1 < widget.sets.length;

  void _copy() {
    if (_index + 1 >= widget.sets.length) return;
    final source = _set;
    final target = widget.sets[_index + 1];
    widget.sets[_index + 1] = SetEntry(
      weight: source.weight,
      reps: source.reps,
      rpe: source.rpe,
      previous: target.previous,
      annotation: target.annotation,
    );
    widget.onChanged(_index + 1, source.weight, source.reps);
    widget.onRpeChanged?.call(_index + 1, source.rpe);
    _select(_index + 1, _SetField.weight);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _keyboardFocus,
    autofocus: true,
    onKeyEvent: _handleKey,
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyHeight = _keyHeight(context);
          final minimumKeyWidth = math.max(
            48.0,
            readableTextWidth(
                  context,
                  '−2.5',
                  Theme.of(context).textTheme.labelLarge!,
                ) +
                8,
          );
          final width = math.max(
            math.min(constraints.maxWidth, 680.0),
            5 * minimumKeyWidth + 4 * _kKeyGap + 2 * _kKeypadPadding,
          );
          final screen = MediaQuery.sizeOf(context).height;
          final bottom = MediaQuery.paddingOf(context).bottom;
          return SizedBox(
            height: math.min(_keypadHeight(context), screen * .6 - bottom),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Center(
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          _header(context),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              _kKeypadPadding,
                              0,
                              _kKeypadPadding,
                              _kKeypadPadding,
                            ),
                            child: _grid(context, keyHeight),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  String get _fieldLabel => switch (_field) {
    _SetField.weight => 'Weight (kg)',
    _SetField.reps => 'Reps',
    _SetField.rpe => 'RPE (1–10)',
  };

  /// Names what the keys are editing, plus the one action that targets
  /// another set and so reads better as a sentence than as a key.
  Widget _header(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!;
    final hasNextSet = _index + 1 < widget.sets.length;
    return SizedBox(
      height: _headerHeight(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.xs, 0),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Set ${_index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: textPrimaryColor(context),
                      ),
                    ),
                    TextSpan(text: '  ·  $_fieldLabel'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: textSecondaryColor(context)),
              ),
            ),
            if (hasNextSet)
              TextButton.icon(
                onPressed: _withHaptic(_copy),
                style: TextButton.styleFrom(
                  foregroundColor: accentColor(context),
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.button,
                  ),
                  textStyle: style.copyWith(fontWeight: FontWeight.w600),
                ),
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: Text('Copy to set ${_index + 2}'),
              ),
          ],
        ),
      ),
    );
  }

  /// Five equal columns: adjustments, three digit columns, then actions. The
  /// action column spans rows so the key pressed most after typing, Next, is
  /// also the largest one.
  Widget _grid(BuildContext context, double keyHeight) {
    double span(int rows) => rows * keyHeight + (rows - 1) * _kKeyGap;
    Widget column(List<(int, Widget)> keys) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(height: _kKeyGap),
            SizedBox(height: span(keys[i].$1), child: keys[i].$2),
          ],
        ],
      ),
    );
    final hasRpe = widget.onRpeChanged != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        column([
          for (final (label, delta) in const [
            ('+2.5', 2.5),
            ('−2.5', -2.5),
            ('+1', 1.0),
            ('−1', -1.0),
          ])
            (1, _incrementKey(context, label: label, delta: delta)),
        ]),
        for (final keys in const [
          ['1', '4', '7', '.'],
          ['2', '5', '8', '0'],
          ['3', '6', '9', 'delete'],
        ]) ...[
          const SizedBox(width: _kKeyGap),
          column([for (final key in keys) (1, _digitKey(context, key))]),
        ],
        const SizedBox(width: _kKeyGap),
        column([
          if (hasRpe)
            (
              1,
              _key(
                context,
                tone:
                    _field == _SetField.rpe
                        ? _KeyTone.selected
                        : _KeyTone.action,
                onPressed: () => _select(_index, _SetField.rpe),
                child: const _KeyLabel('RPE'),
              ),
            ),
          (
            hasRpe ? 2 : 3,
            _key(
              context,
              tone: _KeyTone.primary,
              onPressed: _hasNext ? _next : widget.onClose,
              child: _KeyLabel(_hasNext ? 'Next' : 'Done'),
            ),
          ),
          (
            1,
            Semantics(
              label: 'Hide keypad',
              button: true,
              excludeSemantics: true,
              onTap: widget.onClose,
              child: _key(
                context,
                tone: _KeyTone.action,
                onPressed: widget.onClose,
                child: const Icon(Icons.keyboard_hide_outlined, size: 22),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  bool _adjustmentEnabled(double delta) => switch (_field) {
    _SetField.weight => true,
    _SetField.reps => delta.abs() == 1,
    _SetField.rpe => false,
  };

  Widget _incrementKey(
    BuildContext context, {
    required String label,
    required double delta,
  }) {
    final enabled = _adjustmentEnabled(delta);
    final emphasized =
        enabled &&
        ((_field == _SetField.weight && delta.abs() == 2.5) ||
            (_field == _SetField.reps && delta.abs() == 1));
    final unit = _field == _SetField.reps ? 'reps' : 'kilograms';
    return Semantics(
      label: '$label $unit',
      child: _key(
        context,
        tone: emphasized ? _KeyTone.emphasized : _KeyTone.action,
        onPressed: enabled ? () => _adjust(delta) : null,
        child: Text(label),
      ),
    );
  }

  Widget _digitKey(BuildContext context, String key) {
    final isDelete = key == 'delete';
    final enabled = key != '.' || _field == _SetField.weight;
    return Semantics(
      label: isDelete ? 'Delete digit' : null,
      hint: isDelete ? 'Long press to clear' : null,
      child: _key(
        context,
        tone: _KeyTone.digit,
        onPressed: enabled ? () => _type(key) : null,
        onLongPress: isDelete ? _clear : null,
        child:
            isDelete
                ? const Icon(Icons.backspace_outlined, size: 22)
                : Text(key),
      ),
    );
  }

  VoidCallback? _withHaptic(VoidCallback? action) =>
      action == null
          ? null
          : () {
            HapticFeedback.selectionClick();
            action();
          };

  Widget _key(
    BuildContext context, {
    required _KeyTone tone,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    required Widget child,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final (ground, ink) = switch (tone) {
      _KeyTone.primary => (accentFillColor(context), onAccentColor(context)),
      _KeyTone.selected => (
        accentMutedColor(context),
        textPrimaryColor(context),
      ),
      _KeyTone.emphasized => (
        raisedSurfaceColor(context),
        accentColor(context),
      ),
      _KeyTone.digit || _KeyTone.action => (
        raisedSurfaceColor(context),
        textPrimaryColor(context),
      ),
    };
    return TextButton(
      onPressed: _withHaptic(onPressed),
      onLongPress:
          onLongPress == null
              ? null
              : () {
                HapticFeedback.mediumImpact();
                onLongPress();
              },
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: ground,
        foregroundColor: ink,
        // A disabled key sinks into the tray instead of fading in place.
        disabledBackgroundColor: _keypadTrayColor(context),
        disabledForegroundColor: textSecondaryColor(context),
        side:
            onPressed == null
                ? BorderSide(color: borderColor(context))
                : BorderSide.none,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        textStyle:
            tone == _KeyTone.digit
                ? textTheme.headlineSmall!.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )
                : textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
      ),
      child: child,
    );
  }
}

enum _KeyTone { digit, action, emphasized, selected, primary }

/// The keys always sit one step above the tray: dark mode puts surface keys on
/// the black page ground, light mode puts near-white keys on a grey surface.
Color _keypadTrayColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? backgroundColor(context)
        : surfaceColor(context);

/// Action labels stay on one line; at extreme text sizes they shrink to fit
/// the key rather than breaking a word in half.
class _KeyLabel extends StatelessWidget {
  final String text;
  const _KeyLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    ),
  );
}

const double _kKeyGap = 6;
const double _kKeypadPadding = 8;

/// Keys are wider than tall on a phone; they grow with short screens' floor of
/// 48dp and with the text scale so a scaled label never clips.
double _keyHeight(BuildContext context) => math.max(
  (MediaQuery.sizeOf(context).height * .065).clamp(48.0, 56.0),
  MediaQuery.textScalerOf(context).scale(24) + 24,
);

double _headerHeight(BuildContext context) =>
    math.max(44.0, MediaQuery.textScalerOf(context).scale(14) + 30);

double _keypadHeight(BuildContext context) =>
    _headerHeight(context) +
    4 * _keyHeight(context) +
    3 * _kKeyGap +
    _kKeypadPadding;

/// The whole sheet, bottom safe area included: what a list has to leave free.
double _keypadSheetHeight(BuildContext context) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  return math.min(
        _keypadHeight(context),
        MediaQuery.sizeOf(context).height * .6 - bottom,
      ) +
      bottom;
}

/// Selection and cursor stay in the original row while the custom keyboard edits.
class _EntryValue extends StatefulWidget {
  final String value;
  final bool active;
  final bool selected;
  final TextStyle style;
  const _EntryValue({
    required this.value,
    required this.active,
    required this.selected,
    required this.style,
  });
  @override
  State<_EntryValue> createState() => _EntryValueState();
}

class _EntryValueState extends State<_EntryValue> {
  Timer? _timer;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    _updateCursor();
  }

  @override
  void didUpdateWidget(_EntryValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.value != widget.value) {
      _updateCursor();
    }
  }

  void _updateCursor() {
    _timer?.cancel();
    _visible = true;
    if (widget.active && widget.value.isEmpty) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() => _visible = !_visible);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active && widget.value.isEmpty) {
      return SizedBox(
        width: 2,
        height: widget.style.fontSize ?? 20,
        child: ColoredBox(
          color: _visible ? accentColor(context) : Colors.transparent,
        ),
      );
    }
    return Text(
      widget.value.isEmpty ? '—' : widget.value,
      softWrap: false,
      style: widget.style.copyWith(
        backgroundColor: widget.selected ? accentMutedColor(context) : null,
      ),
    );
  }
}
