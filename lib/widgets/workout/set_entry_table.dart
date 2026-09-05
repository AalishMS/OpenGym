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

/// Shared by prescribed sets, live sets, and the set detail dialogs.
class SetEntryTable extends StatelessWidget {
  final String exerciseName;
  final List<SetEntry> sets;
  final void Function(int index, double weight, int reps) onChanged;
  final ValueChanged<int>? onDetails;
  final ValueChanged<int>? onDelete;
  final VoidCallback? onEntryFinished;
  final bool showHistoryColumns;

  const SetEntryTable({
    super.key,
    required this.exerciseName,
    required this.sets,
    required this.onChanged,
    this.onDetails,
    this.onDelete,
    this.onEntryFinished,
    this.showHistoryColumns = true,
  });

  Future<void> _open(BuildContext context, int index, bool weight) async {
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
            exerciseName: exerciseName,
            sets: List.of(sets),
            initialIndex: index,
            initialWeight: weight,
            onChanged: (index, weight, reps) {
              changed = true;
              onChanged(index, weight, reps);
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
                onWeight: () => _open(context, index, true),
                onReps: () => _open(context, index, false),
                trailing:
                    onDetails != null || onDelete != null
                        ? IconButton(
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
    Expanded(flex: 5, child: cells[3]),
    if (trailing != null) SizedBox(width: 48, child: trailing),
  ],
);

class _EntryHeader extends StatelessWidget {
  final bool trailing;
  final bool showHistoryColumns;
  const _EntryHeader({this.trailing = false, this.showHistoryColumns = true});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _columns(
      [
        for (final label in ['Set', 'Prev', 'Kg', 'Reps'])
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
    ),
  );
}

class _EntryRow extends StatelessWidget {
  final int index;
  final String? previous;
  final String weight;
  final String reps;
  final bool? activeWeight;
  final VoidCallback onWeight;
  final VoidCallback onReps;
  final Widget? trailing;
  final bool showHistoryColumns;

  const _EntryRow({
    required this.index,
    this.previous,
    required this.weight,
    required this.reps,
    this.activeWeight,
    required this.onWeight,
    required this.onReps,
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
      _field(context, weight, 'Kg', activeWeight == true, onWeight),
      _field(context, reps, 'Reps', activeWeight == false, onReps),
    ],
    trailing: trailing,
    showHistoryColumns: showHistoryColumns,
  );

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
  final String exerciseName;
  final List<SetEntry> sets;
  final int initialIndex;
  final bool initialWeight;
  final void Function(int, double, int) onChanged;

  const _SetKeyboard({
    required this.exerciseName,
    required this.sets,
    required this.initialIndex,
    required this.initialWeight,
    required this.onChanged,
  });

  @override
  State<_SetKeyboard> createState() => _SetKeyboardState();
}

class _SetKeyboardState extends State<_SetKeyboard> {
  late int _index = widget.initialIndex;
  late bool _weight = widget.initialWeight;
  late String _input = _value;
  bool _replace = true;

  SetEntry get _set => widget.sets[_index];
  String get _value => _weight ? entryWeight(_set.weight) : '${_set.reps}';

  void _select(int index, bool weight) => setState(() {
    _index = index;
    _weight = weight;
    _input = _value;
    _replace = true;
  });

  void _publish() {
    // Clearing a field explicitly sets it to zero; a blank draft cannot leak
    // stale values into autosave. Reps are always integral.
    final value = double.tryParse(_input) ?? 0;
    final updated = SetEntry(
      weight: _weight ? value : _set.weight,
      reps: _weight ? _set.reps : value.toInt(),
      previous: _set.previous,
      annotation: _set.annotation,
      rpe: _set.rpe,
    );
    widget.sets[_index] = updated;
    widget.onChanged(_index, updated.weight, updated.reps);
  }

  void _type(String key) => setState(() {
    if (key == '.' && !_weight) return;
    var next = _replace ? '' : _input;
    if (key == 'delete') {
      next = _input.isEmpty ? '' : _input.substring(0, _input.length - 1);
    } else if (key == '.') {
      if (next.contains('.')) return;
      next = next.isEmpty ? '0.' : '$next.';
    } else {
      next = next == '0' ? key : '$next$key';
    }
    if (next.length > 6 || (double.tryParse(next) ?? 0) > 999) return;
    if (next.contains('.') && next.split('.').last.length > 2) return;
    _input = next;
    _replace = false;
    _publish();
  });

  void _adjust(double delta) => setState(() {
    _input = entryWeight((_set.weight + delta).clamp(0, 999).toDouble());
    _replace = true;
    _publish();
  });

  void _next() {
    if (_weight) {
      _select(_index, false);
    } else if (_index + 1 < widget.sets.length) {
      _select(_index + 1, true);
    }
  }

  bool get _hasNext => _weight || _index + 1 < widget.sets.length;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.exerciseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            _EntryHeader(trailing: widget.sets.any((set) => set.rpe != null)),
            _EntryRow(
              index: _index,
              previous: _set.previous,
              weight: _weight ? _input : entryWeight(_set.weight),
              reps: _weight ? '${_set.reps}' : _input,
              activeWeight: _weight,
              trailing:
                  widget.sets.any((set) => set.rpe != null)
                      ? Center(
                        child:
                            _set.rpe == null
                                ? const SizedBox()
                                : _effort(context, _set.rpe!),
                      )
                      : null,
              onWeight: () => _select(_index, true),
              onReps: () => _select(_index, false),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Set ${_index + 1} of ${widget.sets.length} · ${_weight ? 'Weight' : 'Reps'}',
                style: _quiet(context),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _key('−2.5 kg', _weight ? () => _adjust(-2.5) : null),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _key('+2.5 kg', _weight ? () => _adjust(2.5) : null),
                ),
              ],
            ),
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['.', '0', 'delete'],
            ])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _key(
                          row[i] == 'delete' ? 'Delete' : row[i],
                          row[i] == '.' && !_weight
                              ? null
                              : () => _type(row[i]),
                          semanticLabel:
                              row[i] == 'delete' ? 'Delete digit' : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _key('Next', _hasNext ? _next : null, filled: true),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _key(
                    'Save',
                    () => Navigator.pop(context),
                    filled: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _key(
    String label,
    VoidCallback? onTap, {
    bool filled = false,
    String? semanticLabel,
  }) => Semantics(
    label: semanticLabel,
    child: SizedBox(
      height: 52,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor:
              filled ? accentFillColor(context) : backgroundColor(context),
          foregroundColor:
              filled ? onAccentColor(context) : textPrimaryColor(context),
          disabledForegroundColor: textSecondaryColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.button,
            side: BorderSide(color: borderColor(context)),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
            fontSize: label.length == 1 ? 22 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    ),
  );
}
