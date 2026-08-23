import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/exercise.dart';
import '../../models/exercise_template.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import 'set_row.dart';

class ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final int exerciseIndex;
  final Color accent;

  /// The plan entry this exercise came from, when one still matches it.
  ///
  /// Only used to hint at prescribed reps/weight on untouched sets; the session
  /// itself never inherits those numbers.
  final ExerciseTemplate? template;

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
    this.template,
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
                child: InkWell(
                  onTap: () => onRename(exerciseIndex),
                  child: Text(
                    exercise.name.toUpperCase(),
                    // The card's title, not its headline. At 14/bold it
                    // out-shouted the set values below it, which are the numbers
                    // you came to the screen to read and change.
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.04,
                    ),
                  ),
                ),
              ),
              // One glyph carries the note's state: a filled-in note when the
              // exercise has one, a pen when it does not. Two icons for one
              // piece of information crowded a 24px band.
              InkWell(
                onTap: () => onAddNote(exerciseIndex),
                child: Icon(
                  exercise.note != null
                      ? LucideIcons.stickyNote
                      : LucideIcons.notebookPen,
                  size: 20,
                  color: exercise.note != null
                      ? accent
                      : textSecondaryColor(context),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => onDeleteExercise(exerciseIndex),
                child: Icon(LucideIcons.trash2,
                    size: 20, color: textSecondaryColor(context)),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => onAddSet(exerciseIndex),
                borderRadius: AppRadius.badge,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: accent, width: 1),
                    borderRadius: AppRadius.badge,
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
                  const SetHeaderRow(),
                  ...exercise.sets.asMap().entries.map((entry) {
                    final setIndex = entry.key;
                    final set = entry.value;
                    return SetRow(
                      setIndex: setIndex,
                      set: set,
                      exerciseIndex: exerciseIndex,
                      accent: accent,
                      target: template?.targetAt(setIndex),
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
