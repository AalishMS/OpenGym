import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/set.dart' as gym;
import '../../providers/settings_provider.dart';
import '../../services/exercise_catalog.dart';
import '../../theme/app_typography.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../utils/statistics_format.dart';
import '../app_button.dart';
import '../motion/app_modals.dart';
import 'set_entry_table.dart';

class WorkoutDialogs {
  static void showAddSetDialog(
    BuildContext context, {
    gym.Set? lastSet,
    String? exerciseName,
    String? exerciseId,
    required void Function(gym.Set newSet) onAdd,
  }) {
    final isTimed = ExerciseCatalog.isTimed(exerciseName ?? '', exerciseId);
    final settings = context.read<SettingsProvider>();

    // Kilograms, as stored; the entry table shows them in the chosen unit.
    final draft = _SetDraft(
      weight: lastSet?.weight,
      reps: lastSet?.reps ?? (isTimed ? 30 : 8),
    );
    int? selectedRpe = settings.autoFillLast ? lastSet?.rpe : null;

    showAppDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: surfaceColor(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add set',
                        style: Theme.of(context).dialogTheme.titleTextStyle,
                      ),
                      const SizedBox(height: 12),
                      _DialogSetEntry(
                        draft: draft,
                        isTimed: isTimed,
                        showHistoryColumns: false,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'RPE (Rate of Perceived Exertion)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: List.generate(10, (index) {
                          final rpe = index + 1;
                          return Semantics(
                            button: true,
                            container: true,
                            label: 'RPE $rpe',
                            selected: selectedRpe == rpe,
                            onTap: () {
                              setDialogState(() {
                                selectedRpe = selectedRpe == rpe ? null : rpe;
                              });
                            },
                            child: InkWell(
                              onTap: () {
                                setDialogState(() {
                                  selectedRpe = selectedRpe == rpe ? null : rpe;
                                });
                              },
                              borderRadius: AppRadius.chip,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color:
                                      selectedRpe == rpe
                                          ? accentFillColor(context)
                                          : controlFillColor(context),
                                  borderRadius: AppRadius.chip,
                                ),
                                child: Center(
                                  child: Text(
                                    '$rpe',
                                    style: AppTypography.figures(
                                      fontSize: 12,
                                      color:
                                          selectedRpe == rpe
                                              ? onAccentColor(context)
                                              : textPrimaryColor(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              final weight = draft.weight;
                              final reps = draft.reps;

                              if (weight == null || weight < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Weight must be 0 or more',
                                    ),
                                    backgroundColor: errorColor(context),
                                  ),
                                );
                                return;
                              }

                              if (reps == null || reps <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isTimed
                                          ? 'Seconds must be greater than 0'
                                          : 'Reps must be greater than 0',
                                    ),
                                    backgroundColor: errorColor(context),
                                  ),
                                );
                                return;
                              }

                              final newSet = gym.Set(
                                reps: reps,
                                weight: weight,
                                rpe: selectedRpe,
                                note: null,
                              );

                              Navigator.pop(context);
                              onAdd(newSet);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentFillColor(context),
                              foregroundColor: onAccentColor(context),
                            ),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void showEditSetDialog(
    BuildContext context, {
    required gym.Set set,
    String? exerciseName,
    String? exerciseId,
    required void Function(gym.Set updatedSet) onSave,
    required VoidCallback onDelete,
  }) {
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder:
          (_) => _EditSetSheet(
            set: set,
            isTimed: ExerciseCatalog.isTimed(exerciseName ?? '', exerciseId),
            onSave: onSave,
            onDelete: onDelete,
          ),
    );
  }

  static void showExerciseNoteDialog(
    BuildContext context, {
    String? currentNote,
    required void Function(String? note) onSave,
  }) {
    final noteController = TextEditingController(text: currentNote ?? '');

    showAppDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: surfaceColor(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Note',
                    style: Theme.of(context).dialogTheme.titleTextStyle,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'Add a note...',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onSave(
                            noteController.text.isNotEmpty
                                ? noteController.text
                                : null,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentFillColor(context),
                          foregroundColor: onAccentColor(context),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// A held week tab's menu, shaped like a plan's: a header naming the week,
  /// then Delete week under a rule in the error colour.
  static void showWeekActions(
    BuildContext context, {
    required int week,
    required String blockName,
    required VoidCallback onDelete,
  }) {
    final error = errorColor(context);
    showAppSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheet) => SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(sheet).bottom + AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Week $week',
                          style: Theme.of(sheet).textTheme.titleSmall?.copyWith(
                            color: textPrimaryColor(sheet),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          blockName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheet).textTheme.bodySmall?.copyWith(
                            color: textSecondaryColor(sheet),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: borderColor(sheet)),
                  InkWell(
                    onTap: () {
                      Navigator.pop(sheet);
                      onDelete();
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                          horizontal: AppSpacing.lg,
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.trash2, size: 16, color: error),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'Delete week',
                                style: Theme.of(
                                  sheet,
                                ).textTheme.bodyMedium?.copyWith(color: error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// [logged] picks the wording: a logged workout also leaves History and
  /// records, while an unlogged one only loses the sets entered so far.
  static Future<bool> showDeleteWeekDialog(
    BuildContext context, {
    required int week,
    bool logged = true,
  }) => _showDestructiveConfirmation(
    context,
    title: 'Delete week?',
    message:
        logged
            ? 'Week $week\'s logged workout will be removed from History, '
                'Stats and personal records.'
            : 'The sets entered for week $week will be removed. This workout '
                'hasn\'t been logged, so History and records won\'t change.',
    confirmLabel: 'Delete',
  );

  static Future<bool> showDeleteExerciseDialog(
    BuildContext context, {
    required String exerciseName,

    /// The workout being trained now: the next week starts from its lineup.
    bool carriesOver = false,
  }) => _showDestructiveConfirmation(
    context,
    title: 'Delete exercise?',
    message:
        'This will permanently delete "$exerciseName" and all its sets.'
        '${carriesOver ? ' Next week will start without it too.' : ''}',
    confirmLabel: 'Delete',
  );

  /// Confirms removing a plan while retaining logged sessions in History.
  static Future<bool> showDeletePlanDialog(
    BuildContext context, {
    required String planName,
  }) => _showDestructiveConfirmation(
    context,
    title: 'Delete plan?',
    message:
        'Removes "$planName" from your plans. Logged sessions stay in History.',
    confirmLabel: 'Delete',
  );

  /// Confirms deleting a logged workout and runs [delete] from the dialog, so
  /// its progress and any failure show where the choice was made. Returns
  /// true once the workout is deleted.
  static Future<bool> showDeleteLoggedWorkoutDialog(
    BuildContext context, {
    required String planName,
    required DateTime date,
    required Future<void> Function() delete,
  }) async {
    var deleting = false;
    var deleted = false;
    String? error;
    await showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => PopScope(
                  canPop: !deleting,
                  child: AlertDialog(
                    title: const Text('Delete workout?'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete “$planName” from ${formatStatisticsDate(date)}? '
                          'It will be removed from History, Stats and personal '
                          'records.',
                        ),
                        if (error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            error!,
                            key: const ValueKey('delete-workout-error'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: errorColor(context)),
                          ),
                        ],
                      ],
                    ),
                    actions: [
                      AppButton.text(
                        label: 'Cancel',
                        onPressed:
                            deleting
                                ? null
                                : () => Navigator.pop(dialogContext),
                      ),
                      AppButton.destructive(
                        label: 'Delete',
                        onPressed:
                            deleting
                                ? null
                                : () async {
                                  setDialogState(() {
                                    deleting = true;
                                    error = null;
                                  });
                                  try {
                                    await delete();
                                    deleted = true;
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext);
                                    }
                                  } catch (exception) {
                                    debugPrint(
                                      'Failed to delete workout: $exception',
                                    );
                                    if (!dialogContext.mounted) return;
                                    setDialogState(() {
                                      deleting = false;
                                      error =
                                          'Could not delete the workout. Check your data and try again.';
                                    });
                                  }
                                },
                        child:
                            deleting
                                ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : null,
                      ),
                    ],
                  ),
                ),
          ),
    );
    return deleted;
  }

  static Future<bool> showDiscardChangesDialog(BuildContext context) =>
      _showDestructiveConfirmation(
        context,
        title: 'Discard changes?',
        message: 'This plan has unsaved edits. Leaving now throws them away.',
        cancelLabel: 'Keep editing',
        confirmLabel: 'Discard',
      );

  static Future<bool> _showDestructiveConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
  }) async {
    final result = await showAppDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(
              title,
              style: TextStyle(color: errorColor(dialogContext)),
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(cancelLabel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: errorColor(dialogContext),
                  foregroundColor: onColor(errorColor(dialogContext)),
                ),
                child: Text(confirmLabel),
              ),
            ],
          ),
    );
    return result ?? false;
  }
}

