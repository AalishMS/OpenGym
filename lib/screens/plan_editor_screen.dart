import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../services/exercise_catalog.dart';
import '../data/plan_colors.dart';
import '../data/plan_starters.dart';
import '../models/exercise_set_data.dart';
import '../models/exercise_template.dart';
import '../models/set.dart' as gym;
import '../models/set_template.dart';
import '../models/workout_plan.dart';
import '../navigation/app_navigation_observer.dart';
import '../providers/settings_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/split_provider.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/breakpoints.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/action_progress.dart';
import '../widgets/app_button.dart';
import '../widgets/app_header.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/raised_card.dart';
import '../widgets/rolling_figure.dart';
import '../widgets/workout/set_entry_table.dart';
import '../utils/set_history.dart';
import '../utils/weight_units.dart';
import '../widgets/workout/workout_dialogs.dart';
import '../widgets/workout/training_block_actions.dart';
import '../widgets/workout/training_block_dialogs.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../providers/training_block_provider.dart';
import '../widgets/workout/training_block_strip.dart';

/// How many sets an exercise added to a plan starts with.
const int kNewExerciseSets = 3;

class PlanEditorScreen extends StatefulWidget {
  final WorkoutPlan? plan;

  const PlanEditorScreen.create({super.key}) : plan = null;

  const PlanEditorScreen.edit(WorkoutPlan this.plan, {super.key});

