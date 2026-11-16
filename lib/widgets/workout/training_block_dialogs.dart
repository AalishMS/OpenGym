import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/training_block.dart';
import '../../models/training_week.dart';
import '../../repositories/training_block_repository.dart';
import '../../services/sync_service.dart';
import '../../services/training_block_lifecycle.dart';
import '../../services/training_week_choices.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'training_block_strip.dart';

/// The split's blocks and the weeks each one offers, read fresh so the
/// starting-week sheet can refresh after a block is created or edited.
typedef TrainingBlockSnapshot =
    ({
      List<TrainingBlock> blocks,
      Map<String, List<TrainingWeek>> weeksByBlock,
    });

/// How [TrainingBlockDialogs.edit] ended, when it did not simply close.
sealed class TrainingBlockEditResult {
  const TrainingBlockEditResult();
}

/// The block was renamed and/or resized; [block] is the stored result.
class TrainingBlockSaved extends TrainingBlockEditResult {
  final TrainingBlock block;
  const TrainingBlockSaved(this.block);
}

/// The block was deleted. [name] is what it was called.
class TrainingBlockDeleted extends TrainingBlockEditResult {
  final String name;
  const TrainingBlockDeleted(this.name);
}

/// What the block sheets need to shorten and delete blocks. Everything is read
/// when a block's Edit dialog opens, so a dialog reflects the current state.
class TrainingBlockLifecycle {
  /// Whether blocks can be shortened and deleted right now.
  final bool Function() available;

  /// The fewest weeks [TrainingBlock] can become, or null to keep its length.
  final int? Function(TrainingBlock block) minimumWeekCount;

  /// Why the block cannot be deleted, or null when it can.
  final BlockDeletionBlocker? Function(TrainingBlock block) deleteBlocker;
  final Future<void> Function(TrainingBlock block) delete;

  const TrainingBlockLifecycle({
    required this.available,
    required this.minimumWeekCount,
    required this.deleteBlocker,
    required this.delete,
  });

  /// Reads the rules from [repository]. A block the repository cannot find
  /// (it just changed) answers as keep-length and deletable; the write then
  /// reports the real reason.
  factory TrainingBlockLifecycle.of(
    TrainingBlockRepository repository, {
    required String splitId,
    required Future<void> Function(TrainingBlock block) delete,
  }) => TrainingBlockLifecycle(
    available: () => repository.lifecycleAvailable,
    minimumWeekCount: (block) {
      try {
        return repository.minimumWeekCount(splitId, block.id);
      } catch (_) {
        return null;
      }
    },
    deleteBlocker: (block) {
      try {
        return repository.deleteBlocker(splitId, block.id);
      } catch (_) {
        return null;
      }
    },
    delete: delete,
  );
}

abstract final class TrainingBlockDialogs {
  /// Why a block cannot be deleted, in the words shown beneath Delete block.
  static String blockerMessage(BlockDeletionBlocker blocker) =>
      switch (blocker) {
        BlockDeletionBlocker.lastBlock => 'A split keeps at least one block.',
        BlockDeletionBlocker.hasWorkouts =>
          'This block has workouts in it, so it can\'t be deleted.',
        BlockDeletionBlocker.workoutInBlock =>
          'A workout is in this block right now. Move it to another block '
              'first.',
      };

