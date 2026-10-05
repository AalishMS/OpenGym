import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
  final List<SetEntry> sets;
  final void Function(int index, double weight, int reps) onChanged;
  final void Function(int index, int? rpe)? onRpeChanged;
  final ValueChanged<int>? onDetails;
  final ValueChanged<int>? onDelete;
  final VoidCallback? onEntryFinished;
  final bool showHistoryColumns;
  final bool continuousLog;

  const SetEntryTable({
    super.key,
    required this.sets,
    required this.onChanged,
    this.onRpeChanged,
    this.onDetails,
    this.onDelete,
    this.onEntryFinished,
    this.showHistoryColumns = true,
    this.continuousLog = false,
  });

  @override
  State<SetEntryTable> createState() => _SetEntryTableState();
}

class _SetEntryTableState extends State<SetEntryTable> {
  static _SetEntryTableState? _activeKeyboard;
  final _keyboardKey = GlobalKey<_SetKeyboardState>();
  OverlayEntry? _overlay;
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
  bool get showHistoryColumns => widget.showHistoryColumns;

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
    if (_activeKeyboard == this) _activeKeyboard = null;
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
    _history = null;
    if (mounted && !_disposing) {
      setState(() {});
      if (_changed) widget.onEntryFinished?.call();
    }
  }

  @override
  void dispose() {
    _disposing = true;
    // Remove the overlay before its owning row disappears.
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
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
    FocusManager.instance.primaryFocus?.unfocus();
    _changed = false;
    _history = LocalHistoryEntry(onRemove: _removeKeyboard);
    ModalRoute.of(context)!.addLocalHistoryEntry(_history!);
    _overlay = OverlayEntry(
      builder:
          (overlayContext) => Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Theme(
              data: Theme.of(context),
              child: BottomSheet(
                onClosing: _close,
                backgroundColor: surfaceColor(context),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.sheet,
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
                          _revealRow(_keyboardKey.currentState!._index);
                        }
                      },
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
    );
    Overlay.of(context).insert(_overlay!);
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
      final scrollable = Scrollable.maybeOf(rowContext, axis: Axis.vertical);
      if (box == null || scrollable == null) return;
      final screen = MediaQuery.sizeOf(context).height;
      final top = box.localToGlobal(Offset.zero).dy;
      final available = screen - math.max(232.0, screen * .35) - 12;
      final delta =
          top < 80
              ? top - 80
              : math.max(0.0, top + box.size.height - available);
      final position = scrollable.position;
      position.animateTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
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
          !numberIsAction ||
          constraints.maxWidth >=
              400 * MediaQuery.textScalerOf(context).scale(1);
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
      final bottom =
          _overlay == null
              ? 0.0
              : math.max(232.0, MediaQuery.sizeOf(context).height * .35);
      if (continuousLog) {
        return Padding(padding: EdgeInsets.only(bottom: bottom), child: table);
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
      _field(context, weight, 'Kg', onWeight, _SetField.weight),
      _field(context, reps, 'Reps', onReps, _SetField.reps),
      if (onRpe != null) _rpeReadout(context),
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
  final void Function(int, double, int) onChanged;
  final void Function(int, int?)? onRpeChanged;

  const _SetKeyboard({
    super.key,
    required this.sets,
    required this.initialIndex,
    required this.initialField,
    required this.onClose,
    required this.onEditingChanged,
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
      setState(() {
        _input = '';
        _replace = true;
        _publish();
      });
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
          // Four rows, with 48dp targets as the floor on short displays.
          final height = math.max(
            232.0,
            MediaQuery.sizeOf(context).height * .35 -
                MediaQuery.paddingOf(context).bottom,
          );
          final keyHeight = math.max(48.0, (height - 40) / 4);
          final keyWidth = math.max(
            48.0,
            readableTextWidth(
                  context,
                  '−2.5',
                  Theme.of(context).textTheme.labelLarge!,
                ) +
                8,
          );
          final width = 5 * keyWidth + 40;
          return SizedBox(
            height: height,
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(math.min(constraints.maxWidth, 680), width),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        for (var row = 0; row < 4; row++) ...[
                          if (row > 0) const SizedBox(height: 8),
                          SizedBox(
                            height: keyHeight,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _incrementKey(
                                    context,
                                    label:
                                        const ['+2.5', '−2.5', '+1', '−1'][row],
                                    delta: const [2.5, -2.5, 1.0, -1.0][row],
                                  ),
                                ),
                                for (final key
                                    in const [
                                      ['1', '2', '3'],
                                      ['4', '5', '6'],
                                      ['7', '8', '9'],
                                      ['.', '0', 'delete'],
                                    ][row]) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: _digitKey(
                                      context,
                                      key,
                                      height: keyHeight,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _actionKey(
                                    context,
                                    label:
                                        const [
                                          'RPE',
                                          'Copy',
                                          'Next',
                                          'Save',
                                        ][row],
                                    onTap: switch (row) {
                                      0 =>
                                        widget.onRpeChanged == null
                                            ? null
                                            : () =>
                                                _select(_index, _SetField.rpe),
                                      1 =>
                                        _index + 1 < widget.sets.length
                                            ? _copy
                                            : null,
                                      2 => _hasNext ? _next : null,
                                      _ => widget.onClose,
                                    },
                                    filled: row == 3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: OutlinedButton(
          onPressed: enabled ? () => _adjust(delta) : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            foregroundColor:
                emphasized ? accentColor(context) : textPrimaryColor(context),
            disabledForegroundColor: textSecondaryColor(context),
            side: BorderSide(
              color: emphasized ? accentColor(context) : borderColor(context),
              width: emphasized ? 2 : 1,
            ),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _digitKey(BuildContext context, String key, {required double height}) {
    final isDelete = key == 'delete';
    final enabled = key != '.' || _field == _SetField.weight;
    return Semantics(
      label: isDelete ? 'Delete digit' : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: TextButton(
          onPressed: enabled ? () => _type(key) : null,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor:
                isDelete
                    ? errorColor(context).withValues(alpha: 0.12)
                    : backgroundColor(context),
            foregroundColor:
                isDelete ? errorColor(context) : textPrimaryColor(context),
            disabledForegroundColor: textSecondaryColor(context),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
            textStyle: Theme.of(
              context,
            ).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w500),
          ),
          child:
              isDelete
                  ? const Icon(Icons.backspace_outlined, size: 20)
                  : Text(key),
        ),
      ),
    );
  }

  Widget _actionKey(
    BuildContext context, {
    required String label,
    required VoidCallback? onTap,
    required bool filled,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: filled ? accentFillColor(context) : Colors.transparent,
        foregroundColor: filled ? onAccentColor(context) : accentColor(context),
        disabledForegroundColor: textSecondaryColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.button,
          side: BorderSide(
            color:
                filled
                    ? accentFillColor(context)
                    : (onTap == null
                        ? borderColor(context)
                        : accentColor(context)),
            width: filled ? 0 : 2,
          ),
        ),
        textStyle: Theme.of(
          context,
        ).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    ),
  );
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
