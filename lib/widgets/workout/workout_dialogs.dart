import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/set.dart' as gym;
import '../../providers/settings_provider.dart';
import '../../services/pr_tracking_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../utils/format.dart';
import 'set_entry_table.dart';

class WorkoutDialogs {
  static void showPRDialog(BuildContext context, List<PRResult> prs) {
    final accent = accentColor(context);
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
                      '> NEW PR DETECTED!',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                              '${pr.newPR}kg (Previous: ${pr.previousPR}kg)',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
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
                          '[ACKNOWLEDGE]',
                          style: GoogleFonts.jetBrainsMono(),
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

  static void showAddExerciseDialog(
    BuildContext context, {
    required void Function(String name) onAdd,
  }) {
    final accent = accentColor(context);
    final nameController = TextEditingController();

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
                      '> ADD EXERCISE',
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
                            '[CANCEL]',
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
                                    '> Enter exercise name',
                                    style: GoogleFonts.jetBrainsMono(),
                                  ),
                                  backgroundColor: errorColor(context),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(context);
                            onAdd(name);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentFillColor(context),
                            foregroundColor: onAccentColor(context),
                          ),
                          child: Text(
                            '[ADD]',
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
                      '> RENAME EXERCISE',
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
                            '[CANCEL]',
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
                                    '> Enter exercise name',
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
                            '[RENAME]',
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
                        '> ADD SET',
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
                              '[CANCEL]',
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
                                      '> Weight must be >= 0',
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
                                      '> Reps must be > 0',
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
                              '[ADD]',
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
    final accent = accentColor(context);

    final weightController = TextEditingController(text: set.weight.toString());
    final repsController = TextEditingController(text: set.reps.toString());
    final noteController = TextEditingController(text: set.note ?? '');
    int? selectedRpe = set.rpe;

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
                        '> EDIT SET',
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
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'RPE',
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
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              onDelete();
                            },
                            child: Text(
                              '[DELETE]',
                              style: GoogleFonts.jetBrainsMono(
                                color: errorColor(context),
                              ),
                            ),
                          ),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  '[CANCEL]',
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
                                  final reps = int.tryParse(
                                    repsController.text,
                                  );

                                  if (weight == null ||
                                      weight < 0 ||
                                      reps == null ||
                                      reps <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '> Invalid values',
                                          style: GoogleFonts.jetBrainsMono(),
                                        ),
                                        backgroundColor: errorColor(context),
                                      ),
                                    );
                                    return;
                                  }

                                  final updatedSet = gym.Set(
                                    reps: reps,
                                    weight: weight,
                                    rpe: selectedRpe,
                                    note:
                                        noteController.text.isNotEmpty
                                            ? noteController.text
                                            : null,
                                  );

                                  Navigator.pop(context);
                                  onSave(updatedSet);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentFillColor(context),
                                  foregroundColor: onAccentColor(context),
                                ),
                                child: Text(
                                  '[SAVE]',
                                  style: GoogleFonts.jetBrainsMono(),
                                ),
                              ),
                            ],
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
                    '> NOTE',
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
                          '[CANCEL]',
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
                        child: Text(
                          '[SAVE]',
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
                  title: Text('RENAME', style: GoogleFonts.jetBrainsMono()),
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

  static void showRenameWeekDialog(
    BuildContext context, {
    required int currentWeek,
    required void Function(int newWeek) onRename,
  }) {
    final accent = accentColor(context);
    final controller = TextEditingController(text: currentWeek.toString());
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
                      '> RENAME WEEK',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Week number',
                        hintText: 'e.g., 1',
                      ),
                      keyboardType: TextInputType.number,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final newWeek = int.tryParse(controller.text);
                            if (newWeek != null && newWeek > 0) {
                              Navigator.pop(context);
                              onRename(newWeek);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentFillColor(context),
                            foregroundColor: onAccentColor(context),
                          ),
                          child: Text(
                            '[RENAME]',
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

  static Future<bool> showDeleteWeekDialog(
    BuildContext context, {
    required int week,
  }) async {
    final result = await showDialog<bool>(
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
                      '> DELETE WEEK?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: errorColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This will permanently delete this week\'s workout data.',
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: errorColor(context),
                            foregroundColor: onColor(errorColor(context)),
                          ),
                          child: Text(
                            '[DELETE]',
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
    return result ?? false;
  }

  static Future<bool> showDeleteExerciseDialog(
    BuildContext context, {
    required String exerciseName,
  }) async {
    final result = await showDialog<bool>(
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
                      '> DELETE EXERCISE?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: errorColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This will permanently delete "$exerciseName" and all its sets.',
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: errorColor(context),
                            foregroundColor: onColor(errorColor(context)),
                          ),
                          child: Text(
                            '[DELETE]',
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
    return result ?? false;
  }

  /// Confirms removing a plan from the plans list.
  ///
  /// The body says what actually happens rather than the usual "permanently
  /// delete" boilerplate: [WorkoutPlanProvider.deletePlan] soft-deletes the plan
  /// and leaves every logged session in History.
  static Future<bool> showDeletePlanDialog(
    BuildContext context, {
    required String planName,
  }) async {
    final result = await showDialog<bool>(
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
                      '> DELETE PLAN?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: errorColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Removes "$planName" from your plans. '
                      'Logged sessions stay in History.',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: errorColor(context),
                            foregroundColor: onColor(errorColor(context)),
                          ),
                          child: Text(
                            '[DELETE]',
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
    return result ?? false;
  }

  /// Confirms leaving the plan editor with unsaved edits.
  ///
  /// Destructive in the same sense as [showDeletePlanDialog] — the edits are
  /// gone once you leave — so it borrows the same red-titled shape, and
  /// `[KEEP EDITING]` is the quiet way out because it is the safe one.
  static Future<bool> showDiscardChangesDialog(BuildContext context) async {
    final result = await showDialog<bool>(
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
                      '> DISCARD CHANGES?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: errorColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This plan has unsaved edits. Leaving now throws them away.',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            '[KEEP EDITING]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: errorColor(context),
                            foregroundColor: onColor(errorColor(context)),
                          ),
                          child: Text(
                            '[DISCARD]',
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
    return result ?? false;
  }

  /// Types a weight and reps straight into one prescribed set in the plan
  /// editor.
  ///
  /// The editor's rows adjust by stepper, which is fine for a nudge and awful
  /// for a jump — reaching 70kg from 0 is 28 taps. Tapping the value gets here
  /// instead.
  ///
  /// Deliberately not [showEditSetDialog]: that one edits a logged `gym.Set`
  /// and carries RPE and a note, neither of which a plan prescribes. [accent]
  /// comes in as a parameter so the dialog wears the plan's own colour rather
  /// than the global accent.
  static void showEditPlanSetDialog(
    BuildContext context, {
    required int setNumber,
    required int reps,
    required double weight,
    required Color accent,
    required void Function(int reps, double weight) onSave,
  }) {
    final weightController = TextEditingController(text: formatWeight(weight));
    final repsController = TextEditingController(text: reps.toString());

    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            backgroundColor: surfaceColor(dialogContext),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: borderColor(dialogContext), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '> SET $setNumber',
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
                    ),
                    const SizedBox(height: 12),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(dialogContext),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            // An unparseable or blank field keeps what the set already
                            // had, so a stray keystroke cannot silently zero a
                            // prescription.
                            final newWeight =
                                double.tryParse(weightController.text.trim()) ??
                                weight;
                            final newReps =
                                int.tryParse(repsController.text.trim()) ??
                                reps;
                            Navigator.pop(dialogContext);
                            onSave(
                              newReps.clamp(1, 999),
                              newWeight.clamp(0, 999).toDouble(),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentFillColor(context),
                            foregroundColor: onAccentColor(context),
                          ),
                          child: Text(
                            '[SAVE]',
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
}

/// Numeric drafts use the same keypad as the inline rows; notes can still use
/// the system text keyboard. The surrounding dialog owns save/cancel behavior.
class _DialogSetEntry extends StatefulWidget {
  final TextEditingController weightController;
  final TextEditingController repsController;

  const _DialogSetEntry({
    required this.weightController,
    required this.repsController,
  });

  @override
  State<_DialogSetEntry> createState() => _DialogSetEntryState();
}

class _DialogSetEntryState extends State<_DialogSetEntry> {
  @override
  Widget build(BuildContext context) => SetEntryTable(
    exerciseName: 'SET DETAILS',
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
