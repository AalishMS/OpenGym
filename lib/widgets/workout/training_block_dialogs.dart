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
import '../../theme/motion.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../motion/app_modals.dart';
import '../motion/collapsible.dart';
import '../motion/state_switcher.dart';
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
  }) => showAppSheet<String>(
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
    return showAppSheet<void>(
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
      await _showBlockSheet<Object>(
            context,
            _BlockForm(
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
    final result = await _showBlockSheet<Object>(
      context,
      _BlockForm(
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
  }) => _showBlockSheet<void>(
    context,
    _BlockOrder(blocks: blocks, onSave: onSave),
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
    // A pill rather than a boxed field: it names the block and week in one
    // line, and the whole thing opens the block sheet.
    return Semantics(
      button: enabled,
      child: Material(
        color: controlFillColor(context),
        borderRadius: AppRadius.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm + AppSpacing.xxs,
                AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: textTheme.bodyMedium?.copyWith(color: textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      value,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: textPrimaryColor(context),
                      ),
                    ),
                  ),
                  if (enabled) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal inset of everything inside a block sheet.
const double _sheetGutter = AppSpacing.lg + AppSpacing.xs;

/// The title block at the top of every block sheet — a large title, a
/// supporting line and an optional footnote — so picking, creating, editing
/// and reordering read as one family.
class _SheetHeader extends StatelessWidget {
  final String title;
  final String? description;
  final String? footnote;

  const _SheetHeader({required this.title, this.description, this.footnote});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: textTheme.titleLarge?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: textPrimaryColor(context),
            ),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            description!,
            style: textTheme.bodyMedium?.copyWith(
              color: secondary,
              height: 1.45,
            ),
          ),
        ],
        if (footnote != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            footnote!,
            style: textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

/// Two equal buttons at the foot of a sheet — the quiet one first — tall
/// enough to be the obvious end of the sheet.
class _SheetActions extends StatelessWidget {
  final Widget secondary;
  final Widget primary;

  const _SheetActions({required this.secondary, required this.primary});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: secondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: primary),
        ],
      ),
    ),
  );
}

/// Shows [child] as a modal block sheet: drag handle, keyboard-aware, scrolls
/// when the content outgrows the screen.
Future<T?> _showBlockSheet<T>(BuildContext context, Widget child) =>
    showAppSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheetContext) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: child,
          ),
    );

/// Header, body, error and actions laid out as a sheet's content.
class _SheetFrame extends StatelessWidget {
  final String title;
  final String description;
  final Widget body;
  final String? error;
  final Widget secondaryAction;
  final Widget primaryAction;