  bool get isEdit => plan != null;

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen>
    with AppRouteParticipant<PlanEditorScreen> {
  @override
  Future<void> leaveRoute() => _handleBack();

  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  final _scrollController = ScrollController();
  final List<_EditorExercise> _exercises = [];

  /// Each exercise's card, so the editor can scroll to what was just added.
  final Map<int, GlobalKey> _exerciseKeys = {};

  /// Exercises added since the last frame, in the order they arrived. Their
  /// cards play an entrance once; exercises loaded with the plan don't.
  final List<int> _arriving = [];

  /// Whether the plan has held an exercise, so an empty list that comes back
  /// (an Undo, the last exercise deleted) fades in instead of snapping.
  bool _hadExercises = false;
  int _nextExerciseId = 0;
  int? _selectedColor = kPlanColors[0];
  late String _initialSignature;
  String? _splitId;
  bool _isSaving = false;
  bool _saved = false;
  bool _showColors = false;

  /// The Undo offered after a starter fills the plan, while it is showing.
  ///
  /// While set, it is the current snackbar: whatever showed before it is
  /// removed outright, so Undo never waits in the queue, and snackbars shown
  /// after it queue behind it.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _starterUndo;

  /// Set by a Save that found the plan incomplete: from then on, whatever is
  /// still missing is named inline, and clears as soon as it is supplied.
  bool _showMissing = false;
  String? _draftId;
  String? _startingWeekId;
  // The block the starting week is in, kept so a week removed by shortening
  // can fall back to that block's last remaining week.
  String? _startingBlockId;

  bool get _hasName => _nameController.text.trim().isNotEmpty;

  /// A plan needs a name and at least one exercise. Save stays tappable
  /// either way, so it can say what is missing instead of greying out.
  bool get _isReady => _hasName && _exercises.isNotEmpty;

  String? get _missingHint => switch ((_hasName, _exercises.isNotEmpty)) {
    (false, false) => 'Needs a name and an exercise',
    (false, true) => 'Needs a name',
    (true, false) => 'Needs an exercise',
    (true, true) => null,
  };

  bool get _isDirty => _signature() != _initialSignature;

  Color _planColor(BuildContext context) =>
      planColorOf(_selectedColor, context);

  @override
  void initState() {
    super.initState();

    final plan = widget.plan;
    _splitId = plan?.splitId ?? context.read<SplitProvider?>()?.activeSplitId;
    if (plan != null) {
      final freshPlan =
          plan.id != null ? HiveService.getPlanById(plan.id!) : plan;
      final source = freshPlan ?? plan;
      _nameController.text = source.name;
      _selectedColor = source.planColor;
      for (final exercise in source.exercises) {
        _exercises.add(
          _EditorExercise(
            id: _nextExerciseId++,
            name: exercise.name,
            exerciseId: exercise.exerciseId,
            note: exercise.note,
            sets: List.generate(exercise.sets, (index) {
              final target = exercise.targetAt(index);
              return ExerciseSetData(
                reps: target?.reps ?? 8,
                weight: target?.weight ?? 0,
                rpe: target?.rpe,
              );
            }),
            expanded: true,
          ),
        );
      }
    }
    _hadExercises = _exercises.isNotEmpty;

    if (!widget.isEdit) _selectedColor = _firstFreeColor();

    if (!widget.isEdit && _splitId != null) {
      final blocks = HiveService.blocksForSplit(_splitId!);
      if (blocks.isNotEmpty) {
        _startingWeekId =
            HiveService.weeksForBlock(
              _splitId!,
              blocks.first.id,
            ).firstOrNull?.id;
        _startingBlockId = blocks.first.id;
      }
    }
    _initialSignature = _signature();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// The first palette colour no other plan in this split wears, so a new
  /// plan is told apart on Home without a trip to the palette. Once all ten
  /// are taken, the palette repeats in order.
  int _firstFreeColor() {
    final plans = HiveService.getPlans(splitId: _splitId);
    final used = {
      for (final plan in plans)
        if (plan.planColor != null) planSlotOf(plan.planColor!),
    };
    for (var slot = 0; slot < kPlanColors.length; slot++) {
      if (!used.contains(slot)) return kPlanColors[slot];
    }
    return kPlanColors[plans.length % kPlanColors.length];
  }

  String _signature() {
    final exerciseParts = _exercises
        .map((exercise) {
          final sets = exercise.sets
              .map((set) => '${set.reps}x${set.weight}@${set.rpe}')
              .join(',');
          return '${exercise.name}:${exercise.note ?? ''}:$sets';
        })
        .join('|');
    return '${_nameController.text.trim()}|$_selectedColor|$exerciseParts|${_startingWeekId ?? ''}';
  }

  Future<void> _handleBack() async {
    if (_isSaving) return;
    // The keypad is the nearest Back layer, including when a notification
    // asks this editor to leave through its registered route participant.
    if (ModalRoute.of(context)?.willHandlePopInternally ?? false) {
      Navigator.pop(context);
      return;
    }
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }

    final discard = await WorkoutDialogs.showDiscardChangesDialog(context);
    if (discard && mounted) Navigator.pop(context);
  }

  List<TrainingBlock> get _startingBlocks =>
      _splitId == null ? [] : HiveService.blocksForSplit(_splitId!);
  Map<String, List<TrainingWeek>> get _startingWeeks => {
    for (final b in _startingBlocks)
      b.id: HiveService.startingWeeksForBlock(_splitId!, b.id),
  };
  String get _startingLabel {
    final week =
        _startingWeekId == null
            ? null
            : _startingWeeks.values
                .expand((w) => w)
                .where((w) => w.id == _startingWeekId)
                .firstOrNull;
    final block =
        week == null ? null : HiveService.getTrainingBlockById(week.blockId);
    if (week != null &&
        week.deletedAt == null &&
        block != null &&
        block.deletedAt == null &&
        week.splitId == _splitId) {
      return '${block.name} · Week ${week.number}';
    }
    return 'Choose starting week';
  }

  TrainingBlockSnapshot _loadBlocks() => (
    blocks: _startingBlocks,
    weeksByBlock: _startingWeeks,
  );

  /// Block changes write straight to storage, outside this form's Save and
  /// Discard, so they never touch the dirty signature.
  TrainingBlockActions get _blockActions => TrainingBlockActions(
    context: () => context,
    splitId: _splitId!,
    ownerId:
        () =>
            widget.plan?.userId ?? HiveService.getSplitById(_splitId!)?.userId,
    onChanged: () => setState(_settleStartingWeek),
  );

  /// Keeps the chosen starting week on a week that exists: blocks change
  /// outside this form's Save, so a delete or a shorten can remove it.
  void _settleStartingWeek() {
    final id = _startingWeekId;
    if (id == null || _splitId == null) return;
    final weeks = _startingWeeks;
    for (final entry in weeks.entries) {
      if (entry.value.any((w) => w.id == id)) {
        _startingBlockId = entry.key;
        return;
      }
    }
    final kept = weeks[_startingBlockId]?.lastOrNull;
    if (kept != null) {
      _startingWeekId = kept.id;
      return;
    }
    final first = _startingBlocks.firstOrNull;
    _startingBlockId = first?.id;
    _startingWeekId = first == null ? null : weeks[first.id]?.firstOrNull?.id;
  }

  String? _blockOfStartingWeek(String weekId) {
    for (final entry in _startingWeeks.entries) {
      if (entry.value.any((w) => w.id == weekId)) return entry.key;
    }
    return null;
  }

  Future<void> _chooseStart() async {
    final chosen = await TrainingBlockDialogs.startingWeek(
      context,
      blocks: _startingBlocks,
      weeksByBlock: _startingWeeks,
      selectedWeekId: _startingWeekId,
      load: _loadBlocks,
      onCreateBlock: (name, count) => _blockActions.create(name, count),
      onEditBlock:
          (block, name, count) => _blockActions.edit(block, name, count),
      lifecycle: _blockActions.lifecycle,
    );
    if (!mounted) return;
    setState(() {
      if (chosen != null) {
        _startingWeekId = chosen;
        _startingBlockId = _blockOfStartingWeek(chosen);
      }
      // Blocks may have been deleted or shortened while the sheet was open,
      // whether or not a week was confirmed.
      _settleStartingWeek();
    });
  }

  /// The block the plan is in now, e.g. `Strength · Week 2 of 4`.
  String get _currentBlockLabel {
    final planId = widget.plan?.id;
    final progress =
        planId == null || _splitId == null
            ? null
            : HiveService.progressForPlan(_splitId!, planId);
    final week =
        progress == null
            ? null
            : HiveService.getTrainingWeekById(progress.activeWeekId);
    final block =
        week == null || week.deletedAt != null
            ? null
            : HiveService.getTrainingBlockById(week.blockId);
    if (block == null || block.deletedAt != null) return 'Not in a block';
    final length = trainingBlockLength(
      block,
      HiveService.weeksForBlock(_splitId!, block.id),
    );
    return '${block.name} · Week ${week!.number} of $length';
  }

  String? get _currentBlockId {
    final planId = widget.plan?.id;
    if (planId == null || _splitId == null) return null;
    final progress = HiveService.progressForPlan(_splitId!, planId);
    return progress == null
        ? null
        : HiveService.getTrainingWeekById(progress.activeWeekId)?.blockId;
  }

  Future<void> _manageBlocks() => TrainingBlockDialogs.manage(
    context,
    load: _loadBlocks,
    onCreateBlock: (name, count) => _blockActions.create(name, count),
    onEditBlock: (block, name, count) => _blockActions.edit(block, name, count),
    currentBlockId: _currentBlockId,
    lifecycle: _blockActions.lifecycle,
  );

  Future<void> _savePlan() async {
    if (_isSaving || _saved) return;

    if (!_isReady) {
      _explainMissing();
      return;
    }
    // Before the write: an Undo tapped mid-save would empty the editor while
    // the stored plan kept the starter's exercises.
    _dismissStarterUndo();

    final templates =
        _exercises
            .map(
              (exercise) => ExerciseTemplate(
                name: exercise.name,
                exerciseId: exercise.exerciseId,
                sets: exercise.sets.length,
                note: exercise.note,
                setTargets:
                    exercise.sets
                        .map(
                          (set) => SetTemplate(
                            reps: set.reps,
                            weight: set.weight,
                            rpe: set.rpe,
                          ),
                        )
                        .toList(),
              ),
            )
            .toList();
    final provider = context.read<WorkoutPlanProvider>();
    final existing = widget.plan;
    final plan = WorkoutPlan(
      id: existing?.id ?? _draftId,
      splitId: _splitId,
      userId: existing?.userId,
      updatedAt: existing?.updatedAt,
      deletedAt: existing?.deletedAt,
      dirty: existing?.dirty,
      position: existing?.position ?? _nextPlanPosition(provider.plans),
      name: _nameController.text.trim(),
      exercises: templates,
      planColor: _selectedColor,
    );

    setState(() => _isSaving = true);
    FocusScope.of(context).unfocus();
    try {
      if (widget.isEdit) {
        await provider.updatePlan(plan);
      } else {
        await provider.addPlan(plan, startingWeekId: _startingWeekId);
      }
      if (!mounted) return;
      setState(() {
        _saved = true;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Plan saved')));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (error) {
      debugPrint('Failed to save plan: $error');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the plan. Your edits are still here. Try again.',
          ),
        ),
      );
    } finally {
      // Storage assigns an identity before writing. Reuse it on retry even
      // when the write reports failure after assigning the identity.
      _draftId = plan.id;
    }
  }

