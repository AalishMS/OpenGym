import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/training_block.dart';
import '../../models/training_week.dart';
import '../../services/training_week_choices.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'training_block_strip.dart';

abstract final class TrainingBlockDialogs {
  static Future<String?> startingWeek(
    BuildContext context, {
    required List<TrainingBlock> blocks,
    required Map<String, List<TrainingWeek>> weeksByBlock,
    String? selectedWeekId,
  }) => showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (_) => _StartingWeek(
          blocks: blocks,
          weeksByBlock: {
            for (final block in blocks)
              block.id: plannedTrainingWeeks(
                block,
                weeksByBlock[block.id] ?? [],
              ),
          },
          selectedWeekId: selectedWeekId,
        ),
  );

  static Future<TrainingBlock?> create(
    BuildContext context, {
    required Future<TrainingBlock> Function(String name, int count) onSave,
  }) => showDialog<TrainingBlock>(
    context: context,
    builder: (_) => _BlockForm(onCreate: onSave),
  );

  static Future<void> rename(
    BuildContext context,
    TrainingBlock block, {
    required Future<void> Function(String name) onSave,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _BlockForm(initialName: block.name, onRename: onSave),
  );

  static Future<void> reorder(
    BuildContext context,
    List<TrainingBlock> blocks, {
    required Future<void> Function(List<String> ids) onSave,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _BlockOrder(blocks: blocks, onSave: onSave),
  );
}

/// Where a new workout begins, shown as a tappable field. [dense] drops the
/// ground and label for a one-line row under a card, as in a Coach review.
class StartingWeekField extends StatelessWidget {
  final String value;
  final VoidCallback? onTap;
  final bool dense;

  const StartingWeekField({
    super.key,
    required this.value,
    required this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    final icon = Icon(
      LucideIcons.calendarRange,
      size: dense ? 16 : 20,
      color: enabled ? accent : textSecondary,
    );
    if (dense) {
      return InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    value,
                    style: textTheme.bodyMedium?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                ),
                if (enabled)
                  Text(
                    'Change',
                    style: textTheme.labelLarge?.copyWith(color: accent),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      color: surfaceColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.field,
        side: BorderSide(color: borderColor(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              icon,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Starting week',
                      style: textTheme.labelMedium?.copyWith(
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      value,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: textPrimaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(LucideIcons.chevronRight, size: 18, color: textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title, supporting line, body and actions on the app's dialog ground — the
/// same frame as the split dialogs, so block management reads as one family.
class _BlockDialogFrame extends StatelessWidget {
  final String title;
  final String description;
  final Widget body;
  final String? error;
  final List<Widget> actions;
  final double maxWidth;

  const _BlockDialogFrame({
    required this.title,
    required this.description,
    required this.body,
    required this.actions,
    this.error,
    this.maxWidth = 400,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: textTheme.headlineSmall?.copyWith(
                  color: accentColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: textTheme.bodyMedium?.copyWith(
                  color: textSecondaryColor(context),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(child: body),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorLine(error!),
              ],
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  final String message;
  const _ErrorLine(this.message);

  @override
  Widget build(BuildContext context) {
    final error = errorColor(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.circleAlert, size: 16, color: error),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: error),
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary action, which keeps its width and shows a spinner in place of
/// its label while the write is in flight.
class _SaveButton extends StatelessWidget {
  final String label;
  final bool saving;
  final VoidCallback? onPressed;

  const _SaveButton({
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: saving ? null : onPressed,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: saving ? 0 : 1, child: Text(label)),
        if (saving)
          Semantics(
            label: 'Saving',
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: textSecondaryColor(context),
              ),
            ),
          ),
      ],
    ),
  );
}

class _BlockForm extends StatefulWidget {
  final String? initialName;
  final Future<TrainingBlock> Function(String, int)? onCreate;
  final Future<void> Function(String)? onRename;
  const _BlockForm({this.initialName, this.onCreate, this.onRename});
  @override
  State<_BlockForm> createState() => _BlockFormState();
}

class _BlockFormState extends State<_BlockForm> {
  static const _maxWeeks = 52;
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName ?? '');
  final _count = TextEditingController(text: '1');
  bool _saving = false;
  String? _error;

  bool get _creating => widget.onCreate != null;
  int? get _weeks => int.tryParse(_count.text);

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = ((_weeks ?? 1) + delta).clamp(1, _maxWeeks);
    setState(() => _count.text = '$next');
    _form.currentState?.validate();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.onCreate case final create?) {
        final result = await create(_name.text.trim(), int.parse(_count.text));
        if (mounted) Navigator.pop(context, result);
      } else {
        await widget.onRename!(_name.text.trim());
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weeks;
    final stepStyle = IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      side: BorderSide(color: borderColor(context)),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
    );
    return PopScope(
      canPop: !_saving,
      child: _BlockDialogFrame(
        title: _creating ? 'Create block' : 'Rename block',
        description:
            _creating
                ? 'A block is a phase of training, like four weeks of '
                    'strength work. Each workout reveals the next week as '
                    'you complete it.'
                : 'Weeks and logged workouts stay in this block.',
        error: _error,
        body: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 40,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction:
                      _creating ? TextInputAction.next : TextInputAction.done,
                  onFieldSubmitted: _creating ? null : (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Block name',
                    helperText: '1–40 characters',
                    counterText: '',
                  ),
                  validator:
                      (value) =>
                          (value ?? '').trim().isEmpty
                              ? 'Enter a block name.'
                              : null,
                ),
                if (_creating) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        tooltip: 'Fewer weeks',
                        style: stepStyle,
                        onPressed:
                            _saving || weeks == null || weeks <= 1
                                ? null
                                : () => _step(-1),
                        icon: const Icon(LucideIcons.minus, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          controller: _count,
                          enabled: !_saving,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          style: AppTypography.figures(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimaryColor(context),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Weeks',
                            isDense: true,
                            // Matches the 48px steppers on either side.
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 11,
                            ),
                            floatingLabelAlignment:
                                FloatingLabelAlignment.center,
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                          validator: (value) {
                            final count = int.tryParse(value ?? '');
                            return count == null ||
                                    count < 1 ||
                                    count > _maxWeeks
                                ? 'Choose 1–52 weeks.'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        tooltip: 'More weeks',
                        style: stepStyle,
                        onPressed:
                            _saving || (weeks != null && weeks >= _maxWeeks)
                                ? null
                                : () => _step(1),
                        icon: const Icon(LucideIcons.plus, size: 20),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          _SaveButton(
            label: _creating ? 'Create' : 'Save',
            saving: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _BlockOrder extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Future<void> Function(List<String>) onSave;
  const _BlockOrder({required this.blocks, required this.onSave});
  @override
  State<_BlockOrder> createState() => _BlockOrderState();
}

class _BlockOrderState extends State<_BlockOrder> {
  late final _blocks = List<TrainingBlock>.of(widget.blocks);
  bool _saving = false;
  String? _error;

  bool get _changed {
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].id != widget.blocks[i].id) return true;
    }
    return false;
  }

  void _move(int from, int to) {
    if (_saving || to < 0 || to >= _blocks.length) return;
    setState(() => _blocks.insert(to, _blocks.removeAt(from)));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_blocks.map((b) => b.id).toList());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Blocks changed. Close and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: !_saving,
      child: _BlockDialogFrame(
        title: 'Reorder blocks',
        description:
            'Hold and drag a block, or use the arrows. Its weeks and logs '
            'move with it.',
        maxWidth: 420,
        error: _error,
        body: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .45,
          ),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            itemCount: _blocks.length,
            onReorderItem: _move,
            proxyDecorator:
                (child, _, animation) => AnimatedBuilder(
                  animation: animation,
                  builder:
                      (context, child) => Material(
                        elevation: 6 * animation.value,
                        color: surfaceColor(context),
                        shadowColor: backgroundColor(context).withAlpha(128),
                        borderRadius: AppRadius.control,
                        child: child,
                      ),
                  child: child,
                ),
            itemBuilder: (context, index) {
              final block = _blocks[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(block.id),
                index: index,
                enabled: !_saving,
                child: AnimatedContainer(
                  duration:
                      disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    border:
                        index == _blocks.length - 1
                            ? null
                            : Border(
                              bottom: BorderSide(color: borderColor(context)),
                            ),
                  ),
                  child: _OrderRow(
                    position: index + 1,
                    name: block.name,
                    onUp:
                        _saving || index == 0
                            ? null
                            : () => _move(index, index - 1),
                    onDown:
                        _saving || index == _blocks.length - 1
                            ? null
                            : () => _move(index, index + 1),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          _SaveButton(
            label: 'Save',
            saving: _saving,
            onPressed: _changed ? _save : null,
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final int position;
  final String name;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _OrderRow({
    required this.position,
    required this.name,
    required this.onUp,
    required this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(LucideIcons.gripVertical, size: 18, color: textSecondary),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 24,
            child: Text(
              '$position',
              textAlign: TextAlign.center,
              style: AppTypography.figures(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: textPrimaryColor(context),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Move $name up',
            onPressed: onUp,
            icon: const Icon(LucideIcons.chevronUp, size: 20),
          ),
          IconButton(
            tooltip: 'Move $name down',
            onPressed: onDown,
            icon: const Icon(LucideIcons.chevronDown, size: 20),
          ),
        ],
      ),
    );
  }
}

class _StartingWeek extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Map<String, List<TrainingWeek>> weeksByBlock;
  final String? selectedWeekId;
  const _StartingWeek({
    required this.blocks,
    required this.weeksByBlock,
    this.selectedWeekId,
  });
  @override
  State<_StartingWeek> createState() => _StartingWeekState();
}

class _StartingWeekState extends State<_StartingWeek> {
  final _selectedChip = GlobalKey();
  String? _block;
  String? _week;

  List<TrainingBlock> get _choices =>
      widget.blocks
          .where((b) => (widget.weeksByBlock[b.id] ?? []).isNotEmpty)
          .toList();

  @override
  void initState() {
    super.initState();
    final choices = _choices;
    final chosen =
        choices
            .where(
              (b) => widget.weeksByBlock[b.id]!.any(
                (w) => w.id == widget.selectedWeekId,
              ),
            )
            .firstOrNull ??
        choices.firstOrNull;
    _block = chosen?.id;
    _week =
        widget.selectedWeekId ??
        (_block == null ? null : widget.weeksByBlock[_block]!.first.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _selectedChip.currentContext;
      if (mounted && chip != null) {
        Scrollable.ensureVisible(chip, alignment: .5);
      }
    });
  }

  void _chooseBlock(String id) {
    if (id == _block) return;
    setState(() {
      _block = id;
      _week = widget.weeksByBlock[id]!.first.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textSecondary = textSecondaryColor(context);
    final choices = _choices;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Choose starting week',
                    style: textTheme.titleLarge?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'This workout starts here. Later weeks appear as you '
                  'complete it.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in choices) ...[
                    _StartBlockTile(
                      name: block.name,
                      caption: trainingBlockLengthLabel(
                        block,
                        widget.weeksByBlock[block.id]!,
                      ),
                      selected: block.id == _block,
                      onTap: () => _chooseBlock(block.id),
                      weeks: [
                        for (final week in widget.weeksByBlock[block.id]!)
                          _WeekChip(
                            key: week.id == _week ? _selectedChip : null,
                            number: week.number,
                            selected: week.id == _week,
                            onTap: () => setState(() => _week = week.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _week == null
                            ? null
                            : () => Navigator.pop(context, _week),
                    child: const Text(
                      'Use this week',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One block in the starting-week sheet. The chosen block opens to show its
/// weeks, so the two choices read as one decision rather than two dropdowns.
class _StartBlockTile extends StatelessWidget {
  final String name;
  final String caption;
  final bool selected;
  final VoidCallback onTap;
  final List<Widget> weeks;

  const _StartBlockTile({
    required this.name,
    required this.caption,
    required this.selected,
    required this.onTap,
    required this.weeks,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180);
    return AnimatedContainer(
      duration: duration,
      decoration: BoxDecoration(
        borderRadius: AppRadius.card,
        border: Border.all(
          color: selected ? accent : borderColor(context),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              onTap: onTap,
              borderRadius: selected ? AppRadius.cardTop : AppRadius.card,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected ? LucideIcons.circleCheck : LucideIcons.circle,
                        size: 18,
                        color: selected ? accent : textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: textPrimaryColor(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        caption,
                        style: AppTypography.figures(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child:
                selected
                    ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: weeks,
                      ),
                    )
                    : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  final int number;
  final bool selected;
  final VoidCallback onTap;

  const _WeekChip({
    super.key,
    required this.number,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ground = selected ? accentFillColor(context) : surfaceColor(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: ground,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.chip,
          side: BorderSide(color: selected ? ground : borderColor(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Week $number',
                  style: AppTypography.figures(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        selected
                            ? onAccentColor(context)
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
}