  const _SheetFrame({
    required this.title,
    required this.description,
    required this.body,
    required this.secondaryAction,
    required this.primaryAction,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: _sheetGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SheetHeader(title: title, description: description),
                  const SizedBox(height: AppSpacing.xl),
                  body,
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ErrorLine(error!),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              _sheetGutter,
              AppSpacing.lg,
              _sheetGutter,
              _sheetGutter + MediaQuery.paddingOf(context).bottom,
            ),
            child: _SheetActions(
              secondary: secondaryAction,
              primary: primaryAction,
            ),
          ),
        ],
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

  /// Called with the result instead of popping a route, when the form is
  /// shown inside the block sheet rather than in a sheet of its own. Cancel
  /// and back then return to the block list.
  final ValueChanged<Object?>? onClose;
  const _BlockForm({
    super.key,
    this.initialName,
    required this.initialWeekCount,
    this.minWeekCount = 1,
    this.lifecycle = false,
    required this.onSave,
    this.onDelete,
    this.deleteUnavailableReason,
    this.onClose,
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

  void _close(Object? result) {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
    } else {
      Navigator.pop(context, result);
    }
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
      if (mounted) _close(_creating ? result : TrainingBlockSaved(result));
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
    final confirmed = await showAppDialog<bool>(
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
      if (mounted) _close(TrainingBlockDeleted(name));
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
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    // A key that can't be pressed sinks into the track: no raised disc, a
    // faded glyph. Keeping the disc made a dead "−" look exactly as live as
    // the "+" beside it.
    final stepStyle = IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      backgroundColor: _stepperKeyColor(context),
      foregroundColor: textPrimaryColor(context),
      disabledBackgroundColor: Colors.transparent,
      disabledForegroundColor: textSecondaryColor(context).withAlpha(120),
      shape: const CircleBorder(),
    );
    final embedded = widget.onClose != null;
    return PopScope(
      // Inside the block sheet, back steps out to the block list.
      canPop: !embedded && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && embedded && !_busy) _close(null);
      },
      child: _SheetFrame(
        title: _creating ? 'Create block' : 'Edit block',
        description: _description,
        error: _error,
        body: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_busy,
                maxLength: 40,
                autofocus: _creating,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: textPrimaryColor(context),
                ),
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
              // One control, not three boxes: the steppers sit inside the
              // same fill as the figure they change.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: controlFillColor(context),
                  borderRadius: AppRadius.card,
                ),
                child: Row(
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
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: textPrimaryColor(context),
                        ),
                        decoration: InputDecoration(
                          labelText: 'Weeks',
                          isDense: true,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          floatingLabelAlignment: FloatingLabelAlignment.center,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          floatingLabelStyle: textTheme.labelMedium?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w700,
                          ),
                          errorMaxLines: 3,
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
              ),
              if (weeks != null && weeks >= 1 && weeks <= _maxWeeks) ...[
                const SizedBox(height: AppSpacing.md),
                _WeekTrack(
                  count: weeks,
                  // Only an edit knows which weeks are spoken for.
                  fixed: _creating ? 0 : _minWeeks,
                ),
              ],
              if (!_creating && widget.lifecycle && !_canShorten) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Every week here has been reached, so this block can\'t '
                  'be shorter.',
                  style: textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ] else if (_canShorten && _minWeeks > 1) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Weeks 1–$_minWeeks have been reached, so $_minWeeks is the '
                  'shortest it can be.',
                  style: textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ],
              if (_canDelete) ...[
                const SizedBox(height: AppSpacing.lg),
                Divider(height: 1, color: hairlineColor(context)),
                const SizedBox(height: AppSpacing.sm),
                _DeleteBlockButton(
                  deleting: _deleting,
                  onPressed:
                      _busy || widget.deleteUnavailableReason != null
                          ? null
                          : _delete,
                ),
                if (widget.deleteUnavailableReason != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.sm + 18 + AppSpacing.sm,
                    ),
                    child: Text(
                      widget.deleteUnavailableReason!,
                      style: textTheme.bodySmall?.copyWith(color: secondary),
                    ),
                  ),
              ],
            ],
          ),
        ),
        secondaryAction: OutlinedButton(
          onPressed: _busy ? null : () => _close(null),
          child: const Text('Cancel'),
        ),
        primaryAction: _SaveButton(
          label: _creating ? 'Create' : 'Save',
          saving: _saving,
          onPressed: _busy ? null : _save,
        ),
      ),
    );
  }
}

/// The steppers' own ground: a step lighter than the control fill they sit
/// in — white on light grey, lifted grey on dark.
Color _stepperKeyColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(controlFillColor(context), textPrimaryColor(context), .08)!
        : surfaceColor(context);

/// The block's weeks as a row of bars: the ones already reached in the
/// accent, the ones still only planned in its quiet wash. It answers, before
/// anyone asks, why the block won't go shorter. Planned weeks are filled
/// rather than outlined: an outlined bar reads as an empty slot, and a new
/// block is nothing but planned weeks.
class _WeekTrack extends StatelessWidget {
  final int count;

  /// How many leading weeks can't be removed.
  final int fixed;

  const _WeekTrack({required this.count, required this.fixed});

