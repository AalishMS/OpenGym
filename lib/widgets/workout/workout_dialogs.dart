import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/set.dart' as gym;
import '../../providers/settings_provider.dart';
import '../../services/pr_tracking_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'set_entry_table.dart';

class WorkoutDialogs {
  static void showPRDialog(BuildContext context, List<PRResult> prs) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: surfaceColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: borderColor(context), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    ...prs.map(
                      (pr) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pr.exerciseName,
                              style: GoogleFonts.jetBrainsMono(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${pr.newPR} kg · was ${pr.previousPR} kg',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: textSecondaryColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentFillColor(context),
                          foregroundColor: onAccentColor(context),
                        ),
                        child: Text(
                          'Got it',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  static void showRenameExerciseDialog(
    BuildContext context, {
    required String currentName,
    required void Function(String name) onRename,
  }) {
    final accent = accentColor(context);
    final nameController = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: surfaceColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: borderColor(context), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rename exercise',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Exercise name',
                        enabledBorder: OutlineInputBorder(
                          borderRadius: AppRadius.field,
                          borderSide: BorderSide(
                            color: borderColor(context),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: AppRadius.field,
                          borderSide: BorderSide(color: accent, width: 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Enter an exercise name',
                                    style: GoogleFonts.jetBrainsMono(),
                                  ),
                                  backgroundColor: errorColor(context),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(context);
                            onRename(name);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentFillColor(context),
                            foregroundColor: onAccentColor(context),
                          ),
                          child: Text(
                            'Rename',
                            style: GoogleFonts.jetBrainsMono(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  static void showAddSetDialog(
    BuildContext context, {
    gym.Set? lastSet,
    required void Function(gym.Set newSet) onAdd,
  }) {
    final settings = context.read<SettingsProvider>();
    final accent = accentColor(context);

    final weightController = TextEditingController(
      text: lastSet?.weight.toString() ?? '',
    );
    final repsController = TextEditingController(
      text: lastSet?.reps.toString() ?? '8',
    );
    int? selectedRpe = settings.autoFillLast ? lastSet?.rpe : null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: surfaceColor(context),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.card,
                side: BorderSide(color: borderColor(context), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add set',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DialogSetEntry(
                        weightController: weightController,
                        repsController: repsController,
                        showHistoryColumns: false,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'RPE (Rate of Perceived Exertion)',
                        style: GoogleFonts.jetBrainsMono(fontSize: 12),
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
                                          : Colors.transparent,
                                  border: Border.all(
                                    color:
                                        selectedRpe == rpe
                                            ? accentFillColor(context)
                                            : borderColor(context),
                                  ),
                                  borderRadius: AppRadius.chip,
                                ),
                                child: Center(
                                  child: Text(
                                    '$rpe',
                                    style: GoogleFonts.jetBrainsMono(
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
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.jetBrainsMono(
                                color: textSecondaryColor(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              final weight = double.tryParse(
                                weightController.text,
                              );
                              final reps = int.tryParse(repsController.text);

                              if (weight == null || weight < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Weight must be 0 or more',
                                      style: GoogleFonts.jetBrainsMono(),
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
                                      'Reps must be greater than 0',
                                      style: GoogleFonts.jetBrainsMono(),
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
                            child: Text(
                              'Add',
                              style: GoogleFonts.jetBrainsMono(),
                            ),
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
    required void Function(gym.Set updatedSet) onSave,
    required VoidCallback onDelete,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder:
          (_) => _EditSetSheet(set: set, onSave: onSave, onDelete: onDelete),
    );
  }

  static void showExerciseNoteDialog(
    BuildContext context, {
    String? currentNote,
    required void Function(String? note) onSave,
  }) {
    final noteController = TextEditingController(text: currentNote ?? '');
    final accent = accentColor(context);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: surfaceColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: borderColor(context), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Note',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
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
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context),
                          ),
                        ),
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
                        child: Text('Save', style: GoogleFonts.jetBrainsMono()),
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

  static void showWeekOptionsMenu(
    BuildContext context, {
    required void Function() onRename,
    required void Function() onDelete,
  }) {
    final accent = accentColor(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(LucideIcons.pencil, color: accent),
                  title: Text('Rename', style: GoogleFonts.jetBrainsMono()),
                  onTap: () {
                    Navigator.pop(context);
                    onRename();
                  },
                ),
                ListTile(
                  leading: Icon(LucideIcons.trash2, color: errorColor(context)),
                  title: Text(
                    'DELETE',
                    style: GoogleFonts.jetBrainsMono(
                      color: errorColor(context),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete();
                  },
                ),
              ],
            ),
          ),
    );
  }

  static Future<void> showRenameWeekDialog(
    BuildContext context, {
    required int currentWeek,
    required void Function(int newWeek) onRename,
  }) async {
    final newWeek = await showDialog<int>(
      context: context,
      builder: (_) => _RenameWeekDialog(currentWeek: currentWeek),
    );
    if (newWeek != null && context.mounted) onRename(newWeek);
  }

  static Future<bool> showDeleteWeekDialog(
    BuildContext context, {
    required int week,
  }) => _showDestructiveConfirmation(
    context,
    title: 'Delete week?',
    message: 'This will permanently delete this week\'s workout data.',
    confirmLabel: 'Delete',
  );

  static Future<bool> showDeleteExerciseDialog(
    BuildContext context, {
    required String exerciseName,
  }) => _showDestructiveConfirmation(
    context,
    title: 'Delete exercise?',
    message: 'This will permanently delete "$exerciseName" and all its sets.',
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
    final result = await showDialog<bool>(
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
  final ValueChanged<gym.Set> onSave;
  final VoidCallback onDelete;

  const _EditSetSheet({
    required this.set,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  late final TextEditingController _weight = TextEditingController(
    text: entryWeight(widget.set.weight),
  );
  late final TextEditingController _reps = TextEditingController(
    text: '${widget.set.reps}',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.set.note ?? '',
  );
  late int? _rpe = widget.set.rpe;
  String? _error;

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final weight = double.tryParse(_weight.text);
    final reps = int.tryParse(_reps.text);
    if (weight == null || weight < 0 || reps == null || reps <= 0) {
      setState(() => _error = 'Enter a valid weight and at least one rep.');
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
              weightController: _weight,
              repsController: _reps,
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

class _DialogSetEntry extends StatefulWidget {
  final TextEditingController weightController;
  final TextEditingController repsController;
  final bool showHistoryColumns;

  const _DialogSetEntry({
    required this.weightController,
    required this.repsController,
    this.showHistoryColumns = true,
  });

  @override
  State<_DialogSetEntry> createState() => _DialogSetEntryState();
}

class _DialogSetEntryState extends State<_DialogSetEntry> {
  @override
  Widget build(BuildContext context) => SetEntryTable(
    showHistoryColumns: widget.showHistoryColumns,
    sets: [
      SetEntry(
        weight: double.tryParse(widget.weightController.text) ?? 0,
        reps: int.tryParse(widget.repsController.text) ?? 0,
      ),
    ],
    onChanged:
        (index, weight, reps) => setState(() {
          widget.weightController.text = entryWeight(weight);
          widget.repsController.text = '$reps';
        }),
  );
}

class _RenameWeekDialog extends StatefulWidget {
  final int currentWeek;

  const _RenameWeekDialog({required this.currentWeek});

  @override
  State<_RenameWeekDialog> createState() => _RenameWeekDialogState();
}

class _RenameWeekDialogState extends State<_RenameWeekDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentWeek.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final week = int.tryParse(_controller.text);
    if (week == null || week <= 0) {
      setState(() => _error = 'Enter a whole number greater than zero.');
      return;
    }
    Navigator.pop(context, week);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename week'),
    scrollable: true,
    content: TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Week number',
        hintText: 'e.g., 1',
        errorText: _error,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      autofocus: true,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ElevatedButton(onPressed: _submit, child: const Text('Rename')),
    ],
  );
}
