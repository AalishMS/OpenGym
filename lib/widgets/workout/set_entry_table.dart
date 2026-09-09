import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/semantic_colors.dart';

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
}

String entryWeight(double weight) =>
    weight.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

enum _SetField { weight, reps, rpe }

/// Shared by prescribed sets, live sets, and the set detail dialogs.
class SetEntryTable extends StatelessWidget {
  final String exerciseName;
  final List<SetEntry> sets;
  final void Function(int index, double weight, int reps) onChanged;
  final void Function(int index, int? rpe)? onRpeChanged;
  final ValueChanged<int>? onDetails;
  final ValueChanged<int>? onDelete;
  final VoidCallback? onEntryFinished;
  final bool showHistoryColumns;

  const SetEntryTable({
    super.key,
    required this.exerciseName,
    required this.sets,
    required this.onChanged,
    this.onRpeChanged,
    this.onDetails,
    this.onDelete,
    this.onEntryFinished,
    this.showHistoryColumns = true,
  });

  Future<void> _open(BuildContext context, int index, _SetField field) async {
    FocusManager.instance.primaryFocus?.unfocus();
    var changed = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder:
          (_) => _SetKeyboard(
            sets: List.of(sets),
            initialIndex: index,
            initialField: field,
            showHistoryColumns: showHistoryColumns,
            onChanged: (index, weight, reps) {
              changed = true;
              onChanged(index, weight, reps);
            },
            onRpeChanged:
                onRpeChanged == null
                    ? null
                    : (index, rpe) {
                      changed = true;
                      onRpeChanged!(index, rpe);
                    },
          ),
    );
    if (changed) onEntryFinished?.call();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _EntryHeader(
        trailing: onDetails != null || onDelete != null,
        showHistoryColumns: showHistoryColumns,
        showRpe: onRpeChanged != null,
      ),
      for (var index = 0; index < sets.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EntryRow(
                showHistoryColumns: showHistoryColumns,
                index: index,
                previous: sets[index].previous,
                weight: entryWeight(sets[index].weight),
                reps: '${sets[index].reps}',
                rpe: sets[index].rpe,
                onWeight: () => _open(context, index, _SetField.weight),
                onReps: () => _open(context, index, _SetField.reps),
                onRpe:
                    onRpeChanged == null
                        ? null
                        : () => _open(context, index, _SetField.rpe),
                trailing:
                    onDetails != null || onDelete != null
                        ? Semantics(
                          label:
                              onDelete != null ? 'Delete set' : 'Set details',
                          button: true,
                          container: true,
                          excludeSemantics: true,
                          onTap: () => (onDelete ?? onDetails)!(index),
                          child: IconButton(
                            iconSize: 32,
                            tooltip:
                                onDelete != null ? 'Delete set' : 'Set details',
                            onPressed: () => (onDelete ?? onDetails)!(index),
                            icon:
                                onDelete == null && sets[index].rpe != null
                                    ? _effort(context, sets[index].rpe!)
                                    : Icon(
                                      onDelete != null
                                          ? Icons.close
                                          : Icons.more_horiz,
                                      size: 18,
                                      color: textSecondaryColor(context),
                                    ),
                          ),
                        )
                        : null,
              ),
              if (sets[index].annotation != null)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 6),
                  child: Text(sets[index].annotation!, style: _quiet(context)),
                ),
            ],
          ),
        ),
    ],
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
  child: FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      '@$rpe',
      maxLines: 1,
      softWrap: false,
      style: Theme.of(context).textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: rpeColor(rpe, context),
      ),
    ),
  ),
);

/// Header and data share the exact same column geometry at every width.
Widget _columns(
  List<Widget> cells, {
  Widget? trailing,
  bool showHistoryColumns = true,
  bool showRpe = false,
}) => Row(
  children: [
    if (showHistoryColumns) ...[
      SizedBox(width: 32, child: cells[0]),
      const SizedBox(width: 8),
      Expanded(flex: 6, child: cells[1]),
      const SizedBox(width: 8),
    ],
    Expanded(flex: 5, child: cells[2]),
    const SizedBox(width: 8),
    Expanded(flex: showRpe ? 4 : 5, child: cells[3]),
    if (showRpe) ...[
      const SizedBox(width: 8),
      Expanded(flex: 4, child: cells[4]),
    ],
    if (trailing != null) SizedBox(width: 48, child: trailing),
  ],
);