  /// Names what Save is waiting for, beside the thing that needs it, and puts
  /// the cursor in the name when that is the gap.
  void _explainMissing() {
    setState(() => _showMissing = true);
    if (!_hasName) {
      _nameFocus.requestFocus();
    } else if (_scrollController.hasClients) {
      final duration = AppMotion.of(context, AppMotion.standard);
      if (duration == Duration.zero) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.animateTo(
          0,
          duration: duration,
          curve: AppMotion.curve,
        );
      }
    }
  }

  int? _nextPlanPosition(List<WorkoutPlan> plans) {
    if (widget.isEdit || plans.isEmpty) return null;
    if (plans.any((plan) => plan.position == null)) return null;
    return plans.map((plan) => plan.position!).reduce((a, b) => a > b ? a : b) +
        1;
  }

  void _updateSet(int exerciseIndex, int setIndex, int reps, double weight) {
    _dismissStarterUndo();
    setState(() {
      _exercises[exerciseIndex].sets[setIndex] = ExerciseSetData(
        reps: reps,
        weight: weight,
        rpe: _exercises[exerciseIndex].sets[setIndex].rpe,
      );
    });
  }

  void _updateRpe(int exerciseIndex, int setIndex, int? rpe) {
    _dismissStarterUndo();
    setState(() {
      final current = _exercises[exerciseIndex].sets[setIndex];
      _exercises[exerciseIndex].sets[setIndex] = ExerciseSetData(
        reps: current.reps,
        weight: current.weight,
        rpe: rpe,
      );
    });
  }

  void _addSetToExercise(int exerciseIndex) {
    _dismissStarterUndo();
    setState(() {
      final sets = _exercises[exerciseIndex].sets;
      final lastSet =
          sets.isNotEmpty
              ? sets.last
              : ExerciseSetData(
                reps:
                    ExerciseCatalog.isTimed(
                          _exercises[exerciseIndex].name,
                          _exercises[exerciseIndex].exerciseId,
                        )
                        ? 30
                        : 8,
                weight: 0,
              );
      sets.add(
        ExerciseSetData(
          reps: lastSet.reps,
          weight: lastSet.weight,
          rpe: lastSet.rpe,
        ),
      );
    });
  }

  void _deleteSet(int exerciseIndex, int setIndex) {
    final sets = _exercises[exerciseIndex].sets;
    if (sets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Each exercise needs at least one set')),
      );
      return;
    }
    _dismissStarterUndo();
    setState(() => sets.removeAt(setIndex));
  }

  void _onReorder(int oldIndex, int newIndex) {
    _dismissStarterUndo();
    setState(() {
      final item = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, item);
    });
  }

  /// Drops an exercise from the draft, behind the same confirmation the workout
  /// screen uses.
  ///
  /// Removes by id rather than index: the list can be reordered while the dialog
  /// is up, and an index captured beforehand would delete the wrong exercise.
  Future<void> _deleteExercise(int id, String name) async {
    final confirmed = await WorkoutDialogs.showDeleteExerciseDialog(
      context,
      exerciseName: name,
    );
    if (!confirmed || !mounted) return;
    _dismissStarterUndo();
    setState(() => _exercises.removeWhere((exercise) => exercise.id == id));
    _exerciseKeys.remove(id);
  }

  void _addExercise(String name, [String? exerciseId]) {
    final id = ExerciseCatalog.identity(name, exerciseId);
    if (_exercises.any(
      (exercise) =>
          ExerciseCatalog.identity(exercise.name, exercise.exerciseId) == id,
    )) {
      return;
    }
    final cardId = _nextExerciseId++;
    _markArriving([cardId]);
    setState(() {
      _exercises.add(
        _EditorExercise(
          id: cardId,
          name: name,
          exerciseId: id,
          // Three working sets, the most common prescription, so a plan
          // starts close to finished: adding a set is one tap, while
          // removing one is a hold and a confirm.
          sets: [
            for (var i = 0; i < kNewExerciseSets; i++)
              ExerciseSetData(
                reps: ExerciseCatalog.isTimed(name, id) ? 30 : 8,
                weight: 0,
              ),
          ],
          expanded: true,
        ),
      );
    });
  }

  /// Fills an empty plan from a common workout: its exercises with their set
  /// and rep targets, and its name if the plan has none yet. Undo restores
  /// both.
  void _applyStarter(PlanStarter starter) {
    final previousName = _nameController.text;
    final nameIt = previousName.trim().isEmpty;
    final added = <int>[];
    // Put the keyboard away: the workout that just arrived is what to look
    // at next, and the keyboard would cover most of it.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      for (final exercise in starter.exercises) {
        final known = ExerciseCatalog.findByName(exercise.name);
        final exerciseId =
            known == null ? null : ExerciseCatalog.canonicalId(known.id);
        final identity = ExerciseCatalog.identity(exercise.name, exerciseId);
        if (_exercises.any(
          (e) => ExerciseCatalog.identity(e.name, e.exerciseId) == identity,
        )) {
          continue;
        }
        final id = _nextExerciseId++;
        added.add(id);
        _exercises.add(
          _EditorExercise(
            id: id,
            name: exercise.name,
            exerciseId: exerciseId,
            note: exercise.note,
            sets: [
              for (final reps in exercise.seedReps)
                ExerciseSetData(reps: reps, weight: 0),
            ],
            // Folded, a whole workout fits on screen and each row previews
            // its targets; open one to set its weights.
            expanded: false,
          ),
        );
      }
    });
    if (nameIt) _nameController.text = starter.name;
    if (added.isEmpty) return;
    _markArriving(added);

    final count = added.length;
    // The queue is cleared and the showing snackbar removed rather than
    // hidden, so Undo shows at once instead of waiting its turn: withdrawing
    // it then hides it, not whatever happened to be on screen.
    final messenger =
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..removeCurrentSnackBar();
    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> undo;
    undo = messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Added $count ${count == 1 ? 'exercise' : 'exercises'} '
          'from ${starter.name}',
        ),
        // An Undo that outlives the moment would strip the starter's
        // exercises after the plan had moved on, so it times out.
        persist: false,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          textColor: accentColor(context),
          onPressed: () {
            // A withdrawn Undo stays tappable while it fades out; by then it
            // would throw away the edit that withdrew it.
            if (!mounted || !identical(_starterUndo, undo)) return;
            setState(() => _exercises.removeWhere((e) => added.contains(e.id)));
            added.forEach(_exerciseKeys.remove);
            if (nameIt && _nameController.text == starter.name) {
              _nameController.text = previousName;
            }
          },
        ),
      ),
    );
    _starterUndo = undo;
    undo.closed.then((_) {
      if (identical(_starterUndo, undo)) _starterUndo = null;
    });
  }

  /// Withdraws a starter's Undo once the reader moves on: an edit to the plan,
  /// the picker, or leaving. Undo removes the starter's exercises whole, so
  /// after an edit it would throw that edit away too.
  void _dismissStarterUndo() {
    if (_starterUndo == null) return;
    _starterUndo = null;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// Folds every exercise when any is open, otherwise opens them all: a
  /// folded list is easier to review and to reorder.
  void _toggleAllExpanded() {
    final expand = !_exercises.any((exercise) => exercise.expanded);
    setState(() {
      for (final exercise in _exercises) {
        exercise.expanded = expand;
      }
    });
  }

  GlobalKey _keyFor(int exerciseId) =>
      _exerciseKeys.putIfAbsent(exerciseId, GlobalKey.new);

  /// Lets the cards for [ids] play their entrance when they are first built,
  /// in this order. The list is cleared after the frame, so a card rebuilt
  /// later (a reorder's drag proxy, say) doesn't play it again.
  void _markArriving(List<int> ids) {
    _hadExercises = true;
    if (_arriving.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _arriving.clear());
    }
    _arriving.addAll(ids);
  }

  /// Brings newly added exercises into view: as many as fit, and never past
  /// the first of them. Nothing moves when they are already on screen.
  void _revealAdded(List<int> ids) {
    if (ids.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final first = _exerciseKeys[ids.first]?.currentContext;
      final last = _exerciseKeys[ids.last]?.currentContext;
      if (first == null || last == null) return;
      // Resolve the destination with instant moves, then animate to it from
      // where the reader was, so the list visibly slides to the new rows.
      final position = _scrollController.position;
      final start = position.pixels;
      Scrollable.ensureVisible(
        last,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        first,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      final target = position.pixels;
      final duration = AppMotion.of(context, AppMotion.enter);
      // Under reduced motion the list simply stays where it was resolved.
      if (target == start || duration == Duration.zero) return;
      position.jumpTo(start);
      position.animateTo(target, duration: duration, curve: AppMotion.curve);
    });
  }

  void _removeExercise(String name, [String? exerciseId]) {
    final normalizedName = ExerciseCatalog.identity(name, exerciseId);
    setState(() {
      _exercises.removeWhere((exercise) {
        final match =
            ExerciseCatalog.identity(exercise.name, exercise.exerciseId) ==
            normalizedName;
        if (match) _exerciseKeys.remove(exercise.id);
        return match;
      });
    });
  }

  Future<void> _showAddExerciseSheet() async {
    // Unfocus the field itself: unfocusing the route's scope leaves the field
    // in that scope's history, so closing the sheet would refocus it.
    FocusManager.instance.primaryFocus?.unfocus();
    _dismissStarterUndo();
    final before = {for (final exercise in _exercises) exercise.id};
    // Exercises already in the plan read as *Added* rather than as ticks, as
    // in the workout: unticking one would throw away the targets set on it
    // without a word. Removing stays with the card's own Delete.
    await showExercisePickerSheet(
      context,
      selectedExerciseNames: const <String>[],
      alreadyAddedExerciseNames: _exercises.map((exercise) => exercise.name),
      userId:
          _splitId == null ? null : HiveService.getSplitById(_splitId!)?.userId,
      selectedExerciseIds: const <String>[],
      alreadyAddedExerciseIds: _exercises.map(
        (e) => ExerciseCatalog.identity(e.name, e.exerciseId),
      ),
      onAddIdentified: _addExercise,
      onRemoveIdentified: _removeExercise,
      onAdd: _addExercise,
      onRemove: _removeExercise,
      selectionOwner: 'plan',
    );
    // Into an empty plan the new cards land just under the heading, already
    // in view; scrolling would only carry the name away.
    if (!mounted || before.isEmpty) return;
    _revealAdded([
      for (final exercise in _exercises)
        if (!before.contains(exercise.id)) exercise.id,
    ]);
  }

  Widget _buildReorderProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder:
          (context, child) => Material(
            color: backgroundColor(context),
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: hairlineColor(context)),
              borderRadius: AppRadius.card,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: child,
            ),
          ),
      child: child,
    );
  }

  /// The line under the Exercises heading, about what can be done with the
  /// cards as they are now: targets are only tappable on an open card.
  String get _editorHint {
    final many = _exercises.length > 1;
    if (_exercises.any((exercise) => exercise.expanded)) {
      return many
          ? 'Tap a target to change it, or hold a set to delete it. Drag the '
              'grip to reorder exercises.'
          : 'Tap a target to change it, or hold a set to delete it.';
    }
    return many
        ? 'Open an exercise to set its targets. Drag the grip to reorder.'
        : 'Open the exercise to set its targets.';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<TrainingBlockProvider?>();
    final planColor = _planColor(context);

    return PopScope(
      canPop: _saved || (!_isSaving && !_isDirty),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          // However the editor closes, a starter's Undo goes with it: left on
          // Home it would offer to undo something on a screen that is gone.
          _dismissStarterUndo();
          return;
        }
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: backgroundColor(context),
        appBar: AppHeader(
          leading: AppBackButton(enabled: !_isSaving, onPressed: _handleBack),
          title: Text(widget.isEdit ? 'Edit plan' : 'New plan'),
          actions: [
            _SaveButton(
              ready: _isReady,
              missingHint: _missingHint,
              isSaving: _isSaving,
              onSave: _isSaving || _saved ? null : _savePlan,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        // Pinned rather than trailing the list, so adding the fifth exercise
        // does not mean scrolling past the first four first.
        bottomNavigationBar: _AddExerciseBar(
          onTap: _isSaving || _saved ? null : _showAddExerciseSheet,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: AbsorbPointer(
                  absorbing: _isSaving,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: Breakpoints.expanded,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The name is the page's title; block and colour
                            // are pills beneath it, so the exercises start
                            // high on the screen.
                            _PlanNameField(
                              controller: _nameController,
                              focusNode: _nameFocus,
                              // Naming is the first step of a new plan, so
                              // the cursor waits there; an edit opens calm.
                              autofocus: !widget.isEdit,
                              marker: planColor,
                              errorText:
                                  _showMissing && !_hasName
                                      ? 'Name this plan to save it'
                                      : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                if (_startingBlocks.isNotEmpty)
                                  if (widget.isEdit)
                                    StartingWeekField(
                                      label: 'Training block',
                                      value: _currentBlockLabel,
                                      onTap: _isSaving ? null : _manageBlocks,
                                    )
                                  else
                                    StartingWeekField(
                                      value: _startingLabel,
                                      onTap: _isSaving ? null : _chooseStart,
                                    ),
                                _ColorPill(
                                  color: planColor,
                                  open: _showColors,
                                  onTap:
                                      () => setState(
                                        () => _showColors = !_showColors,
                                      ),
                                ),
                              ],
                            ),
                            _Collapsible(
                              open: _showColors,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.md,
                                ),
                                child: _ColorPicker(
                                  selectedColor: _selectedColor,
                                  onChanged:
                                      (value) => setState(
                                        () => _selectedColor = value,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            _SectionHeading(
                              title: 'Exercises',
                              count:
                                  _exercises.isEmpty ? null : _exercises.length,
                              trailing:
                                  _exercises.length > 1
                                      ? _FoldAllButton(
                                        expand:
                                            !_exercises.any((e) => e.expanded),
                                        onTap: _toggleAllExpanded,
                                      )
                                      : null,
                            ),
                            if (_exercises.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: _EditorHint(_editorHint),
                              ),
                            if (_exercises.isEmpty)
                              _Entrance(
                                animate: _hadExercises,
                                child: _EmptyExercises(
                                  starters: planStarters,
                                  onStarter:
                                      _isSaving || _saved
                                          ? null
                                          : _applyStarter,
                                  showMissing: _showMissing,
                                ),
                              )
                            else
                              _buildExerciseList(),
                            // Room for the keypad below the last card, so
                            // the card itself keeps its natural height.
                            ValueListenableBuilder<double>(
                              valueListenable: SetEntryTable.keyboardHeight,
                              builder:
                                  (_, height, _) => SizedBox(height: height),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildExerciseList() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _exercises.length,
      buildDefaultDragHandles: false,
      proxyDecorator: _buildReorderProxyDecorator,
      itemBuilder: (context, index) {
        final exercise = _exercises[index];
        return Padding(
          key: ValueKey(exercise.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: _ExerciseEditorSection(
            key: _keyFor(exercise.id),
            exercise: exercise,
            splitId: _splitId,
            index: index,
            arrivalOrder:
                _arriving.contains(exercise.id)
                    ? _arriving.indexOf(exercise.id)
                    : null,
            accent: accentColor(context),
            onToggle:
                () => setState(() => exercise.expanded = !exercise.expanded),
            onDelete: () => _deleteExercise(exercise.id, exercise.name),
            onSetChanged:
                (setIndex, reps, weight) =>
                    _updateSet(index, setIndex, reps, weight),
            onRpeChanged: (setIndex, rpe) => _updateRpe(index, setIndex, rpe),
            onSetDeleted: (setIndex) => _deleteSet(index, setIndex),
            onSetAdded: () => _addSetToExercise(index),
          ),
        );
      },
      onReorderItem: _onReorder,
    );
  }
}

class _EditorExercise {
  final int id;
  String name;
  final String? exerciseId;
  final String? note;
  List<ExerciseSetData> sets;
  bool expanded;

  _EditorExercise({
    required this.id,
    required this.name,
    this.exerciseId,
    this.note,
    required this.sets,
    required this.expanded,
  });
}

/// Save on the accent ground once the plan is complete. Until then it sits
/// quietly on the control fill, so a blank plan doesn't advertise an action it
/// can't finish, but it stays tappable: a tap names what is missing, where a
/// greyed-out button would leave the reader guessing.
class _SaveButton extends StatelessWidget {
  final bool ready;

  /// What the plan still needs, read to screen readers with the button.
  final String? missingHint;
  final bool isSaving;

  /// Null only while saving or after saving.
  final VoidCallback? onSave;

  const _SaveButton({
    required this.ready,
    required this.missingHint,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final quiet = !ready;
    // Quiet, it is the app's secondary button: a neutral fill with readable
    // ink, so it still looks pressable. Grey ink would read as disabled.
    final ink = quiet ? textPrimaryColor(context) : onAccentColor(context);
    // AppBar stretches its actions to the toolbar height; keep a 48px button.
    return Center(
      child: Semantics(
        hint: ready ? null : missingHint,
        child: ElevatedButton(
          onPressed: onSave,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                quiet ? controlFillColor(context) : accentFillColor(context),
            foregroundColor: ink,
            // A 40px pill; the padded tap target keeps it 48px to the finger.
            minimumSize: const Size(72, 40),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg + 2),
            // The fill and ink ease between quiet and ready.
            animationDuration: AppMotion.of(context, AppMotion.standard),
          ).copyWith(
            // A pill in the header stays flat: a hover or press lifting it
            // into a shadow reads as a different control.
            elevation: const WidgetStatePropertyAll(0),
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => switch (states) {
                _ when states.contains(WidgetState.pressed) => ink.withAlpha(
                  31,
                ),
                _ when states.contains(WidgetState.focused) => ink.withAlpha(
                  26,
                ),
                _ when states.contains(WidgetState.hovered) => ink.withAlpha(
                  20,
                ),
                _ => null,
              },
            ),
          ),
          child:
              isSaving
                  ? const ActionProgress('Saving plan')
                  : const Text('Save'),
        ),
      ),
    );
  }
}

/// *Collapse all* while any exercise is open, *Expand all* once every one is
/// folded.
class _FoldAllButton extends StatelessWidget {
  final bool expand;
  final VoidCallback onTap;

  const _FoldAllButton({required this.expand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: accentColor(context),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: Icon(
        expand ? LucideIcons.chevronsUpDown : LucideIcons.chevronsDownUp,
        size: 16,
      ),
      label: Text(expand ? 'Expand all' : 'Collapse all'),
    );
  }
}

/// A sentence-case label over one section of the editor, with an optional
/// count beside it and an action pushed to the far edge.
class _SectionHeading extends StatelessWidget {
  final String title;
  final int? count;
  final Widget? trailing;

  const _SectionHeading({required this.title, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.only(
        // The action's padded target supplies its own breathing room.
        bottom: trailing == null ? AppSpacing.sm : 0,
      ),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: textPrimaryColor(context),
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: AppSpacing.sm),
            // The count rolls as exercises arrive or go, like the workout's
            // running figures.
            RollingFigure(
              '$count',
              style: textTheme.titleSmall?.copyWith(color: secondary),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PlanNameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;

  /// The plan's colour, shown as the same bar the workout header leads with,
  /// so the name and colour read as one identity while they are being chosen.
  final Color marker;
  final String? errorText;

  const _PlanNameField({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.marker,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = textTheme.headlineLarge?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.2,
      color: textPrimaryColor(context),
    );
    final quick = AppMotion.of(context, AppMotion.quick);
    // The name is set as the page title rather than inside a box: a hairline
    // under it at rest, the accent under it while typing. The error line
    // fades in on its own; the size animation keeps it from shoving the page.
    return AnimatedSize(
      duration: quick,
      curve: AppMotion.curve,
      alignment: AlignmentDirectional.topStart,
      child: Semantics(
        label: 'Plan name',
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          style: title,
          decoration: InputDecoration(
            hintText: 'Plan name',
            hintStyle: title?.copyWith(color: textSecondaryColor(context)),
            errorText: errorText,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.md,
            ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: hairlineColor(context)),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: hairlineColor(context)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accentColor(context), width: 2),
            ),
            // The same rule in the error colour, never the theme's ring: the
            // name stays a title, not a boxed field.
            errorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: errorColor(context)),
            ),
            focusedErrorBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: errorColor(context), width: 2),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.md,
                bottom: AppSpacing.sm,
              ),
              child: ExcludeSemantics(
                child: AnimatedContainer(
                  duration: quick,
                  curve: AppMotion.curve,
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    color: marker,
                    borderRadius: AppRadius.micro,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The plan colour as a compact pill beside the block pill: its swatch and a
/// chevron that turns as the palette opens. Without a label it fits on the
/// block pill's row at phone width; the swatch beside the name's colour bar
/// says what it changes, and its tooltip and screen-reader label say it too.
class _ColorPill extends StatelessWidget {
  final Color color;
  final bool open;
  final VoidCallback onTap;

  const _ColorPill({
    required this.color,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final quick = AppMotion.of(context, AppMotion.quick);
    return Tooltip(
      message: 'Change color',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        expanded: open,
        label: 'Change color',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: controlFillColor(context),
          borderRadius: AppRadius.pill,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: quick,
                      curve: AppMotion.curve,
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: quick,
                      curve: AppMotion.curve,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final int? selectedColor;
  final ValueChanged<int> onChanged;

  const _ColorPicker({required this.selectedColor, required this.onChanged});

  static const double _swatch = 48;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // One row when all ten fit, otherwise two even rows of five, spread
        // edge to edge so the grid lines up with the fields above and below
        // instead of leaving a ragged 6 + 4.
        final perRow =
            constraints.maxWidth >=
                    kPlanColors.length * _swatch +
                        (kPlanColors.length - 1) * AppSpacing.sm
                ? kPlanColors.length
                : (kPlanColors.length / 2).ceil();
        return Column(
          children: [
            for (
              var start = 0;
              start < kPlanColors.length;
              start += perRow
            ) ...[
              if (start > 0) const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (
                    var slot = start;
                    slot < start + perRow && slot < kPlanColors.length;
                    slot++
                  )
                    _buildSwatch(context, slot),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSwatch(BuildContext context, int slot) {
    final colorValue = kPlanColors[slot];
    // Resolved swatch, slot-matched selection — see the home-screen picker.
    final color = planSwatch(slot, context);
    final selected =
        selectedColor != null && planSlotOf(selectedColor!) == slot;
    return Semantics(
      label: 'Plan color ${slot + 1}',
      selected: selected,
      button: true,
      onTap: () => onChanged(colorValue),
      child: InkWell(
        onTap: () => onChanged(colorValue),
        borderRadius: AppRadius.button,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.quick),
          width: _swatch,
          height: _swatch,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
            borderRadius: AppRadius.button,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.badge,
            ),
            child:
                selected
                    ? Icon(LucideIcons.check, size: 18, color: onColor(color))
                    : null,
          ),
        ),
      ),
    );
  }
}

class _ExerciseEditorSection extends StatelessWidget {
  final _EditorExercise exercise;
  final int index;

  /// This card's place among exercises that just arrived, or null for one
  /// that was already here: only arrivals play an entrance.
  final int? arrivalOrder;
  final String? splitId;
  final Color accent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final void Function(int setIndex, int reps, double weight) onSetChanged;
  final void Function(int setIndex, int? rpe) onRpeChanged;
  final ValueChanged<int> onSetDeleted;
  final VoidCallback onSetAdded;

  const _ExerciseEditorSection({
    super.key,
    required this.exercise,
    this.splitId,
    required this.index,
    this.arrivalOrder,
    required this.accent,
    required this.onToggle,
    required this.onDelete,
    required this.onSetChanged,
    required this.onRpeChanged,
    required this.onSetDeleted,
    required this.onSetAdded,
  });

  /// What this exercise prescribes, so a collapsed card reads as a plan
  /// instead of just a title: *3 × 12 · 70 kg* when every set is the same,
  /// otherwise the sets themselves (*70 × 12, 70 × 10, 65 × 8*), up to four
  /// and then *+N*.
  ///
  /// Spans rather than a plain string because the numbers carry the line and the
  /// units step back out of the way — the same hierarchy as the entry table, so a collapsed card
  /// previews its own contents in the voice they are written in.
  ///
  /// Weights read in [weightUnit]; the targets themselves stay kilograms.
  List<InlineSpan> _targetSpans(
    TextStyle number,
    TextStyle unit,
    String weightUnit,
  ) {
    final sets = exercise.sets;
    if (sets.isEmpty) return [TextSpan(text: 'No sets', style: unit)];
    final first = sets.first;
    final uniform = sets.every(
      (set) =>
          set.reps == first.reps &&
          set.weight == first.weight &&
          set.rpe == first.rpe,
    );
    if (uniform) {
      return [
        TextSpan(text: '${sets.length}', style: number),
        TextSpan(text: ' × ', style: unit),
        TextSpan(text: '${first.reps}', style: number),
        if (ExerciseCatalog.isTimed(exercise.name, exercise.exerciseId))
          TextSpan(text: ' s', style: unit),
        if (first.weight > 0) ...[
          TextSpan(text: '  ·  ', style: unit),
          TextSpan(
            text: formatEntryWeight(first.weight, weightUnit),
            style: number,
          ),
          TextSpan(text: ' ${weightUnitLabel(weightUnit)}', style: unit),
        ],
        if (first.rpe != null)
          TextSpan(text: '  ·  RPE ${first.rpe}', style: unit),
      ];
    }
    const shown = 4;
    final weighted = sets.any((set) => set.weight > 0);
    return [
      for (var i = 0; i < sets.length && i < shown; i++) ...[
        if (i > 0) TextSpan(text: ', ', style: unit),
        if (weighted) ...[
          TextSpan(
            text: formatEntryWeight(sets[i].weight, weightUnit),
            style: number,
          ),
          TextSpan(text: ' × ', style: unit),
        ],
        TextSpan(text: '${sets[i].reps}', style: number),
        if (ExerciseCatalog.isTimed(exercise.name, exercise.exerciseId))
          TextSpan(text: ' s', style: unit),
        if (sets[i].rpe != null)
          TextSpan(text: ' @${sets[i].rpe}', style: unit),
      ],
      if (!weighted &&
          !ExerciseCatalog.isTimed(exercise.name, exercise.exerciseId))
        TextSpan(text: ' reps', style: unit),
      if (sets.length > shown)
        TextSpan(text: '  +${sets.length - shown}', style: unit),
    ];
  }

  /// The best set from the last time this exercise was trained in this split,
  /// or null when it never was — so a new exercise doesn't get an empty line.
  String? _lastLine(List<gym.Set> previous, String weightUnit) {
    final done = previous.where((set) => set.reps > 0);
    if (done.isEmpty) return null;
    final top = done.reduce(
      (a, b) =>
          b.weight > a.weight || (b.weight == a.weight && b.reps > a.reps)
              ? b
              : a,
    );
    return top.weight > 0
        ? 'Last: ${formatEntryWeight(top.weight, weightUnit)} '
            '${weightUnitLabel(weightUnit)} \u00d7 ${top.reps}${ExerciseCatalog.isTimed(exercise.name, exercise.exerciseId) ? ' s' : ''}'
        : 'Last: ${top.reps} ${ExerciseCatalog.isTimed(exercise.name, exercise.exerciseId) ? 's' : 'reps'}';
  }

  @override
  Widget build(BuildContext context) {
    final expanded = exercise.expanded;
    final previous = previousExerciseSets(
      HiveService.getSessions(),
      ExerciseCatalog.identity(exercise.name, exercise.exerciseId),
      splitId: splitId,
    );

    // The entrance sits under this card's GlobalKey, so a reorder's drag
    // proxy carries its finished state along instead of replaying it.
    return _Entrance(
      animate: arrivalOrder != null,
      order: arrivalOrder ?? 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairlineColor(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, expanded, previous),
            _Collapsible(
              open: expanded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (exercise.note?.trim().isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        exercise.note!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  SetEntryTable(
                    isTimed: ExerciseCatalog.isTimed(
                      exercise.name,
                      exercise.exerciseId,
                    ),
                    continuousLog: true,
                    scrollWideTable: true,
                    hostReservesSpace: true,
                    showPrevious: false,
                    sets: [
                      for (final set in exercise.sets)
                        SetEntry(
                          weight: set.weight,
                          reps: set.reps,
                          rpe: set.rpe,
                        ),
                    ],
                    onChanged:
                        (index, weight, reps) =>
                            onSetChanged(index, reps, weight),
                    onRpeChanged: onRpeChanged,
                    onDelete: onSetDeleted,
                  ),
                  _buildFooter(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prescriptionSummary(BuildContext context, List<gym.Set> previous) {
    final textSecondary = textSecondaryColor(context);
    final unit = AppTypography.figures(
      fontSize: 13,
      height: 1.4,
      color: textSecondary,
    );
    final weightUnit = SettingsProvider.unitOf(context);
    final last = _lastLine(previous, weightUnit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: _targetSpans(
              AppTypography.figures(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: textPrimaryColor(context),
              ),
              unit,
              weightUnit,
            ),
          ),
        ),
        if (last != null) Text(last, style: unit),
      ],
    );
  }

  /// How far the header's tap ground reaches past its text: inside the ground
  /// as padding, and out into the page gutter by the same amount, so a press
  /// lights a padded box while the name keeps the column's left edge.
  static const double _headerInset = AppSpacing.sm;

  Widget _buildHeader(
    BuildContext context,
    bool expanded,
    List<gym.Set> previous,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _GutterBleed(
              bleed: _headerInset,
              child: Semantics(
                button: true,
                expanded: expanded,
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: AppRadius.button,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                      horizontal: _headerInset,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                exercise.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            AnimatedRotation(
                              turns: expanded ? 0.5 : 0,
                              duration: AppMotion.of(context, AppMotion.quick),
                              curve: AppMotion.curve,
                              child: Icon(
                                LucideIcons.chevronDown,
                                size: 16,
                                color: textSecondaryColor(context),
                              ),
                            ),
                          ],
                        ),
                        // The summary stands in for the table while folded,
                        // and gives way to it as the card opens.
                        _Collapsible(
                          open: !expanded,
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: _prescriptionSummary(context, previous),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: 'Drag to reorder',
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  LucideIcons.gripVertical,
                  size: 18,
                  color: textSecondaryColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _FooterAction(
                semanticLabel: 'Add set',
                label: 'Add set',
                icon: LucideIcons.plus,
                color: accent,
                onTap: onSetAdded,
              ),
            ),
          ),
          _FooterAction(
            semanticLabel: 'Delete exercise',
            icon: LucideIcons.trash2,
            color: errorColor(context),
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Lays [child] out [bleed] wider than its slot and lets the extra reach into
/// the page gutter on the start side.
///
/// For a tap ground that needs padding round its text without moving the text
/// off the column's edge. Only the painted ground bleeds: a tap in the gutter
/// strip itself still falls outside the row, which is fine for an 8px margin.
class _GutterBleed extends StatelessWidget {
  final double bleed;
  final Widget child;

  const _GutterBleed({required this.bleed, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder:
          (context, constraints) => OverflowBox(
            alignment: AlignmentDirectional.centerEnd,
            minWidth: constraints.maxWidth + bleed,
            maxWidth: constraints.maxWidth + bleed,
            fit: OverflowBoxFit.deferToChild,
            child: child,
          ),
    );
  }
}

/// An action in an exercise card's footer: an icon, with a visible label when
/// it is the kind of action a first-time user should be able to read.
class _FooterAction extends StatelessWidget {
  final String semanticLabel;
  final String? label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FooterAction({
    required this.semanticLabel,
    this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final action = Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.1),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: label == null ? 0 : AppSpacing.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                if (label != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      label!,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: color),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return label == null
        ? Tooltip(
          message: semanticLabel,
          excludeFromSemantics: true,
          child: action,
        )
        : action;
  }
}

/// Shown in place of the exercise list until the first one is added: the two
/// ways to begin, the library below and a common workout to adapt.
///
/// The guidance sits on the page; only the starters, which are tappable, get
/// a ground of their own.
class _EmptyExercises extends StatelessWidget {
  final List<PlanStarter> starters;
  final ValueChanged<PlanStarter>? onStarter;

  /// Whether Save has asked for an exercise, so the gap is named here.
  final bool showMissing;

  const _EmptyExercises({
    required this.starters,
    required this.onStarter,
    required this.showMissing,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add exercises from the library, or start from a common workout '
          'and adjust its targets.',
          style: textTheme.bodyMedium?.copyWith(color: secondary),
        ),
        _Collapsible(
          open: showMissing,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 16,
                    color: errorColor(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Add at least one exercise to save',
                      style: textTheme.bodyMedium?.copyWith(
                        color: errorColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (starters.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Semantics(
            header: true,
            child: Text(
              'Start from',
              style: textTheme.titleSmall?.copyWith(
                color: textPrimaryColor(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // One raised card of rows, like a settings group: six starters read
          // as one choice rather than six loose controls.
          RaisedCard(
            child: Column(
              children: [
                for (var i = 0; i < starters.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: AppSpacing.lg,
                      endIndent: AppSpacing.lg,
                      color: hairlineColor(context),
                    ),
                  _StarterRow(
                    starter: starters[i],
                    onTap:
                        onStarter == null
                            ? null
                            : () => onStarter!(starters[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A common workout as a row: its name, then what it holds and trains (*6
/// exercises · Chest, shoulders, arms*), so the choice is made knowing what
/// arrives. The trailing plus says a tap adds it to the plan.
class _StarterRow extends StatelessWidget {
  final PlanStarter starter;
  final VoidCallback? onTap;

  const _StarterRow({required this.starter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final count = starter.exercises.length;
    final exercises = '$count ${count == 1 ? 'exercise' : 'exercises'}';
    final focus = starter.focus;
    final trains = [
      for (var i = 0; i < focus.length; i++)
        i == 0 ? focus[i] : focus[i].toLowerCase(),
    ].join(', ');
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: [
        'Start from ${starter.name}',
        exercises,
        if (trains.isNotEmpty) trains.toLowerCase(),
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        starter.name,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        trains.isEmpty ? exercises : '$exercises  ·  $trains',
                        style: textTheme.bodySmall?.copyWith(color: secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // The tonal wash, as on Add exercise: an add, not a link.
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        enabled
                            ? accentMutedColor(context)
                            : controlFillColor(context),
                    borderRadius: AppRadius.pill,
                  ),
                  child: Icon(
                    LucideIcons.plus,
                    size: 18,
                    color: enabled ? accentOnMutedColor(context) : secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under the Exercises heading. It cross-fades when the cards change
/// between open and folded, since what it describes changes with them.
class _EditorHint extends StatelessWidget {
  final String text;

  const _EditorHint(this.text);

  @override
  Widget build(BuildContext context) {
    // The two hints can differ by a line; the height eases instead of
    // snapping when the old one leaves.
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.curve,
      alignment: AlignmentDirectional.topStart,
      child: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.quick),
        switchInCurve: AppMotion.curve,
        switchOutCurve: AppMotion.exit,
        layoutBuilder:
            (current, previous) => Stack(
              alignment: AlignmentDirectional.topStart,
              children: [...previous, if (current != null) current],
            ),
        child: Text(
          text,
          key: ValueKey(text),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// Opens and closes [child] by growing and fading it from the top, and drops
/// it from the tree once closed, so a folded region holds no controls or
/// semantics. It starts at rest: only a change of [open] animates.
class _Collapsible extends StatefulWidget {
  final bool open;
  final Widget child;

  const _Collapsible({required this.open, required this.child});

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
    value: widget.open ? 1 : 0,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
    reverseCurve: AppMotion.exit,
  );

  void _onStatus(AnimationStatus status) {
    // Settling changes the clip, and closing drops the child.
    if (!status.isAnimating && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_Collapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    _controller.duration = AppMotion.of(context, AppMotion.standard);
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && _controller.isDismissed) return const SizedBox.shrink();
    return ClipRect(
      // Clip only while moving, so a settled region can paint past its edge
      // (focus rings, shadows) as it did before it could fold.
      clipBehavior: _controller.isAnimating ? Clip.hardEdge : Clip.none,
      child: SizeTransition(
        sizeFactor: _progress,
        alignment: AlignmentDirectional.topStart,
        child: FadeTransition(opacity: _progress, child: widget.child),
      ),
    );
  }
}

/// Fades [child] in and lifts it a few pixels into place when it is first
/// built, if [animate]; later [order]s start a beat later, so a batch of new
/// cards arrives in sequence. Changing [animate] afterwards does nothing.
class _Entrance extends StatefulWidget {
  final bool animate;
  final int order;
  final Widget child;

  const _Entrance({required this.animate, this.order = 0, required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  /// The gap between one arrival and the next, and how many gaps at most, so
  /// a long batch doesn't keep the last card waiting.
  static const Duration _stagger = Duration(milliseconds: 40);
  static const int _maxStagger = 6;
  static const double _lift = 8;

  AnimationController? _controller;
  Animation<double> _progress = kAlwaysCompleteAnimation;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) return;
    final delay = _stagger * widget.order.clamp(0, _maxStagger);
    final total = delay + AppMotion.enter;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: AppMotion.curve,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One tree shape whether or not this entrance plays, so the child keeps
    // its state either way.
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        builder:
            (context, child) => Transform.translate(
              offset: Offset(0, _lift * (1 - _progress.value)),
              child: child,
            ),
        child: widget.child,
      ),
    );
  }
}

/// The editor's pinned footer: the one action the screen is mostly for.
class _AddExerciseBar extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddExerciseBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(top: BorderSide(color: hairlineColor(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
              child: ElevatedButton.icon(
                onPressed: onTap,
                style: tonalButtonStyle(context).copyWith(
                  minimumSize: const WidgetStatePropertyAll(
                    Size.fromHeight(52),
                  ),
                ),
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('Add exercise'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