/// Numeric drafts use the same keypad as the inline rows; notes can still use
/// the system text keyboard. The surrounding dialog owns save/cancel behavior.
class _EditSetSheet extends StatefulWidget {
  final gym.Set set;
  final bool isTimed;
  final ValueChanged<gym.Set> onSave;
  final VoidCallback onDelete;

  const _EditSetSheet({
    required this.set,
    this.isTimed = false,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  // The stored kilograms at full precision. A text field in between rounded
  // them to two decimals, which rewrote a weight typed in pounds on every save.
  late final _SetDraft _draft = _SetDraft(
    weight: widget.set.weight,
    reps: widget.set.reps,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.set.note ?? '',
  );
  late int? _rpe = widget.set.rpe;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final weight = _draft.weight;
    final reps = _draft.reps;
    if (weight == null || weight < 0 || reps == null || reps <= 0) {
      setState(
        () =>
            _error =
                widget.isTimed
                    ? 'Enter a valid weight and at least one second.'
                    : 'Enter a valid weight and at least one rep.',
      );
      return;
    }
    final updated = gym.Set(
      weight: weight,
      reps: reps,
      rpe: _rpe,
      note: _note.text.isEmpty ? null : _note.text,
    );
    Navigator.pop(context);
    widget.onSave(updated);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit set', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            _DialogSetEntry(
              draft: _draft,
              isTimed: widget.isTimed,
              showHistoryColumns: false,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('RPE', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder:
                  (context, constraints) => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (var rpe = 1; rpe <= 10; rpe++)
                        Semantics(
                          label: 'RPE $rpe',
                          selected: _rpe == rpe,
                          button: true,
                          excludeSemantics: true,
                          onTap:
                              () => setState(
                                () => _rpe = _rpe == rpe ? null : rpe,
                              ),
                          child: SizedBox(
                            width: ((constraints.maxWidth - 32) / 5).clamp(
                              48.0,
                              double.infinity,
                            ),
                            height: 48,
                            child: OutlinedButton(
                              onPressed:
                                  () => setState(
                                    () => _rpe = _rpe == rpe ? null : rpe,
                                  ),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor:
                                    _rpe == rpe
                                        ? accentFillColor(context)
                                        : null,
                                foregroundColor:
                                    _rpe == rpe
                                        ? onAccentColor(context)
                                        : textPrimaryColor(context),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: AppRadius.chip,
                                ),
                              ),
                              child: Text('$rpe'),
                            ),
                          ),
                        ),
                    ],
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              minLines: 1,
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: errorColor(context)),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: errorColor(context),
                  ),
                  child: const Text('Delete'),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDelete();
                  },
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: AppSpacing.sm,
                    overflowSpacing: AppSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentFillColor(context),
                          foregroundColor: onAccentColor(context),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A set being drafted in a dialog: kilograms and reps, null until known.
class _SetDraft {
  double? weight;
  int? reps;

  _SetDraft({this.weight, this.reps});
}

class _DialogSetEntry extends StatefulWidget {
  final _SetDraft draft;
  final bool isTimed;
  final bool showHistoryColumns;

  const _DialogSetEntry({
    required this.draft,
    this.isTimed = false,
    this.showHistoryColumns = true,
  });

  @override
  State<_DialogSetEntry> createState() => _DialogSetEntryState();
}

class _DialogSetEntryState extends State<_DialogSetEntry> {
  @override
  Widget build(BuildContext context) => SetEntryTable(
    isTimed: widget.isTimed,
    showHistoryColumns: widget.showHistoryColumns,
    sets: [
      SetEntry(weight: widget.draft.weight ?? 0, reps: widget.draft.reps ?? 0),
    ],
    onChanged:
        (index, weight, reps) => setState(() {
          widget.draft
            ..weight = weight
            ..reps = reps;
        }),
  );
}
