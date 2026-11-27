import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../services/exercise_catalog.dart';
import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../models/workout_session.dart';
import '../navigation/app_navigation_observer.dart';
import '../navigation/open_workout.dart';
import '../providers/settings_provider.dart';
import '../providers/workout_session_provider.dart';
import '../theme/app_theme.dart';
import '../theme/spacing.dart';
import '../utils/scroll_to_top.dart';
import '../utils/set_history.dart';
import '../utils/statistics_format.dart';
import '../utils/weight_units.dart';
import '../widgets/action_progress.dart';
import '../widgets/app_button.dart';
import '../widgets/app_header.dart';
import '../widgets/history/history_journal_data.dart';
import '../widgets/history/history_journal_widgets.dart';
import '../widgets/motion/app_modals.dart';
import '../widgets/motion/collapsible.dart';
import '../widgets/motion/state_switcher.dart';
import '../widgets/own_scroll_controller.dart';
import '../widgets/workout/set_entry_table.dart';
import '../widgets/workout/workout_dialogs.dart';
import '../widgets/raised_card.dart';

class HistoryScreen extends StatefulWidget {
  /// Bumped when the History tab is tapped while showing.
  final int scrollToTopRequest;

  const HistoryScreen({this.scrollToTopRequest = 0, super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// The journal list on show. The list owns its controller
  /// ([OwnScrollController]): results that come back while the last list is
  /// still crossing out arrive as a second list, and one controller can't
  /// hold both.
  ScrollController? _listScroll;
  String _query = '';
  String? _splitId;
  bool _hasSeenSplit = false;

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollToTopRequest != oldWidget.scrollToTopRequest) {
      scrollToTop(context, _listScroll);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final splitId = context.watch<WorkoutSessionProvider>().activeSplitId;
    if (_hasSeenSplit && splitId != _splitId) {
      _query = '';
      _searchController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final scroll = _listScroll;
        if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
      });
    }
    _splitId = splitId;
    _hasSeenSplit = true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkoutSessionProvider>();
    final weightUnit = context.watch<SettingsProvider>().weightUnit;
    final journal = buildHistoryJournalData(
      provider.sessions,
      query: _query,
      splitId: provider.activeSplitId,
    );
    final entries = <Object>[
      for (final group in journal.groups) ...[
        group,
        for (final (index, workout) in group.workouts.indexed)
          _JournalEntry(
            summary: workout,
            showDate:
                index == 0 ||
                !DateUtils.isSameDay(
                  group.workouts[index - 1].session.date,
                  workout.session.date,
                ),
            rule:
                index == group.workouts.length - 1
                    ? HistoryRowRule.none
                    : DateUtils.isSameDay(
                      group.workouts[index + 1].session.date,
                      workout.session.date,
                    )
                    ? HistoryRowRule.inset
                    : HistoryRowRule.full,
          ),
      ],
    ];
    final visibleCount = journal.groups.fold<int>(
      0,
      (count, group) => count + group.workouts.length,
    );
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: const AppHeader(
        automaticallyImplyLeading: false,
        title: Text('History'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: HistorySearchField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  onClear: _clearSearch,
                ),
              ),
              // The count opens under the field when a search starts and
              // folds away when it ends, so the ledger moves rather than
              // jumps. Typing more only changes the number, in place.
              Collapsible(
                open: searching && !journal.isEmpty,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$visibleCount matching workout${visibleCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
              Expanded(
                // Results and "No matching workouts" cross in place; typing
                // more within either one replays nothing.
                child: StateSwitcher(
                  child:
                      journal.isEmpty
                          ? HistoryEmptyState(
                            key: ValueKey('history-empty-$searching'),
                            isSearching: searching,
                            onClearSearch: _clearSearch,
                          )
                          : OwnScrollController(
                            key: const ValueKey('history-journal'),
                            onAttach: (scroll) => _listScroll = scroll,
                            onDetach: (scroll) {
                              if (identical(_listScroll, scroll)) {
                                _listScroll = null;
                              }
                            },
                            builder:
                                (context, scroll) => ListView.builder(
                                  key: const PageStorageKey(
                                    'history-journal-list',
                                  ),
                                  controller: scroll,
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.lg,
                                    AppSpacing.md,
                                    AppSpacing.lg,
                                    AppSpacing.xxl,
                                  ),
                                  itemCount: entries.length,
                                  itemBuilder: (context, index) {
                                    final entry = entries[index];
                                    if (entry is HistoryMonthGroup) {
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          top: index == 0 ? 0 : AppSpacing.xxl,
                                        ),
                                        child: HistoryMonthHeader(
                                          group: entry,
                                          weightUnit: weightUnit,
                                        ),
                                      );
                                    }
                                    final row = entry as _JournalEntry;
                                    final session = row.summary.session;
                                    return HistoryWorkoutRow(
                                      key: ValueKey(
                                        'history-row-${historySessionIdentity(session)}',
                                      ),
                                      summary: row.summary,
                                      weightUnit: weightUnit,
                                      showDate: row.showDate,
                                      rule: row.rule,
                                      onTap:
                                          () => openLoggedWorkout(
                                            context,
                                            session,
                                          ),
                                    );
                                  },
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
}

/// A journal row, whether it opens a new day, and the rule beneath it.
class _JournalEntry {
  final HistoryWorkoutSummary summary;
  final bool showDate;
  final HistoryRowRule rule;

  const _JournalEntry({
    required this.summary,
    required this.showDate,
    required this.rule,
  });
}

enum _EditLeaveAction { save, discard }

class EditSessionScreen extends StatefulWidget {
  final WorkoutSession session;

  const EditSessionScreen({super.key, required this.session});

  @override
  State<EditSessionScreen> createState() => _EditSessionScreenState();
}

class _EditSessionScreenState extends State<EditSessionScreen>
    with AppRouteParticipant<EditSessionScreen> {
  @override
  Future<void> leaveRoute() => _handleBack();

  late WorkoutSession _session;
  late TextEditingController _planNameController;
  late final String _initialSignature;
  bool _isSaving = false;
  bool _isConfirmingLeave = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session.copyWith();
    _planNameController = TextEditingController(text: _session.planName);
    _initialSignature = _draftSignature;
    _planNameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _planNameController.removeListener(_onNameChanged);
    _planNameController.dispose();
    super.dispose();
  }

  String get _draftSignature => jsonEncode({
    'name': _planNameController.text.trim(),
    'exercises':
        _session.exercises.map((exercise) => exercise.toJson()).toList(),
  });

  bool get _isDirty => _draftSignature != _initialSignature;

  void _onNameChanged() => setState(() {});

  Future<void> _handleBack() async {
    if (_isSaving || _isConfirmingLeave) return;
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isConfirmingLeave = true);
    final action = await showAppDialog<_EditLeaveAction>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Save changes?'),
            content: const Text('This workout has unsaved edits.'),
            actions: [
              AppButton.text(
                label: 'Cancel',
                onPressed: () => Navigator.pop(dialogContext),
              ),
              AppButton.destructive(
                label: 'Discard',
                onPressed:
                    () =>
                        Navigator.pop(dialogContext, _EditLeaveAction.discard),
              ),
              AppButton.primary(
                label: 'Save',
                onPressed:
                    () => Navigator.pop(dialogContext, _EditLeaveAction.save),
              ),
            ],
          ),
    );
    if (!mounted) return;
    setState(() => _isConfirmingLeave = false);
    if (action == _EditLeaveAction.save) {
      await _save();
    } else if (action == _EditLeaveAction.discard) {
      Navigator.pop(context);
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    return await showAppDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: Text(title),
                content: Text(
                  '$message Changes apply when you save the workout.',
                ),
                actions: [
                  AppButton.text(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(dialogContext, false),
                  ),
                  AppButton.destructive(
                    label: 'Delete',
                    onPressed: () => Navigator.pop(dialogContext, true),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _removeExercise(int index) async {
    final exercise = _session.exercises[index];
    final confirmed = await _confirmDelete(
      title: 'Delete exercise?',
      message:
          'Delete “${ExerciseCatalog.label(exercise.name, exercise.exerciseId)}” '
          'and all its sets from this workout?',
    );
    if (!mounted || !confirmed || _isSaving) return;
    final exercises = List<Exercise>.from(_session.exercises)..removeAt(index);
    setState(() => _session = _session.copyWith(exercises: exercises));
  }

  Future<void> _removeSet(int exerciseIndex, int setIndex) async {
    final exercise = _session.exercises[exerciseIndex];
    final confirmed = await _confirmDelete(
      title: 'Delete set?',
      message:
          'Delete set ${setIndex + 1} from '
          '“${ExerciseCatalog.label(exercise.name, exercise.exerciseId)}”?',
    );
    if (!mounted || !confirmed || _isSaving) return;
    final sets = List<gym.Set>.of(exercise.sets)..removeAt(setIndex);
    _replaceSets(exerciseIndex, sets);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final name = _planNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a workout name.')));
      return;
    }
    setState(() => _isSaving = true);
    _session = _session.copyWith(planName: name);
    try {
      await context.read<WorkoutSessionProvider>().upsertSession(_session);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Workout updated')));
      Navigator.pop(context, true);
    } catch (exception) {
      debugPrint('Failed to update workout: $exception');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the workout. Your edits are still here. Try again.',
          ),
        ),
      );
    }
  }

  /// Deletes the workout as saved, edits and all, and leaves without asking
  /// about them.
  Future<void> _delete() async {
    final id = widget.session.id;
    if (_isSaving || _isConfirmingLeave || id == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    SetEntryTable.closeKeypad();
    final provider = context.read<WorkoutSessionProvider>();
    final deleted = await WorkoutDialogs.showDeleteLoggedWorkoutDialog(
      context,
      planName: widget.session.planName,
      date: widget.session.date,
      delete: () => provider.deleteSession(id),
    );
    if (!deleted || !mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty && !_isSaving && !_isConfirmingLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: backgroundColor(context),
        appBar: AppHeader(
          title: const Text('Edit workout'),
          leading: AppBackButton(enabled: !_isSaving, onPressed: _handleBack),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _save,
              child:
                  _isSaving
                      ? const ActionProgress('Saving workout')
                      : const Text('Save'),
            ),
            if (widget.session.id != null && widget.session.isCompleted)
              PopupMenuButton<String>(
                tooltip: 'Workout actions',
                enabled: !_isSaving,
                icon: Icon(
                  LucideIcons.ellipsisVertical,
                  color: textSecondaryColor(context),
                ),
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder:
                    (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        height: 48,
                        child: Text(
                          'Delete workout',
                          style: TextStyle(color: errorColor(context)),
                        ),
                      ),
                    ],
              )
            else
              const SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                TextField(
                  key: const ValueKey('workout-name-field'),
                  controller: _planNameController,
                  enabled: !_isSaving,
                  decoration: const InputDecoration(labelText: 'Workout name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Weights are in ${weightUnitSpoken(SettingsProvider.unitOf(context))}. '
                  'Tap a value to edit, or a set number for notes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Exercises',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_session.exercises.isEmpty)
                  Text(
                    'No exercises in this workout',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                for (final entry in _session.exercises.indexed)
                  _EditableExerciseCard(
                    key: ValueKey('edit-exercise-${entry.$1}-${entry.$2.name}'),
                    exercise: entry.$2,
                    entries: _entriesFor(entry.$2),
                    enabled: !_isSaving,
                    onRemove: () => _removeExercise(entry.$1),
                    onDeleteSet: (setIndex) => _removeSet(entry.$1, setIndex),
                    onChanged: (setIndex, weight, reps) {
                      final sets = List<gym.Set>.of(
                        _session.exercises[entry.$1].sets,
                      );
                      final old = sets[setIndex];
                      sets[setIndex] = gym.Set(
                        weight: weight,
                        reps: reps,
                        rpe: old.rpe,
                        note: old.note,
                      );
                      _replaceSets(entry.$1, sets);
                    },
                    onRpeChanged: (setIndex, rpe) {
                      final sets = List<gym.Set>.of(
                        _session.exercises[entry.$1].sets,
                      );
                      final old = sets[setIndex];
                      sets[setIndex] = gym.Set(
                        weight: old.weight,
                        reps: old.reps,
                        rpe: rpe,
                        note: old.note,
                      );
                      _replaceSets(entry.$1, sets);
                    },
                    onDetails:
                        (setIndex) => _showEditSetDialog(
                          entry.$1,
                          setIndex,
                          entry.$2.sets[setIndex],
                        ),
                    onAddSet: () => _showAddSetDialog(entry.$1),
                  ),
                // Room for the keypad below the last card.
                ValueListenableBuilder<double>(
                  valueListenable: SetEntryTable.keyboardHeight,
                  builder: (_, height, _) => SizedBox(height: height),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<SetEntry> _entriesFor(Exercise exercise) {
    final weightUnit = SettingsProvider.unitOf(context);
    final previous = previousExerciseSets(
      context.read<WorkoutSessionProvider>().sessions.where(
        (session) => session.date.isBefore(_session.date),
      ),
      ExerciseCatalog.identity(exercise.name, exercise.exerciseId),
      splitId: _session.splitId,
      planId: _session.planId,
      planName: _session.planName,
    );
    return [
      for (var index = 0; index < exercise.sets.length; index++)
        SetEntry(
          weight: exercise.sets[index].weight,
          reps: exercise.sets[index].reps,
          previous:
              index < previous.length && previous[index].reps > 0
                  ? ExerciseCatalog.isTimed(exercise.name, exercise.exerciseId)
                      ? formatSetSummary(
                        previous[index].weight,
                        previous[index].reps,
                        weightUnit,
                        timed: true,
                      )
                      : '${formatEntryWeight(previous[index].weight, weightUnit)} × ${previous[index].reps}'
                  : null,
          annotation: exercise.sets[index].note,
          rpe: exercise.sets[index].rpe,
        ),
    ];
  }

  void _replaceSets(int exerciseIndex, List<gym.Set> sets) {
    final exercises = List<Exercise>.of(_session.exercises);
    final old = exercises[exerciseIndex];
    exercises[exerciseIndex] = Exercise(
      name: old.name,
      exerciseId: old.exerciseId,
      sets: sets,
      note: old.note,
    );
    setState(() => _session = _session.copyWith(exercises: exercises));
  }

  void _showAddSetDialog(int exerciseIndex) {
    WorkoutDialogs.showAddSetDialog(
      context,
      exerciseName: _session.exercises[exerciseIndex].name,
      exerciseId: _session.exercises[exerciseIndex].exerciseId,
      onAdd: (set) {
        _replaceSets(exerciseIndex, [
          ..._session.exercises[exerciseIndex].sets,
          set,
        ]);
      },
    );
  }

  void _showEditSetDialog(int exerciseIndex, int setIndex, gym.Set set) {
    WorkoutDialogs.showEditSetDialog(
      context,
      exerciseName: _session.exercises[exerciseIndex].name,
      exerciseId: _session.exercises[exerciseIndex].exerciseId,
      set: set,
      onSave: (updated) {
        final sets = List<gym.Set>.of(_session.exercises[exerciseIndex].sets);
        sets[setIndex] = updated;
        _replaceSets(exerciseIndex, sets);
      },
      onDelete: () => _removeSet(exerciseIndex, setIndex),
    );
  }
}

class _EditableExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final List<SetEntry> entries;
  final bool enabled;
  final VoidCallback onRemove;
  final ValueChanged<int> onDeleteSet;
  final void Function(int index, double weight, int reps) onChanged;
  final void Function(int index, int? rpe) onRpeChanged;
  final ValueChanged<int> onDetails;
  final VoidCallback onAddSet;

  const _EditableExerciseCard({
    required this.exercise,
    required this.entries,
    required this.enabled,
    required this.onRemove,
    required this.onDeleteSet,
    required this.onChanged,
    required this.onRpeChanged,
    required this.onDetails,
    required this.onAddSet,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final name = ExerciseCatalog.label(exercise.name, exercise.exerciseId);
    final note = exercise.note?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: raisedDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              AppIconButton(
                label: 'Delete $name',
                icon: LucideIcons.trash2,
                color: errorColor(context),
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.md),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No sets recorded',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (entries.isNotEmpty)
            IgnorePointer(
              ignoring: !enabled,
              child: SetEntryTable(
                isTimed: ExerciseCatalog.isTimed(
                  exercise.name,
                  exercise.exerciseId,
                ),
                hostReservesSpace: true,
                sets: entries,
                onChanged: onChanged,
                onRpeChanged: onRpeChanged,
                onDetails: onDetails,
                onDelete: onDeleteSet,
              ),
            ),
          AppButton.text(
            label: 'Add set',
            icon: const Icon(LucideIcons.plus, size: 18),
            onPressed: enabled ? onAddSet : null,
          ),
        ],
      ),
    );
  }
}