  @override
  Widget build(BuildContext context) {
    // Past a dozen weeks the bars get too thin to read as weeks.
    if (count > 16) return const SizedBox.shrink();
    final secondary = textSecondaryColor(context);
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var week = 1; week <= count; week++) ...[
            if (week > 1) const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color:
                          week <= fixed
                              ? accentFillColor(context)
                              : accentMutedColor(context),
                      borderRadius: AppRadius.badge,
                    ),
                  ),
                  if (count <= 8) ...[
                    const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                    Text(
                      '$week',
                      style: AppTypography.figures(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The destructive entry point in Edit block: a quiet row in the error colour,
/// set apart from Cancel and Save, disabled rather than hidden when the block
/// can't be deleted.
class _DeleteBlockButton extends StatelessWidget {
  final bool deleting;
  final VoidCallback? onPressed;
  const _DeleteBlockButton({required this.deleting, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final error = errorColor(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: error,
          disabledForegroundColor: error.withAlpha(110),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          overlayColor: error,
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
      ),
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
    return PopScope(
      canPop: !_saving,
      child: _SheetFrame(
        title: 'Reorder blocks',
        description:
            'Hold and drag a block, or use the arrows. Its weeks and logs '
            'move with it.',
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
                        shadowColor: Theme.of(context).colorScheme.shadow,
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
                  duration: AppMotion.of(context, AppMotion.quick),
                  curve: AppMotion.curve,
                  decoration: BoxDecoration(
                    border:
                        index == _blocks.length - 1
                            ? null
                            : Border(
                              bottom: BorderSide(color: hairlineColor(context)),
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
        secondaryAction: OutlinedButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        primaryAction: _SaveButton(
          label: 'Save',
          saving: _saving,
          onPressed: _changed ? _save : null,
        ),
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

  /// The create or edit form showing in place of the block list, if any.
  /// Editing happens inside this sheet, so only one layer is ever open.
  Widget? _form;

  void _create() {
    setState(
      () =>
          _form = _BlockForm(
            key: const ValueKey('create-block'),
            onSave: (name, count) => widget.onCreateBlock!(name, count!),
            initialWeekCount: kDefaultBlockWeeks,
            onClose: _created,
          ),
    );
  }

  void _created(Object? result) {
    setState(() => _form = null);
    final created = result as TrainingBlock?;
    if (created == null || !mounted) return;
    _reload();
    if (widget.picking && (_weeks[created.id] ?? []).isNotEmpty) {
      _chooseBlock(created.id);
      _scrollToSelection();
    }
  }

  void _edit(TrainingBlock block) {
    final lifecycle = widget.lifecycle;
    final lifecycleOn = lifecycle != null && lifecycle.available();
    final blocker = lifecycleOn ? lifecycle.deleteBlocker(block) : null;
    final length = _lengthOf(block);
    final minimum = lifecycleOn ? lifecycle.minimumWeekCount(block) : null;
    setState(
      () =>
          _form = _BlockForm(
            key: ValueKey('edit-${block.id}'),
            initialName: block.name,
            initialWeekCount: length,
            minWeekCount: (minimum ?? length).clamp(1, length),
            lifecycle: lifecycleOn,
            onSave: (name, count) => widget.onEditBlock!(block, name, count),
            onDelete: lifecycleOn ? () => lifecycle.delete(block) : null,
            deleteUnavailableReason:
                blocker == null
                    ? null
                    : TrainingBlockDialogs.blockerMessage(blocker),
            onClose: _edited,
          ),
    );
  }

  void _edited(Object? result) {
    setState(() => _form = null);
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
    // The list and a form trade places in the sheet, which eases to the new
    // height from its bottom edge; the side going away takes no more taps.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: StateSwitcher(
        animateSize: true,
        alignment: Alignment.bottomCenter,
        child:
            _form ??
            KeyedSubtree(
              key: const ValueKey('blocks'),
              child: _list(context),
            ),
      ),
    );
  }

  Widget _list(BuildContext context) {
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
            padding: const EdgeInsets.symmetric(horizontal: _sheetGutter),
            child: _SheetHeader(
              title:
                  widget.picking ? 'Choose starting week' : 'Training blocks',
              description:
                  widget.picking
                      ? 'This workout starts here. Later weeks appear as you '
                          'complete it.'
                      : widget.lifecycle?.available() ?? false
                      ? 'Rename a block, change its length, or delete it.'
                      : 'Add weeks or rename a block. Weeks can be added but '
                          'not removed.',
              footnote:
                  _canManage
                      ? 'Blocks are shared by every workout in this split. '
                          'Changes to a block save right away, not with Save '
                          'or Discard.'
                      : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < choices.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent:
                            _sheetGutter + _BlockRow.markSize + AppSpacing.md,
                        color: hairlineColor(context),
                      ),
                    _blockRow(choices[i]),
                  ],
                  if (_canManage) _CreateBlockRow(onTap: _create),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              _sheetGutter,
              AppSpacing.md,
              _sheetGutter,
              _sheetGutter + MediaQuery.paddingOf(context).bottom,
            ),
            child:
                widget.picking
                    ? _SheetActions(
                      secondary: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      primary: ElevatedButton(
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
                    )
                    : ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _blockRow(TrainingBlock block) {
    final current = !widget.picking && block.id == widget.currentBlockId;
    final edit = _canManage ? () => _edit(block) : null;
    return _BlockRow(
      name: block.name,
      caption: trainingBlockLengthLabel(block, _weeks[block.id]!),
      note: current ? 'Current block' : null,
      picking: widget.picking,
      selected: widget.picking ? block.id == _block : current,
      // Managing has nothing to choose, so the whole row edits the block.
      onTap: widget.picking ? () => _chooseBlock(block.id) : edit,
      onEdit: edit,
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
    );
  }
}

/// One block in the sheet: a row on the sheet, not a tile in it. When picking,
/// the chosen block opens to show its weeks, so the two choices read as one
/// decision. When managing, [selected] marks the current block with a check
/// and tapping the row edits it.
class _BlockRow extends StatelessWidget {
  /// The leading check or ring.
  static const double markSize = 22;

  final String name;
  final String caption;
  final String? note;

  /// Whether the rows are choices. Only then do the others carry an empty
  /// ring: a ring that does nothing when tapped promises a choice that isn't
  /// there.
  final bool picking;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final List<Widget> weeks;

  const _BlockRow({
    required this.name,
    required this.caption,
    required this.picking,
    required this.selected,
    required this.onTap,
    required this.weeks,
    this.note,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final fill = accentFillColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: onTap != null,
          selected: selected,
          onTapHint: picking || onTap == null ? null : 'Edit block',
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _sheetGutter,
                  AppSpacing.sm,
                  onEdit == null ? _sheetGutter : AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.of(context, AppMotion.quick),
                      curve: AppMotion.curve,
                      width: markSize,
                      height: markSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? fill : null,
                        border:
                            selected || !picking
                                ? null
                                : Border.all(
                                  color: borderColor(context),
                                  width: 1.75,
                                ),
                      ),
                      child:
                          selected
                              ? Icon(
                                LucideIcons.check,
                                size: 14,
                                color: onAccentColor(context),
                              )
                              : null,
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
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: textPrimaryColor(context),
                            ),
                          ),
                          Wrap(
                            children: [
                              Text(
                                caption,
                                style: AppTypography.figures(
                                  fontSize: 13,
                                  color: secondary,
                                ),
                              ),
                              if (note != null) ...[
                                Text(
                                  '  ·  ',
                                  style: textTheme.bodySmall?.copyWith(
                                    fontSize: 13,
                                    color: secondary,
                                  ),
                                ),
                                Text(
                                  note!,
                                  style: textTheme.bodySmall?.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor(context),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (onEdit != null)
                      IconButton(
                        tooltip: 'Edit $name',
                        onPressed: onEdit,
                        color: secondary,
                        icon: const Icon(LucideIcons.pencilLine, size: 20),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The chosen block opens to show its weeks; the one left folds away.
        Collapsible(
          open: selected && weeks.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _sheetGutter + markSize + AppSpacing.md,
              0,
              _sheetGutter,
              AppSpacing.md,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: weeks,
            ),
          ),
        ),
      ],
    );
  }
}

/// Create block, as the last row of the list rather than one more box.
class _CreateBlockRow extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateBlockRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _sheetGutter),
            child: Row(
              children: [
                Container(
                  width: _BlockRow.markSize,
                  height: _BlockRow.markSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentMutedColor(context),
                  ),
                  // Accent ink on the accent's wash, like the label beside it
                  // and the tonal button: one colour for "add".
                  child: Icon(
                    LucideIcons.plus,
                    size: 14,
                    color: accentOnMutedColor(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  'Create block',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final ground =
        selected ? accentFillColor(context) : controlFillColor(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: ground,
        borderRadius: AppRadius.pill,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            // The same height as the other pills in the block flow.
            constraints: const BoxConstraints(minHeight: 44, minWidth: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Week $number',
                  style: AppTypography.figures(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