  /// Pick a block and week. With [load] and the block callbacks the sheet also
  /// creates and edits blocks in place; without them it only picks.
  static Future<String?> startingWeek(
    BuildContext context, {
    required List<TrainingBlock> blocks,
    required Map<String, List<TrainingWeek>> weeksByBlock,
    String? selectedWeekId,
    TrainingBlockSnapshot Function()? load,
    Future<TrainingBlock> Function(String name, int count)? onCreateBlock,
    Future<TrainingBlock> Function(
      TrainingBlock block,
      String name,
      int? count,
    )?
    onEditBlock,
    TrainingBlockLifecycle? lifecycle,
  }) => showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (_) => _StartingWeek(
          blocks: blocks,
          weeksByBlock: weeksByBlock,
          selectedWeekId: selectedWeekId,
          load: load,
          onCreateBlock: onCreateBlock,
          onEditBlock: onEditBlock,
          lifecycle: lifecycle,
        ),
  );

  /// Lists the split's blocks with their lengths, marks [currentBlockId], and
  /// creates or edits blocks. There is no week to pick, so it only closes.
  static Future<void> manage(
    BuildContext context, {
    required TrainingBlockSnapshot Function() load,
    required Future<TrainingBlock> Function(String name, int count)
    onCreateBlock,
    required Future<TrainingBlock> Function(
      TrainingBlock block,
      String name,
      int? count,
    )
    onEditBlock,
    String? currentBlockId,
    TrainingBlockLifecycle? lifecycle,
  }) {
    final snapshot = load();
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _StartingWeek(
            blocks: snapshot.blocks,
            weeksByBlock: snapshot.weeksByBlock,
            currentBlockId: currentBlockId,
            picking: false,
            load: load,
            onCreateBlock: onCreateBlock,
            onEditBlock: onEditBlock,
            lifecycle: lifecycle,
          ),
    );
  }

  static Future<TrainingBlock?> create(
    BuildContext context, {
    required Future<TrainingBlock> Function(String name, int count) onSave,
    int initialWeekCount = kDefaultBlockWeeks,
  }) async =>
      await showDialog<Object>(
            context: context,
            builder:
                (_) => _BlockForm(
                  onSave: (name, count) => onSave(name, count!),
                  initialWeekCount: initialWeekCount,
                ),
          )
          as TrainingBlock?;

  /// Rename, resize or delete a block. Null means it was closed unchanged.
  ///
  /// [minimumWeekCount] is the fewest weeks the block may become; it defaults
  /// to [currentWeekCount], so a block can only grow. A non-null [onDelete]
  /// says shortening and deleting are supported for this account: the dialog
  /// then offers Delete block, disabled with [deleteUnavailableReason] beneath
  /// it when the block cannot be deleted. Without it the dialog keeps the
  /// grow-only behaviour and has no delete.
  ///
  /// [onSave] gets a null count when the user left the weeks as they opened
  /// the dialog, meaning "keep the stored length": the block may have been
  /// resized elsewhere while the dialog was open, and a rename must not undo
  /// that.
  static Future<TrainingBlockEditResult?> edit(
    BuildContext context,
    TrainingBlock block, {
    required int currentWeekCount,
    required Future<TrainingBlock> Function(String name, int? count) onSave,
    int? minimumWeekCount,
    Future<void> Function()? onDelete,
    String? deleteUnavailableReason,
  }) async {
    final result = await showDialog<Object>(
      context: context,
      builder:
          (_) => _BlockForm(
            initialName: block.name,
            initialWeekCount: currentWeekCount,
            minWeekCount: (minimumWeekCount ?? currentWeekCount).clamp(
              1,
              currentWeekCount,
            ),
            lifecycle: onDelete != null,
            onSave: onSave,
            onDelete: onDelete,
            deleteUnavailableReason: deleteUnavailableReason,
          ),
    );
    return result as TrainingBlockEditResult?;
  }

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
  final String label;

  const StartingWeekField({
    super.key,
    required this.value,
    required this.onTap,
    this.dense = false,
    this.label = 'Starting week',
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
                      label,
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
  /// Null when creating; set when editing an existing block.
  final String? initialName;
  final int initialWeekCount;

  /// The fewest weeks allowed. Below [initialWeekCount] the block can shrink.
  final int minWeekCount;

  /// Whether this account can shorten and delete blocks (editing only).
  final bool lifecycle;
  final Future<TrainingBlock> Function(String, int?) onSave;
  final Future<void> Function()? onDelete;
  final String? deleteUnavailableReason;
  const _BlockForm({
    this.initialName,
    required this.initialWeekCount,
    this.minWeekCount = 1,
    this.lifecycle = false,
    required this.onSave,
    this.onDelete,
    this.deleteUnavailableReason,
  });
  @override
  State<_BlockForm> createState() => _BlockFormState();
}

class _BlockFormState extends State<_BlockForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _count = TextEditingController(text: '${widget.initialWeekCount}');
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  bool get _busy => _saving || _deleting;
  bool get _creating => widget.initialName == null;
  int get _minWeeks => widget.minWeekCount;
  bool get _canShorten => !_creating && _minWeeks < widget.initialWeekCount;
  bool get _canDelete =>
      !_creating && widget.lifecycle && widget.onDelete != null;
  // A block can already be past the usual cap through appended weeks; it may
  // keep that length but not grow further.
  int get _maxWeeks =>
      widget.initialWeekCount > kMaxBlockWeeks
          ? widget.initialWeekCount
          : kMaxBlockWeeks;
  int? get _weeks => int.tryParse(_count.text);

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = ((_weeks ?? _minWeeks) + delta).clamp(_minWeeks, _maxWeeks);
    setState(() => _count.text = '$next');
    _form.currentState?.validate();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final weeks = int.parse(_count.text);
      // Creating always sends a length. Editing sends one only when the user
      // changed it from what the dialog opened with, so a rename alone never
      // writes the length.
      final result = await widget.onSave(
        _name.text.trim(),
        _creating || weeks != widget.initialWeekCount ? weeks : null,
      );
      if (mounted) {
        Navigator.pop(context, _creating ? result : TrainingBlockSaved(result));
      }
    } on ArgumentError {
      // The repository refused the values: while this dialog was open the
      // block changed (a sync or another workout made it longer), so retrying
      // the same numbers can never work.
      if (mounted) {
        setState(
          () =>
              _error =
                  _creating
                      ? 'Could not save. Try again.'
                      : 'This block changed. Close and open it again.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final name = widget.initialName!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteBlockConfirmation(name: name),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context, TrainingBlockDeleted(name));
    } on TrainingBlockDeletionException catch (e) {
      if (mounted) setState(() => _error = _deletionMessage(e));
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not delete. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  static String _deletionMessage(TrainingBlockDeletionException e) {
    // This device found the block in use itself: say which way.
    final blocker = e.blocker;
    if (blocker != null) return TrainingBlockDialogs.blockerMessage(blocker);
    return switch (e.reason) {
      TrainingBlockDeletionReason.inUse =>
        'This block is in use on another device.',
      TrainingBlockDeletionReason.lastBlock =>
        TrainingBlockDialogs.blockerMessage(BlockDeletionBlocker.lastBlock),
      TrainingBlockDeletionReason.updateRequired =>
        'Update OpenGym to delete blocks.',
      TrainingBlockDeletionReason.unavailable ||
      TrainingBlockDeletionReason
          .splitDeleted => 'This block is no longer available.',
    };
  }

  String get _description {
    if (_creating) {
      return 'A block is a phase of training, like four weeks of strength '
          'work. Each workout reveals the next week as you complete it.';
    }
    if (_canShorten) {
      return 'Remove planned weeks no workout has reached, or add more. '
          'Logged workouts stay in this block.';
    }
    if (widget.lifecycle) {
      return 'Rename this block or add weeks. Logged workouts stay in this '
          'block.';
    }
    return 'You can add weeks but not remove them. Weeks and logged '
        'workouts stay in this block.';
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
      canPop: !_busy,
      child: _BlockDialogFrame(
        title: _creating ? 'Create block' : 'Edit block',
        description: _description,
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
                  enabled: !_busy,
                  maxLength: 40,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
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
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'Fewer weeks',
                      style: stepStyle,
                      onPressed:
                          _busy || weeks == null || weeks <= _minWeeks
                              ? null
                              : () => _step(-1),
                      icon: const Icon(LucideIcons.minus, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _count,
                        enabled: !_busy,
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
                          floatingLabelAlignment: FloatingLabelAlignment.center,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        validator: (value) {
                          final count = int.tryParse(value ?? '');
                          if (count != null &&
                              count >= _minWeeks &&
                              count <= _maxWeeks) {
                            return null;
                          }
                          if (_creating || _canShorten) {
                            return 'Choose $_minWeeks–$_maxWeeks weeks.';
                          }
                          return 'Weeks can only be added. Choose '
                              '$_minWeeks–$_maxWeeks.';
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      tooltip: 'More weeks',
                      style: stepStyle,
                      onPressed:
                          _busy || (weeks != null && weeks >= _maxWeeks)
                              ? null
                              : () => _step(1),
                      icon: const Icon(LucideIcons.plus, size: 20),
                    ),
                  ],
                ),
                if (!_creating && widget.lifecycle && !_canShorten) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Every week here has been reached, so this block can\'t '
                    'be shorter.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textSecondaryColor(context),
                    ),
                  ),
                ],
                if (_canDelete) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Divider(height: 1, color: borderColor(context)),
                  const SizedBox(height: AppSpacing.lg),
                  _DeleteBlockButton(
                    deleting: _deleting,
                    onPressed:
                        _busy || widget.deleteUnavailableReason != null
                            ? null
                            : _delete,
                  ),
                  if (widget.deleteUnavailableReason != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.deleteUnavailableReason!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: textSecondaryColor(context),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          _SaveButton(
            label: _creating ? 'Create' : 'Save',
            saving: _saving,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// The destructive entry point in Edit block. It sits apart from Cancel and
/// Save, outlined in the error colour, and is disabled rather than hidden when
/// the block can't be deleted.
class _DeleteBlockButton extends StatelessWidget {
  final bool deleting;
  final VoidCallback? onPressed;
  const _DeleteBlockButton({required this.deleting, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final error = errorColor(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: error,
        side: BorderSide(
          color: onPressed == null ? borderColor(context) : error,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      icon:
          deleting
              ? Semantics(
                label: 'Deleting',
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: textSecondaryColor(context),
                  ),
                ),
              )
              : const Icon(LucideIcons.trash2, size: 18),
      label: const Text('Delete block'),
    );
  }
}

class _DeleteBlockConfirmation extends StatelessWidget {
  final String name;
  const _DeleteBlockConfirmation({required this.name});

  @override
  Widget build(BuildContext context) {
    final error = errorColor(context);
    return AlertDialog(
      title: Text('Delete $name?', style: TextStyle(color: error)),
      content: const Text(
        'This block and its planned weeks will be removed from the split. '
        'No workouts are logged in it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: error,
            foregroundColor: onColor(error),
          ),
          child: const Text('Delete'),
        ),
      ],
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

/// The block sheet. Picking, it chooses a block and week for a new workout;
/// managing ([picking] false) it only lists blocks. Either way it can create
/// and edit blocks when [onCreateBlock] / [onEditBlock] are supplied, and
/// re-reads the split through [load] afterwards.
class _StartingWeek extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Map<String, List<TrainingWeek>> weeksByBlock;
  final String? selectedWeekId;
  final String? currentBlockId;
  final bool picking;
  final TrainingBlockSnapshot Function()? load;
  final Future<TrainingBlock> Function(String name, int count)? onCreateBlock;
  final Future<TrainingBlock> Function(
    TrainingBlock block,
    String name,
    int? count,
  )?
  onEditBlock;
  final TrainingBlockLifecycle? lifecycle;
  const _StartingWeek({
    required this.blocks,
    required this.weeksByBlock,
    this.selectedWeekId,
    this.currentBlockId,
    this.picking = true,
    this.load,
    this.onCreateBlock,
    this.onEditBlock,
    this.lifecycle,
  });
  @override
  State<_StartingWeek> createState() => _StartingWeekState();
}

class _StartingWeekState extends State<_StartingWeek> {
  final _selectedChip = GlobalKey();
  late List<TrainingBlock> _blocks;
  late Map<String, List<TrainingWeek>> _weeks;
  String? _block;
  String? _week;

  bool get _canManage =>
      widget.load != null &&
      widget.onCreateBlock != null &&
      widget.onEditBlock != null;

  /// Starting-week choices include intended slots without persisting them.
  Map<String, List<TrainingWeek>> _planned(
    List<TrainingBlock> blocks,
    Map<String, List<TrainingWeek>> weeks,
  ) => {
    for (final block in blocks)
      block.id: plannedTrainingWeeks(block, weeks[block.id] ?? []),
  };

  List<TrainingBlock> get _choices =>
      widget.picking
          ? _blocks.where((b) => (_weeks[b.id] ?? []).isNotEmpty).toList()
          : _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = widget.blocks;
    _weeks = _planned(widget.blocks, widget.weeksByBlock);
    _week = widget.selectedWeekId;
    _settleSelection();
    _scrollToSelection();
  }

  void _scrollToSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _selectedChip.currentContext;
      if (mounted && chip != null) {
        Scrollable.ensureVisible(chip, alignment: .5);
      }
    });
  }

  /// Keeps the selection on a week that exists. A week removed by shortening
  /// leaves the block's last week selected; a deleted block leaves the first
  /// remaining block's first week.
  void _settleSelection() {
    final choices = _choices;
    final owner =
        _week == null
            ? null
            : choices
                .where((b) => _weeks[b.id]!.any((w) => w.id == _week))
                .firstOrNull;
    if (owner != null) {
      _block = owner.id;
      return;
    }
    final kept = choices.where((b) => b.id == _block).firstOrNull;
    final fallback = kept ?? choices.firstOrNull;
    _block = fallback?.id;
    _week =
        fallback == null
            ? null
            : (kept == null
                    ? _weeks[fallback.id]!.first
                    : _weeks[kept.id]!.last)
                .id;
  }

  void _chooseBlock(String id) {
    if (id == _block) return;
    setState(() {
      _block = id;
      _week = _weeks[id]!.first.id;
    });
  }

  void _reload() {
    final snapshot = widget.load!();
    setState(() {
      _blocks = snapshot.blocks;
      _weeks = _planned(snapshot.blocks, snapshot.weeksByBlock);
      _settleSelection();
    });
  }

  int _lengthOf(TrainingBlock block) =>
      trainingBlockLength(block, _weeks[block.id] ?? const []);

  Future<void> _create() async {
    final created = await TrainingBlockDialogs.create(
      context,
      onSave: widget.onCreateBlock!,
    );
    if (created == null || !mounted) return;
    _reload();
    if (widget.picking && (_weeks[created.id] ?? []).isNotEmpty) {
      _chooseBlock(created.id);
      _scrollToSelection();
    }
  }

  Future<void> _edit(TrainingBlock block) async {
    final lifecycle = widget.lifecycle;
    final lifecycleOn = lifecycle != null && lifecycle.available();
    final blocker = lifecycleOn ? lifecycle.deleteBlocker(block) : null;
    final result = await TrainingBlockDialogs.edit(
      context,
      block,
      currentWeekCount: _lengthOf(block),
      minimumWeekCount: lifecycleOn ? lifecycle.minimumWeekCount(block) : null,
      onSave: (name, count) => widget.onEditBlock!(block, name, count),
      onDelete: lifecycleOn ? () => lifecycle.delete(block) : null,
      deleteUnavailableReason:
          blocker == null ? null : TrainingBlockDialogs.blockerMessage(blocker),
    );
    if (result == null || !mounted) return;
    _reload();
    if (result is TrainingBlockDeleted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${result.name} deleted')));
    }
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
                    widget.picking ? 'Choose starting week' : 'Training blocks',
                    style: textTheme.titleLarge?.copyWith(
                      color: textPrimaryColor(context),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.picking
                      ? 'This workout starts here. Later weeks appear as you '
                          'complete it.'
                      : widget.lifecycle?.available() ?? false
                      ? 'Rename a block, change its length, or delete it.'
                      : 'Add weeks or rename a block. Weeks can be added but '
                          'not removed.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: textSecondary,
                    height: 1.45,
                  ),
                ),
                if (_canManage) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Blocks are shared by every workout in this split. '
                    'Changes to a block save right away, not with Save or '
                    'Discard.',
                    style: textTheme.bodySmall?.copyWith(
                      color: textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
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
                        _weeks[block.id]!,
                      ),
                      note:
                          !widget.picking && block.id == widget.currentBlockId
                              ? 'Current block'
                              : null,
                      selected:
                          widget.picking
                              ? block.id == _block
                              : block.id == widget.currentBlockId,
                      onTap:
                          widget.picking ? () => _chooseBlock(block.id) : null,
                      onEdit: _canManage ? () => _edit(block) : null,
                      weeks: [
                        if (widget.picking)
                          for (final week in _weeks[block.id]!)
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
                  if (_canManage)
                    OutlinedButton.icon(
                      onPressed: _create,
                      icon: const Icon(LucideIcons.plus, size: 18),
                      label: const Text('Create block'),
                    ),
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
            child:
                widget.picking
                    ? Row(
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
                    )
                    : ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
          ),
        ],
      ),
    );
  }
}