class _EntryHeader extends StatelessWidget {
  final bool trailing;
  final bool showHistoryColumns;
  final bool showRpe;
  const _EntryHeader({
    this.trailing = false,
    this.showHistoryColumns = true,
    this.showRpe = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _columns(
      [
        for (final label in ['Set', 'Prev', 'Kg', 'Reps', if (showRpe) 'RPE'])
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
              color: textSecondaryColor(context),
            ),
          ),
      ],
      trailing: trailing ? const SizedBox() : null,
      showHistoryColumns: showHistoryColumns,
      showRpe: showRpe,
    ),
  );
}

class _EntryRow extends StatelessWidget {
  final int index;
  final String? previous;
  final String weight;
  final String reps;
  final int? rpe;
  final VoidCallback onWeight;
  final VoidCallback onReps;
  final VoidCallback? onRpe;
  final Widget? trailing;
  final bool showHistoryColumns;

  const _EntryRow({
    required this.index,
    this.previous,
    required this.weight,
    required this.reps,
    this.rpe,
    required this.onWeight,
    required this.onReps,
    this.onRpe,
    this.trailing,
    this.showHistoryColumns = true,
  });

  @override
  Widget build(BuildContext context) => _columns(
    [
      Text(
        '${index + 1}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      Semantics(
        label: 'Previous set ${index + 1}: ${previous ?? 'no history'}',
        child: Text(
          previous ?? '—',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textSecondaryColor(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      _field(context, weight, 'Kg', false, onWeight),
      _field(context, reps, 'Reps', false, onReps),
      if (onRpe != null) _rpeReadout(context),
    ],
    trailing: trailing,
    showHistoryColumns: showHistoryColumns,
    showRpe: onRpe != null,
  );

  Widget _rpeReadout(BuildContext context) {
    final value = rpe == null ? '@—' : '@$rpe';
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
          child: SizedBox(
            height: 48,
            child: Center(
              child:
                  rpe == null
                      ? Text(
                        value,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          fontWeight: FontWeight.w700,
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
    bool active,
    VoidCallback onTap,
  ) => Semantics(
    label: 'Set ${index + 1} $label',
    container: true,
    excludeSemantics: true,
    onTap: onTap,
    value: value,
    button: true,
    selected: active,
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
                  active ? accentMutedColor(context) : backgroundColor(context),
              border: Border.all(
                color: active ? accentColor(context) : borderColor(context),
                width: active ? 2 : 1,
              ),
              borderRadius: AppRadius.field,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value.isEmpty ? '—' : value,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  fontSize: 20,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.bold,
                  color:
                      active
                          ? onColor(accentMutedColor(context))
                          : textPrimaryColor(context),
                ),
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
  final bool showHistoryColumns;
  final void Function(int, double, int) onChanged;
  final void Function(int, int?)? onRpeChanged;

  const _SetKeyboard({
    required this.sets,
    required this.initialIndex,
    required this.initialField,
    required this.showHistoryColumns,
    required this.onChanged,
    this.onRpeChanged,
  });

  @override
  State<_SetKeyboard> createState() => _SetKeyboardState();
}

class _SetKeyboardState extends State<_SetKeyboard> {
  late int _index = widget.initialIndex;
  late _SetField _field = widget.initialField;
  late String _input = _value;
  bool _replace = true;

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
  }

  void _type(String key) => setState(() {
    if (key == '.' && _field != _SetField.weight) return;
    var next = _replace ? '' : _input;
    if (key == 'delete') {
      next = _input.isEmpty ? '' : _input.substring(0, _input.length - 1);
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

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _contextRows(context),
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, thickness: 1, color: borderColor(context)),
                const SizedBox(height: AppSpacing.lg),
                _incrementRow(context),
                const SizedBox(height: AppSpacing.lg),
                _digitGrid(context),
                const SizedBox(height: AppSpacing.lg),
                _actionRow(context),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  List<(String, int)> get _contextColumns {
    final columns = <(String, int)>[];
    if (widget.showHistoryColumns) {
      columns.addAll([('Set', 7), ('Prev', 9)]);
    }
    columns.addAll([('Kg', 10), ('Reps', 9)]);
    if (widget.onRpeChanged != null) columns.add(('RPE', 8));
    return columns;
  }

  Widget _contextRows(BuildContext context) => Column(
    children: [
      Row(
        children: [
          for (final column in _contextColumns)
            Expanded(
              flex: column.$2,
              child: Text(
                column.$1,
                textAlign:
                    column.$1 == 'Set' || column.$1 == 'Prev'
                        ? TextAlign.left
                        : TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      Row(
        children: [
          if (widget.showHistoryColumns) ...[
            Expanded(flex: 7, child: _contextText(context, '${_index + 1}')),
            Expanded(
              flex: 9,
              child: _contextText(context, _set.previous ?? '—', muted: true),
            ),
          ],
          Expanded(
            flex: 10,
            child: _contextField(
              context,
              value:
                  _field == _SetField.weight
                      ? _input
                      : entryWeight(_set.weight),
              field: _SetField.weight,
              semanticsLabel: 'Set ${_index + 1} Kg',
              filled: false,
            ),
          ),
          Expanded(
            flex: 9,
            child: _contextField(
              context,
              value: _field == _SetField.reps ? _input : '${_set.reps}',
              field: _SetField.reps,
              semanticsLabel: 'Set ${_index + 1} Reps',
            ),
          ),
          if (widget.onRpeChanged != null)
            Expanded(
              flex: 8,
              child: _contextField(
                context,
                value:
                    '@ ${_field == _SetField.rpe ? (_input.isEmpty ? '—' : _input) : (_set.rpe?.toString() ?? '—')}',
                field: _SetField.rpe,
                semanticsLabel:
                    _set.rpe == null
                        ? 'Set ${_index + 1} RPE, not set'
                        : 'Set ${_index + 1} RPE ${_set.rpe}',
              ),
            ),
        ],
      ),
    ],
  );

  Widget _contextText(
    BuildContext context,
    String value, {
    bool muted = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge!.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: muted ? textSecondaryColor(context) : textPrimaryColor(context),
      ),
    ),
  );

  Widget _contextField(
    BuildContext context, {
    required String value,
    required _SetField field,
    required String semanticsLabel,
    bool filled = true,
  }) {
    final active = _field == field;
    final Color valueColor;
    if (active) {
      valueColor = accentColor(context);
    } else if (field == _SetField.rpe && _set.rpe != null) {
      valueColor = rpeColor(_set.rpe!, context);
    } else {
      valueColor =
          field == _SetField.rpe
              ? textSecondaryColor(context)
              : textPrimaryColor(context);
    }
    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: active,
      excludeSemantics: true,
      onTap: () => _select(_index, field),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.button,
        child: InkWell(
          onTap: () => _select(_index, field),
          borderRadius: AppRadius.button,
          child: Container(
            height: 48,
            margin: const EdgeInsets.only(left: AppSpacing.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  filled
                      ? (active
                          ? accentMutedColor(context)
                          : backgroundColor(context))
                      : Colors.transparent,
              borderRadius: AppRadius.button,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value.isEmpty ? '0' : value,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _adjustmentEnabled(double delta) => switch (_field) {
    _SetField.weight => true,
    _SetField.reps => delta.abs() == 1,
    _SetField.rpe => false,
  };

  Widget _incrementRow(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _incrementKey(
            context,
            label: const ['+2.5', '−2.5', '+1', '−1'][i],
            delta: const [2.5, -2.5, 1.0, -1.0][i],
          ),
        ),
      ],
    ],
  );

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
      child: SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: enabled ? () => _adjust(delta) : null,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor:
                emphasized ? accentColor(context) : textPrimaryColor(context),
            disabledForegroundColor: textSecondaryColor(context),
            side: BorderSide(
              color: emphasized ? accentColor(context) : borderColor(context),
              width: emphasized ? 2 : 1,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.keypadKey,
            ),
          ),
          child: FittedBox(child: Text(label)),
        ),
      ),
    );
  }

  Widget _digitGrid(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final keyWidth = (constraints.maxWidth - AppSpacing.lg) / 3;
      final keyHeight = (keyWidth / 2.2).clamp(52.0, 72.0);
      const rows = [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
        ['.', '0', 'delete'],
      ];
      return Column(
        children: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
            if (rowIndex > 0) const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 0; i < rows[rowIndex].length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _digitKey(
                      context,
                      rows[rowIndex][i],
                      height: keyHeight,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _digitKey(BuildContext context, String key, {required double height}) {
    final isDelete = key == 'delete';
    final enabled = key != '.' || _field == _SetField.weight;
    return Semantics(
      label: isDelete ? 'Delete digit' : null,
      child: SizedBox(
        height: height,
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
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.keypadKey,
            ),
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

  Widget _actionRow(BuildContext context) => Row(
    children: [
      Expanded(
        child: _actionKey(
          context,
          label: 'Next',
          onTap: _hasNext ? _next : null,
          filled: false,
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: _actionKey(
          context,
          label: 'Save',
          onTap: () => Navigator.pop(context),
          filled: true,
        ),
      ),
    ],
  );

  Widget _actionKey(
    BuildContext context, {
    required String label,
    required VoidCallback? onTap,
    required bool filled,
  }) => SizedBox(
    height: 52,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: filled ? accentFillColor(context) : Colors.transparent,
        foregroundColor: filled ? onAccentColor(context) : accentColor(context),
        disabledForegroundColor: textSecondaryColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.keypadKey,
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
