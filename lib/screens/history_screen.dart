import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/exercise.dart';
import '../models/set.dart' as gym;
import '../models/workout_session.dart';
import '../providers/settings_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/statistics_analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/set_history.dart';
import '../utils/statistics_format.dart';
import '../widgets/app_button.dart';
import '../widgets/history/history_journal_data.dart';
import '../widgets/history/history_journal_widgets.dart';
import '../widgets/history/workout_details_widgets.dart';
import '../widgets/workout/set_entry_table.dart';
import '../widgets/workout/workout_dialogs.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';
  String? _splitId;
  bool _hasSeenSplit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final splitId = context.watch<WorkoutSessionProvider>().activeSplitId;
    if (_hasSeenSplit && splitId != _splitId) {
      _query = '';
      _searchController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
    _splitId = splitId;
    _hasSeenSplit = true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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
      for (final group in journal.groups) ...[group, ...group.workouts],
    ];

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        automaticallyImplyLeading: false,
        title: Text(
          'History',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textPrimaryColor(context)),
        ),
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
              Expanded(
                child:
                    journal.isEmpty
                        ? HistoryEmptyState(
                          isSearching: _query.trim().isNotEmpty,
                          onClearSearch: _clearSearch,
                        )
                        : ListView.builder(
                          key: const PageStorageKey('history-journal-list'),
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.xxl,
                          ),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry is HistoryMonthGroup) {
                              return Padding(
                                padding: EdgeInsets.only(
                                  top: index == 0 ? 0 : AppSpacing.xl,
                                  bottom: AppSpacing.md,
                                ),
                                child: HistoryMonthHeader(group: entry),
                              );
                            }
                            final summary = entry as HistoryWorkoutSummary;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: HistoryWorkoutRow(
                                key: ValueKey(
                                  'history-row-${historySessionIdentity(summary.session)}',
                                ),
                                summary: summary,
                                weightUnit: weightUnit,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder:
                                          (_) => WorkoutDetailsScreen(
                                            sessionIdentity:
                                                historySessionIdentity(
                                                  summary.session,
                                                ),
                                          ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutDetailsScreen extends StatelessWidget {
  final String sessionIdentity;

  const WorkoutDetailsScreen({required this.sessionIdentity, super.key});

  WorkoutSession? _session(WorkoutSessionProvider provider) {
    for (final session in provider.sessions) {
      if (historySessionIdentity(session) == sessionIdentity) return session;
    }
    return null;
  }

  Future<void> _edit(BuildContext context, WorkoutSession session) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditSessionScreen(session: session),
      ),
    );
    if (!context.mounted || updated != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Workout updated')));
  }

  Future<void> _delete(BuildContext context, WorkoutSession session) async {
    var deleting = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Delete workout?'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delete “${session.planName}” from '
                        '${formatStatisticsDate(session.date)}?',
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
                          deleting ? null : () => Navigator.pop(dialogContext),
                    ),
                    AppButton.destructive(
                      label: 'Delete',
                      onPressed:
                          deleting
                              ? null
                              : () async {
                                final id = session.id;
                                if (id == null) {
                                  setDialogState(
                                    () =>
                                        error =
                                            'This workout cannot be deleted because its identity is missing.',
                                  );
                                  return;
                                }
                                setDialogState(() {
                                  deleting = true;
                                  error = null;
                                });
                                try {
                                  await dialogContext
                                      .read<WorkoutSessionProvider>()
                                      .deleteSession(id);
                                  if (!dialogContext.mounted) return;
                                  Navigator.pop(dialogContext);
                                  if (context.mounted) Navigator.pop(context);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkoutSessionProvider>();
    final session = _session(provider);
    final weightUnit = context.watch<SettingsProvider>().weightUnit;
    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: const Text('Workout details'),
        actions: [
          if (session != null)
            PopupMenuButton<String>(
              tooltip: 'Workout actions',
              onSelected: (value) {
                if (value == 'edit') _edit(context, session);
                if (value == 'delete') _delete(context, session);
              },
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      height: 48,
                      child: Text('Edit'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      height: 48,
                      child: Text(
                        'Delete',
                        style: TextStyle(color: errorColor(context)),
                      ),
                    ),
                  ],
            ),
        ],
      ),
      body:
          session == null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Workout no longer available',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton.text(
                        label: 'Back',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              )
              : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      WorkoutDetailsSummary(
                        statistics: const StatisticsAnalyticsService()
                            .sessionStatistics(session),
                        weightUnit: weightUnit,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      for (final exercise in session.exercises) ...[
                        WorkoutExerciseDetails(
                          exercise: exercise,
                          weightUnit: weightUnit,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }
}

class EditSessionScreen extends StatefulWidget {
  final WorkoutSession session;

  const EditSessionScreen({super.key, required this.session});

  @override
  State<EditSessionScreen> createState() => _EditSessionScreenState();
}

class _EditSessionScreenState extends State<EditSessionScreen> {
  late WorkoutSession _session;
  late TextEditingController _planNameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session.copyWith();
    _planNameController = TextEditingController(text: _session.planName);
  }

  @override
  void dispose() {
    _planNameController.dispose();
    super.dispose();
  }

  void _removeExercise(int index) {
    final exercises = List<Exercise>.from(_session.exercises)..removeAt(index);
    setState(() => _session = _session.copyWith(exercises: exercises));
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
      await context.read<WorkoutSessionProvider>().updateSession(_session);
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: const Text('Edit workout'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child:
                _isSaving
                    ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Save'),
          ),
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
                decoration: const InputDecoration(
                  labelText: 'Workout name',
                  border: OutlineInputBorder(borderRadius: AppRadius.field),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Weights are edited in kilograms.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Exercises', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              for (final entry in _session.exercises.indexed)
                _EditableExerciseCard(
                  key: ValueKey('edit-exercise-${entry.$1}-${entry.$2.name}'),
                  exercise: entry.$2,
                  entries: _entriesFor(entry.$2),
                  enabled: !_isSaving,
                  onRemove: () => _removeExercise(entry.$1),
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
            ],
          ),
        ),
      ),
    );
  }

  List<SetEntry> _entriesFor(Exercise exercise) {
    final previous = previousExerciseSets(
      context.read<WorkoutSessionProvider>().sessions.where(
        (session) => session.date.isBefore(_session.date),
      ),
      exercise.name,
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
                  ? '${entryWeight(previous[index].weight)} × ${previous[index].reps}'
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
      sets: sets,
      note: old.note,
    );
    setState(() => _session = _session.copyWith(exercises: exercises));
  }

  void _showAddSetDialog(int exerciseIndex) {
    WorkoutDialogs.showAddSetDialog(
      context,
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
      set: set,
      onSave: (updated) {
        final sets = List<gym.Set>.of(_session.exercises[exerciseIndex].sets);
        sets[setIndex] = updated;
        _replaceSets(exerciseIndex, sets);
      },
      onDelete: () {
        final sets = List<gym.Set>.of(_session.exercises[exerciseIndex].sets)
          ..removeAt(setIndex);
        _replaceSets(exerciseIndex, sets);
      },
    );
  }
}

class _EditableExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final List<SetEntry> entries;
  final bool enabled;
  final VoidCallback onRemove;
  final void Function(int index, double weight, int reps) onChanged;
  final void Function(int index, int? rpe) onRpeChanged;
  final ValueChanged<int> onDetails;
  final VoidCallback onAddSet;

  const _EditableExerciseCard({
    required this.exercise,
    required this.entries,
    required this.enabled,
    required this.onRemove,
    required this.onChanged,
    required this.onRpeChanged,
    required this.onDetails,
    required this.onAddSet,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final note = exercise.note?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              AppIconButton(
                label: 'Remove ${exercise.name}',
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
          IgnorePointer(
            ignoring: !enabled,
            child: SetEntryTable(
              exerciseName: exercise.name,
              sets: entries,
              onChanged: onChanged,
              onRpeChanged: onRpeChanged,
              onDetails: onDetails,
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
