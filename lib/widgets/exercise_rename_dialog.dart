import 'package:flutter/material.dart';

import '../models/exercise_definition.dart';
import '../services/exercise_catalog.dart';
import '../services/exercise_rename_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import 'action_progress.dart';
import 'motion/app_modals.dart';

/// What the rename dialog did.
sealed class ExerciseRenameOutcome {
  const ExerciseRenameOutcome();
}

/// The movement now goes by [name] everywhere.
class ExerciseRenamed extends ExerciseRenameOutcome {
  final String name;
  const ExerciseRenamed(this.name);
}

/// The movement was merged into [into], whose name it now shows.
class ExerciseMerged extends ExerciseRenameOutcome {
  final ExerciseDefinition into;
  const ExerciseMerged(this.into);
}

/// The one way to rename a movement, from a workout or from Settings.
///
/// A movement has one name (see `ExerciseRenameService`), so the dialog
/// renames it everywhere: every plan, workout, log and chart shows the new
/// name, and its history stays where it was. When the typed name already
/// belongs to another movement, the two are the same movement: the dialog
/// says so and its action becomes *Merge*, which combines them under that
/// name. Returns null when cancelled.
Future<ExerciseRenameOutcome?> showExerciseRenameDialog(
  BuildContext context, {
  required String exerciseId,
  required String currentName,
  required String? userId,
}) => showAppDialog<ExerciseRenameOutcome>(
  context: context,
  barrierDismissible: false,
  builder:
      (_) => _ExerciseRenameDialog(
        exerciseId: ExerciseCatalog.canonicalId(exerciseId),
        currentName: currentName,
        userId: userId,
      ),
);

class _ExerciseRenameDialog extends StatefulWidget {
  final String exerciseId;
  final String currentName;
  final String? userId;

  const _ExerciseRenameDialog({
    required this.exerciseId,
    required this.currentName,
    required this.userId,
  });

  @override
  State<_ExerciseRenameDialog> createState() => _ExerciseRenameDialogState();
}

class _ExerciseRenameDialogState extends State<_ExerciseRenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.currentName,
  );
  late final ExerciseUsage _usage = ExerciseRenameService.usage(
    widget.exerciseId,
    userId: widget.userId,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _typed => ExerciseRenameService.canonicalName(_name.text);

  ExerciseDefinition? get _owner =>
      _typed.isEmpty
          ? null
          : ExerciseRenameService.nameOwner(widget.exerciseId, _typed);

  Future<void> _submit() async {
    if (_saving) return;
    final name = _typed;
    if (ExerciseRenameService.validationMessage(name) case final message?) {
      setState(() => _error = message);
      return;
    }
    if (name == widget.currentName) {
      Navigator.pop(context);
      return;
    }
    final owner = _owner;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ExerciseRenameOutcome outcome;
      if (owner != null) {
        await ExerciseRenameService.merge(
          sourceId: widget.exerciseId,
          targetId: owner.id,
          userId: widget.userId,
        );
        outcome = ExerciseMerged(owner);
      } else {
        await ExerciseRenameService.rename(
          exerciseId: widget.exerciseId,
          currentName: widget.currentName,
          to: name,
          userId: widget.userId,
        );
        outcome = ExerciseRenamed(name);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      // Let PopScope publish its updated canPop before dismissing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, outcome);
      });
    } catch (error) {
      debugPrint('Could not rename exercise: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            error is FormatException
                ? error.message
                : owner != null
                ? 'Could not merge exercises. Try again.'
                : 'Could not rename exercise. Try again.';
      });
    }
  }

  String _count(int value, String noun) =>
      '$value ${value == 1 ? noun : '${noun}s'}';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final owner = _owner;
    final usage =
        _usage.isEmpty
            ? 'Not used in any plan or workout yet.'
            : 'Used in ${_count(_usage.plans, 'plan')} and '
                '${_count(_usage.workouts, 'workout')}.';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Rename exercise'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
              // The keyboard's own action renames. A merge can't be undone,
              // so it takes the Merge button.
              onSubmitted: (_) {
                if (_owner == null) _submit();
              },
              decoration: InputDecoration(
                labelText: 'Exercise name',
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The new name shows in every plan, workout and chart. '
              'Its history stays the same. $usage',
              key: const ValueKey('rename-scope'),
              style: textTheme.bodySmall?.copyWith(color: secondary),
            ),
            if (owner != null) ...[
              const SizedBox(height: AppSpacing.md),
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('rename-merge-note'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: controlFillColor(context),
                    borderRadius: AppRadius.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // The match may be an alias or a former name, so
                        // say which exercise the typed name belongs to.
                        ExerciseCatalog.normalize(owner.name) ==
                                ExerciseCatalog.normalize(_typed)
                            ? '${owner.name} is already an exercise'
                            : '$_typed is another name for ${owner.name}',
                        style: textTheme.titleSmall?.copyWith(
                          color: textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Merge to make them one exercise called '
                        '${owner.name}, with their history, records and '
                        'previous sets together. All logged sets are kept. '
                        "This can't be undone.",
                        style: textTheme.bodySmall?.copyWith(
                          color: textPrimaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child:
                _saving
                    ? ActionProgress(owner != null ? 'Merging' : 'Saving')
                    : Text(owner != null ? 'Merge' : 'Rename'),
          ),
        ],
      ),
    );
  }
}
