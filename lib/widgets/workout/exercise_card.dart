import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/exercise.dart';
import '../../models/exercise_template.dart';
import '../../models/set.dart' as gym;
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import 'set_entry_table.dart';

class ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final int exerciseIndex;
  final Color accent;
  final ExerciseTemplate? template;
  final List<gym.Set> previousSets;
  final VoidCallback? onEntryFinished;
  final void Function(int exercise, int index, double weight, int reps)?
  onSetChanged;
  final Set<gym.Set> touchedSets;
  final void Function(int) onAddSet;
  final void Function(int, int) onEditSet;
  final void Function(int) onAddNote;
  final void Function(int) onRename;
  final void Function(int) onDeleteExercise;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.exerciseIndex,
    required this.accent,
    this.template,
    this.previousSets = const [],
    this.onEntryFinished,
    this.onSetChanged,
    this.touchedSets = const {},
    required this.onAddSet,
    required this.onEditSet,
    required this.onAddNote,
    required this.onRename,
    required this.onDeleteExercise,
  });

  String? _annotation(int index) {
    final set = exercise.sets[index];
    final target = template?.targetAt(index);
    final parts = [
      if (set.note?.isNotEmpty ?? false) set.note!,
      if (!touchedSets.contains(set) &&
          target != null &&
          (target.weight > 0 || target.reps > 0))
        'TARGET ${entryWeight(target.weight)} KG · ${target.reps} REPS',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget action(
    BuildContext context,
    String label,
    VoidCallback callback,
    Widget child,
  ) => Semantics(
    button: true,
    container: true,
    label: label,
    onTap: callback,
    child: InkWell(
      onTap: callback,
      borderRadius: AppRadius.badge,
      child: SizedBox(width: 48, height: 48, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: accent),
                  borderRadius: AppRadius.badge,
                ),
                child: Text(
                  '${exerciseIndex + 1}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: action(
                  context,
                  exercise.name,
                  () => onRename(exerciseIndex),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      exercise.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              action(
                context,
                'Exercise note',
                () => onAddNote(exerciseIndex),
                Icon(
                  exercise.note != null
                      ? LucideIcons.stickyNote
                      : LucideIcons.notebookPen,
                  size: 20,
                  color:
                      exercise.note != null
                          ? accent
                          : textSecondaryColor(context),
                ),
              ),
              action(
                context,
                'Delete exercise',
                () => onDeleteExercise(exerciseIndex),
                Icon(
                  LucideIcons.trash2,
                  size: 20,
                  color: textSecondaryColor(context),
                ),
              ),
              action(
                context,
                'Add set',
                () => onAddSet(exerciseIndex),
                Center(
                  child: Text(
                    '[+]',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (exercise.sets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '> No sets added yet',
                style: TextStyle(color: textSecondaryColor(context)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SetEntryTable(
                exerciseName: exercise.name,
                onEntryFinished: onEntryFinished,
                sets: [
                  for (var i = 0; i < exercise.sets.length; i++)
                    SetEntry(
                      weight: exercise.sets[i].weight,
                      reps: exercise.sets[i].reps,
                      previous:
                          i < previousSets.length && previousSets[i].reps > 0
                              ? '${entryWeight(previousSets[i].weight)} × ${previousSets[i].reps}'
                              : null,
                      annotation: _annotation(i),
                      rpe: exercise.sets[i].rpe,
                    ),
                ],
                onChanged:
                    (index, weight, reps) =>
                        onSetChanged?.call(exerciseIndex, index, weight, reps),
                onDetails: (index) => onEditSet(exerciseIndex, index),
              ),
            ),
        ],
      ),
    );
  }
}
