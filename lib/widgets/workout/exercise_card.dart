import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/exercise.dart';
import '../../theme/app_theme.dart';
import 'set_row.dart';

class ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final int exerciseIndex;
  final Color accent;
  final void Function(int exerciseIndex, int setIndex) onIncrementReps;
  final void Function(int exerciseIndex, int setIndex) onDecrementReps;
  final void Function(int exerciseIndex, int setIndex) onIncrementWeight;
  final void Function(int exerciseIndex, int setIndex) onDecrementWeight;
  final void Function(int exerciseIndex) onAddSet;
  final void Function(int exerciseIndex, int setIndex) onEditSet;
  final void Function(int exerciseIndex) onAddNote;
  final void Function(int exerciseIndex) onRename;
  final void Function(int exerciseIndex) onDeleteExercise;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.exerciseIndex,
    required this.accent,
    required this.onIncrementReps,
    required this.onDecrementReps,
    required this.onIncrementWeight,
    required this.onDecrementWeight,
    required this.onAddSet,
    required this.onEditSet,
    required this.onAddNote,
    required this.onRename,
    required this.onDeleteExercise,
  });

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
                  border: Border.all(color: accent, width: 1),
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
                child: InkWell(
                  onTap: () => onRename(exerciseIndex),
                  child: Text(
                    exercise.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (exercise.note != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.note, size: 16, color: accent),
                ),
              InkWell(
                onTap: () => onAddNote(exerciseIndex),
                child: Icon(Icons.note_add,
                    size: 20, color: textSecondaryColor(context)),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => onDeleteExercise(exerciseIndex),
                child: Icon(Icons.delete_outline, size: 20, color: accent),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => onAddSet(exerciseIndex),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: accent, width: 1),
                  ),
                  child: Text('[+]',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 12, color: accent)),
                ),
              ),
            ],
          ),
          if (exercise.sets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '> No sets added yet',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: textSecondaryColor(context)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...exercise.sets.asMap().entries.map((entry) {
                    final setIndex = entry.key;
                    final set = entry.value;
                    return SetRow(
                      setIndex: setIndex,
                      set: set,
                      exerciseIndex: exerciseIndex,
                      accent: accent,
                      onDecrementReps: () =>
                          onDecrementReps(exerciseIndex, setIndex),
                      onIncrementReps: () =>
                          onIncrementReps(exerciseIndex, setIndex),
                      onDecrementWeight: () =>
                          onDecrementWeight(exerciseIndex, setIndex),
                      onIncrementWeight: () =>
                          onIncrementWeight(exerciseIndex, setIndex),
                      onEdit: () => onEditSet(exerciseIndex, setIndex),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
