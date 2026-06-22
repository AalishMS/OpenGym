import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/set.dart' as gym;
import '../../providers/settings_provider.dart';
import '../../services/pr_tracking_service.dart';
import '../../theme/app_theme.dart';

class WorkoutDialogs {
  static void showPRDialog(BuildContext context, List<PRResult> prs) {
    final accent = context.read<SettingsProvider>().accentColor;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
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
                ...prs.map((pr) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pr.exerciseName,
                              style: GoogleFonts.jetBrainsMono(
                                  fontWeight: FontWeight.bold)),
                          Text(
                            '${pr.newPR}kg (Previous: ${pr.previousPR}kg)',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: textSecondaryColor(context)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    child: Text('[ ACKNOWLEDGE ]',
                        style: GoogleFonts.jetBrainsMono()),
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
    final accent = context.read<SettingsProvider>().accentColor;
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor(context), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                style: GoogleFonts.jetBrainsMono(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Exercise name',
                  labelStyle: GoogleFonts.jetBrainsMono(fontSize: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide:
                        BorderSide(color: borderColor(context), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: accent, width: 1),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('> Enter exercise name',
                                style: GoogleFonts.jetBrainsMono()),
                            backgroundColor: errorColor(context),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      onAdd(name);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    child: Text('[ ADD ]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
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
    final accent = context.read<SettingsProvider>().accentColor;
    final nameController = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor(context), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                style: GoogleFonts.jetBrainsMono(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Exercise name',
                  labelStyle: GoogleFonts.jetBrainsMono(fontSize: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide:
                        BorderSide(color: borderColor(context), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: accent, width: 1),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('> Enter exercise name',
                                style: GoogleFonts.jetBrainsMono()),
                            backgroundColor: errorColor(context),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      onRename(name);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    child:
                        Text('[ RENAME ]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
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
    final accent = settings.accentColor;

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
                borderRadius: BorderRadius.zero,
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
                      TextField(
                        controller: weightController,
                        decoration: const InputDecoration(
                          labelText: 'Weight (kg)',
                          hintText: 'e.g., 50',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: repsController,
                        decoration: const InputDecoration(
                          labelText: 'Reps',
                          hintText: 'e.g., 8',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      Text('RPE (Rate of Perceived Exertion)',
                          style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: List.generate(10, (index) {
                          final rpe = index + 1;
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                selectedRpe = selectedRpe == rpe ? null : rpe;
                              });
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: selectedRpe == rpe
                                    ? accent
                                    : Colors.transparent,
                                border: Border.all(
                                  color: selectedRpe == rpe
                                      ? accent
                                      : borderColor(context),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$rpe',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 12,
                                    color: selectedRpe == rpe
                                        ? Colors.black
                                        : textPrimaryColor(context),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('[CANCEL]',
                                style: GoogleFonts.jetBrainsMono(
                                    color: textSecondaryColor(context))),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              final weight =
                                  double.tryParse(weightController.text);
                              final reps = int.tryParse(repsController.text);

                              if (weight == null || weight < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('> Weight must be >= 0',
                                        style: GoogleFonts.jetBrainsMono()),
                                    backgroundColor: errorColor(context),
                                  ),
                                );
                                return;
                              }

                              if (reps == null || reps <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('> Reps must be > 0',
                                        style: GoogleFonts.jetBrainsMono()),
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
                              backgroundColor: accent,
                              foregroundColor: Colors.black,
                            ),
                            child: Text('[ ADD ]',
                                style: GoogleFonts.jetBrainsMono()),
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
    final settings = context.read<SettingsProvider>();
    final accent = settings.accentColor;

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
                borderRadius: BorderRadius.zero,
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
                      TextField(
                        controller: weightController,
                        decoration:
                            const InputDecoration(labelText: 'Weight (kg)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: repsController,
                        decoration: const InputDecoration(labelText: 'Reps'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      Text('RPE',
                          style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: List.generate(10, (index) {
                          final rpe = index + 1;
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                selectedRpe = selectedRpe == rpe ? null : rpe;
                              });
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: selectedRpe == rpe
                                    ? accent
                                    : Colors.transparent,
                                border: Border.all(
                                  color: selectedRpe == rpe
                                      ? accent
                                      : borderColor(context),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$rpe',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 12,
                                    color: selectedRpe == rpe
                                        ? Colors.black
                                        : textPrimaryColor(context),
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
                        decoration:
                            const InputDecoration(labelText: 'Note (optional)'),
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
                            child: Text('[DELETE]',
                                style: GoogleFonts.jetBrainsMono(
                                    color: errorColor(context))),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('[CANCEL]',
                                    style: GoogleFonts.jetBrainsMono(
                                        color: textSecondaryColor(context))),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  final weight =
                                      double.tryParse(weightController.text);
                                  final reps =
                                      int.tryParse(repsController.text);

                                  if (weight == null ||
                                      weight < 0 ||
                                      reps == null ||
                                      reps <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('> Invalid values',
                                            style: GoogleFonts.jetBrainsMono()),
                                        backgroundColor: errorColor(context),
                                      ),
                                    );
                                    return;
                                  }

                                  final updatedSet = gym.Set(
                                    reps: reps,
                                    weight: weight,
                                    rpe: selectedRpe,
                                    note: noteController.text.isNotEmpty
                                        ? noteController.text
                                        : null,
                                  );

                                  Navigator.pop(context);
                                  onSave(updatedSet);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.black,
                                ),
                                child: Text('[ SAVE ]',
                                    style: GoogleFonts.jetBrainsMono()),
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
    final accent = context.read<SettingsProvider>().accentColor;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: surfaceColor(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: borderColor(context), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('[CANCEL]',
                          style: GoogleFonts.jetBrainsMono(
                              color: textSecondaryColor(context))),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onSave(noteController.text.isNotEmpty
                            ? noteController.text
                            : null);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                      ),
                      child:
                          Text('[ SAVE ]', style: GoogleFonts.jetBrainsMono()),
                    ),
                  ],
                ),
              ],
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
    final accent = context.read<SettingsProvider>().accentColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: accent),
              title: Text('RENAME', style: GoogleFonts.jetBrainsMono()),
              onTap: () {
                Navigator.pop(context);
                onRename();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: errorColor(context)),
              title: Text('DELETE',
                  style: GoogleFonts.jetBrainsMono(color: errorColor(context))),
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
    final accent = context.read<SettingsProvider>().accentColor;
    final controller = TextEditingController(text: currentWeek.toString());
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor(context), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context))),
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
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    child:
                        Text('[ RENAME ]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
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
      builder: (context) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor(context), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: textSecondaryColor(context)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: errorColor(context),
                      foregroundColor: Colors.white,
                    ),
                    child:
                        Text('[ DELETE ]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
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
      builder: (context) => Dialog(
        backgroundColor: surfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor(context), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: textSecondaryColor(context)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: errorColor(context),
                      foregroundColor: Colors.white,
                    ),
                    child:
                        Text('[ DELETE ]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }
}
