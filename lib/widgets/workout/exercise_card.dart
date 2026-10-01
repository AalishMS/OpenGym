import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/exercise.dart';
import '../../models/set.dart' as gym;
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'set_entry_table.dart';

enum _ExerciseAction { note, rename, moveUp, moveDown, deleteExercise }

/// An expanded exercise section in the continuous workout log.
class ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final int exerciseIndex;
  final bool reorderable;
  final bool readOnly;
  final Color accent;
  final List<gym.Set> previousSets;
  final VoidCallback? onEntryFinished;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final void Function(int exercise, int index, double weight, int reps)?
  onSetChanged;
  final void Function(int exercise, int index, int? rpe) onSetRpeChanged;
  final void Function(int) onAddSet;
  final void Function(int, int) onDeleteSet;
  final void Function(int) onAddNote;
  final void Function(int) onRename;
  final void Function(int) onDeleteExercise;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.exerciseIndex,
    this.reorderable = false,
    this.readOnly = false,
    required this.accent,
    this.previousSets = const [],
    this.onEntryFinished,
    this.onMoveUp,
    this.onMoveDown,
    this.onSetChanged,
    required this.onSetRpeChanged,
    required this.onAddSet,
    required this.onDeleteSet,
    required this.onAddNote,
    required this.onRename,
    required this.onDeleteExercise,
  });

  void _onAction(_ExerciseAction action) {
    switch (action) {
      case _ExerciseAction.note:
        onAddNote(exerciseIndex);
      case _ExerciseAction.rename:
        onRename(exerciseIndex);
      case _ExerciseAction.moveUp:
        onMoveUp?.call();
      case _ExerciseAction.moveDown:
        onMoveDown?.call();
      case _ExerciseAction.deleteExercise:
        onDeleteExercise(exerciseIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          exercise.name,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (readOnly)
            title
          else
            SetEntryHeading(
              title:
                  reorderable && !readOnly
                      ? ReorderableDelayedDragStartListener(
                        index: exerciseIndex,
                        child: Tooltip(
                          message: 'Hold to reorder ${exercise.name}',
                          // Reordering owns the long press, not the tooltip.
                          triggerMode: TooltipTriggerMode.manual,
                          child: title,
                        ),
                      )
                      : title,
              action: PopupMenuButton<_ExerciseAction>(
                tooltip: 'Exercise actions for ${exercise.name}',
                icon: Icon(
                  LucideIcons.ellipsis,
                  size: 20,
                  color: textSecondaryColor(context),
                ),
                constraints: const BoxConstraints(minWidth: 180),
                onSelected: _onAction,
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: _ExerciseAction.note,
                        height: 48,
                        child: Text('Exercise note'),
                      ),
                      const PopupMenuItem(
                        value: _ExerciseAction.rename,
                        height: 48,
                        child: Text('Rename exercise'),
                      ),
                      if (onMoveUp != null)
                        const PopupMenuItem(
                          value: _ExerciseAction.moveUp,
                          height: 48,
                          child: Text('Move up'),
                        ),
                      if (onMoveDown != null)
                        const PopupMenuItem(
                          value: _ExerciseAction.moveDown,
                          height: 48,
                          child: Text('Move down'),
                        ),
                      PopupMenuItem(
                        value: _ExerciseAction.deleteExercise,
                        height: 48,
                        child: Text(
                          'Delete exercise',
                          style: TextStyle(color: errorColor(context)),
                        ),
                      ),
                    ],
              ),
            ),
          if (exercise.note?.trim().isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                exercise.note!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (exercise.sets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No sets added yet',
                style: TextStyle(color: textSecondaryColor(context)),
              ),
            )
          else
            SetEntryTable(
              continuousLog: true,
              onEntryFinished: onEntryFinished,
              onDelete:
                  readOnly
                      ? null
                      : (index) => onDeleteSet(exerciseIndex, index),
              sets: [
                for (var i = 0; i < exercise.sets.length; i++)
                  SetEntry(
                    weight: exercise.sets[i].weight,
                    reps: exercise.sets[i].reps,
                    previous:
                        i < previousSets.length && previousSets[i].reps > 0
                            ? '${entryWeight(previousSets[i].weight)} × ${previousSets[i].reps}'
                            : null,
                    rpe: exercise.sets[i].rpe,
                  ),
              ],
              onChanged:
                  (index, weight, reps) =>
                      onSetChanged?.call(exerciseIndex, index, weight, reps),
              onRpeChanged:
                  (index, rpe) => onSetRpeChanged(exerciseIndex, index, rpe),
            ),
          if (!readOnly)
            TextButton.icon(
              onPressed: () => onAddSet(exerciseIndex),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Add set'),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                minimumSize: const Size(96, 48),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.button,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