/// One block in the sheet. When picking, the chosen block opens to show its
/// weeks, so the two choices read as one decision rather than two dropdowns.
/// When managing, [selected] marks the current block and [onEdit] edits it.
class _StartBlockTile extends StatelessWidget {
  final String name;
  final String caption;
  final String? note;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final List<Widget> weeks;

  const _StartBlockTile({
    required this.name,
    required this.caption,
    required this.selected,
    required this.onTap,
    required this.weeks,
    this.note,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);
    final textTheme = Theme.of(context).textTheme;
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
            button: onTap != null,
            selected: selected,
            child: InkWell(
              onTap: onTap,
              borderRadius:
                  selected && weeks.isNotEmpty
                      ? AppRadius.cardTop
                      : AppRadius.card,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: AppSpacing.md,
                    right: onEdit == null ? AppSpacing.md : AppSpacing.xs,
                    top: AppSpacing.sm,
                    bottom: AppSpacing.sm,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight:
                                    selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                color: textPrimaryColor(context),
                              ),
                            ),
                            if (note != null)
                              Text(
                                note!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: textSecondary,
                                ),
                              ),
                          ],
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
                      if (onEdit != null)
                        IconButton(
                          tooltip: 'Edit $name',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: onEdit,
                          icon: Icon(
                            LucideIcons.pencilLine,
                            size: 20,
                            color: accent,
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
                selected && weeks.isNotEmpty
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
