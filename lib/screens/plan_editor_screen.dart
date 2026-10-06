import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/plan_colors.dart';
import '../models/exercise_set_data.dart';
import '../models/exercise_template.dart';
import '../models/set_template.dart';
import '../models/workout_plan.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/split_provider.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../utils/format.dart';
import '../widgets/action_progress.dart';
import '../widgets/app_button.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/workout/set_entry_table.dart';
import '../utils/set_history.dart';
import '../widgets/workout/workout_dialogs.dart';

class PlanEditorScreen extends StatefulWidget {
  final WorkoutPlan? plan;

  const PlanEditorScreen.create({super.key}) : plan = null;

  const PlanEditorScreen.edit(WorkoutPlan this.plan, {super.key});

  bool get isEdit => plan != null;

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  final _nameController = TextEditingController();
  final List<_EditorExercise> _exercises = [];
  int _nextExerciseId = 0;
  int? _selectedColor = kPlanColors[0];
  late String _initialSignature;
  String? _splitId;
  bool _isSaving = false;
  bool _saved = false;
  String? _draftId;

  bool get _canSave => _nameController.text.trim().isNotEmpty;

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
            note: exercise.note,
            sets: List.generate(exercise.sets, (index) {
              final target = exercise.targetAt(index);
              return ExerciseSetData(
                reps: target?.reps ?? 8,
                weight: target?.weight ?? 0,
              );
            }),
            expanded: false,
          ),
        );
      }
    }

    _initialSignature = _signature();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _signature() {
    final exerciseParts = _exercises
        .map((exercise) {
          final sets = exercise.sets
              .map((set) => '${set.reps}x${set.weight}')
              .join(',');
          return '${exercise.name}:${exercise.note ?? ''}:$sets';
        })
        .join('|');
    return '${_nameController.text.trim()}|$_selectedColor|$exerciseParts';
  }

  Future<void> _handleBack() async {
    if (_isSaving) return;
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }

    final discard = await WorkoutDialogs.showDiscardChangesDialog(context);
    if (discard && mounted) Navigator.pop(context);
  }

  Future<void> _savePlan() async {
    if (_isSaving || _saved || !_canSave) return;

    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise to save')),
      );
      return;
    }

    final templates =
        _exercises
            .map(
              (exercise) => ExerciseTemplate(
                name: exercise.name,
                sets: exercise.sets.length,
                note: exercise.note,
                setTargets:
                    exercise.sets
                        .map(
                          (set) =>
                              SetTemplate(reps: set.reps, weight: set.weight),
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
        await provider.addPlan(plan);
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

  int? _nextPlanPosition(List<WorkoutPlan> plans) {
    if (widget.isEdit || plans.isEmpty) return null;
    if (plans.any((plan) => plan.position == null)) return null;
    return plans.map((plan) => plan.position!).reduce((a, b) => a > b ? a : b) +
        1;
  }

  void _updateSet(int exerciseIndex, int setIndex, int reps, double weight) {
    setState(() {
      _exercises[exerciseIndex].sets[setIndex] = ExerciseSetData(
        reps: reps,
        weight: weight,
      );
    });
  }

  void _addSetToExercise(int exerciseIndex) {
    setState(() {
      final sets = _exercises[exerciseIndex].sets;
      final lastSet =
          sets.isNotEmpty ? sets.last : ExerciseSetData(reps: 8, weight: 0);
      sets.add(ExerciseSetData(reps: lastSet.reps, weight: lastSet.weight));
    });
  }

  void _deleteSet(int exerciseIndex, int setIndex) {
    setState(() {
      final sets = _exercises[exerciseIndex].sets;
      if (sets.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Each exercise needs at least one set')),
        );
        return;
      }
      sets.removeAt(setIndex);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
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
    setState(() => _exercises.removeWhere((exercise) => exercise.id == id));
  }

  void _addExercise(String name) {
    final lower = name.toLowerCase();
    if (_exercises.any((exercise) => exercise.name.toLowerCase() == lower)) {
      return;
    }
    setState(() {
      _exercises.add(
        _EditorExercise(
          id: _nextExerciseId++,
          name: name,
          sets: [ExerciseSetData(reps: 8, weight: 0)],
          expanded: true,
        ),
      );
    });
  }

  void _removeExercise(String name) {
    final normalizedName = name.toLowerCase();
    setState(() {
      _exercises.removeWhere(
        (exercise) => exercise.name.toLowerCase() == normalizedName,
      );
    });
  }

  void _showAddExerciseSheet() {
    showExercisePickerSheet(
      context,
      selectedExerciseNames: _exercises.map((exercise) => exercise.name),
      onAdd: _addExercise,
      onRemove: _removeExercise,
      selectionOwner: 'plan',
    );
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
            color: surfaceColor(context),
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: borderColor(context)),
              borderRadius: AppRadius.card,
            ),
            child: child,
          ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final planColor = _planColor(context);

    return PopScope(
      canPop: _saved || (!_isSaving && !_isDirty),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: backgroundColor(context),
        // Pinned rather than trailing the list, so adding the fifth exercise
        // does not mean scrolling past the first four first.
        bottomNavigationBar: _AddExerciseBar(
          accent: planColor,
          onTap: _isSaving || _saved ? null : _showAddExerciseSheet,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _EditorHeader(
                title: widget.isEdit ? 'Edit plan' : 'New plan',
                color: planColor,
                canSave: _canSave && !_isSaving && !_saved,
                isSaving: _isSaving,
                onBack: _handleBack,
                onSave: _savePlan,
              ),
              Container(height: 2, color: planColor),
              Expanded(
                child: AbsorbPointer(
                  absorbing: _isSaving,
                  child: SingleChildScrollView(
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
                            const _SectionHeading(title: 'Plan name'),
                            _PlanNameField(
                              controller: _nameController,
                              marker: planColor,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            const _SectionHeading(title: 'Color'),
                            _ColorPicker(
                              selectedColor: _selectedColor,
                              onChanged:
                                  (value) =>
                                      setState(() => _selectedColor = value),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            _SectionHeading(
                              title: 'Exercises',
                              count: _exercises.length,
                              hint:
                                  _exercises.length > 1
                                      ? 'Drag to reorder'
                                      : null,
                            ),
                            if (_exercises.isEmpty)
                              const _EmptyExercises()
                            else
                              _buildExerciseList(planColor),
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

  Widget _buildExerciseList(Color planColor) {
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
          padding: EdgeInsets.only(
            bottom: index == _exercises.length - 1 ? 0 : AppSpacing.sm,
          ),
          child: _ExerciseEditorCard(
            exercise: exercise,
            splitId: _splitId,
            index: index,
            accent: planColor,
            onToggle:
                () => setState(() => exercise.expanded = !exercise.expanded),
            onDelete: () => _deleteExercise(exercise.id, exercise.name),
            onSetChanged:
                (setIndex, reps, weight) =>
                    _updateSet(index, setIndex, reps, weight),
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
  final String? note;
  List<ExerciseSetData> sets;
  bool expanded;

  _EditorExercise({
    required this.id,
    required this.name,
    this.note,
    required this.sets,
    required this.expanded,
  });
}

class _EditorHeader extends StatelessWidget {
  final String title;
  final Color color;
  final bool canSave;
  final bool isSaving;
  final VoidCallback onBack;
  final VoidCallback onSave;

  const _EditorHeader({
    required this.title,
    required this.color,
    required this.canSave,
    required this.isSaving,
    required this.onBack,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Row(
        children: [
          AppIconButton(
            label: 'Back',
            icon: LucideIcons.chevronLeft,
            color: color,
            onPressed: isSaving ? null : onBack,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: textPrimaryColor(context),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: canSave ? onSave : null,
            borderRadius: AppRadius.button,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: canSave ? color : color.withAlpha(32),
                borderRadius: AppRadius.button,
              ),
              child: Center(
                child:
                    isSaving
                        ? const ActionProgress('Saving plan')
                        : Text(
                          'Save',
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(
                            color:
                                canSave
                                    ? onColor(color)
                                    : textSecondaryColor(context),
                          ),
                        ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// A sentence-case label over one section of the editor, with an optional
/// count beside it and a muted hint pushed to the far edge.
class _SectionHeading extends StatelessWidget {
  final String title;
  final int? count;
  final String? hint;

  const _SectionHeading({required this.title, this.count, this.hint});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
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
            Text(
              '$count',
              style: textTheme.titleSmall?.copyWith(color: secondary),
            ),
          ],
          const SizedBox(width: AppSpacing.md),
          if (hint != null)
            Expanded(
              child: Text(
                hint!,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanNameField extends StatelessWidget {
  final TextEditingController controller;

  /// The plan's colour, shown as the same bar the workout header leads with,
  /// so the name and colour read as one identity while they are being chosen.
  final Color marker;

  const _PlanNameField({required this.controller, required this.marker});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      style: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: textPrimaryColor(context),
      ),
      decoration: InputDecoration(
        hintText: 'e.g. Push day',
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: textSecondaryColor(context),
        ),
        filled: true,
        fillColor: surfaceColor(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.sm,
          ),
          child: ExcludeSemantics(
            child: Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: marker,
                borderRadius: AppRadius.micro,
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
          duration: const Duration(milliseconds: 150),
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

class _ExerciseEditorCard extends StatelessWidget {
  final _EditorExercise exercise;
  final int index;
  final String? splitId;
  final Color accent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final void Function(int setIndex, int reps, double weight) onSetChanged;
  final ValueChanged<int> onSetDeleted;
  final VoidCallback onSetAdded;

  const _ExerciseEditorCard({
    required this.exercise,
    this.splitId,
    required this.index,
    required this.accent,
    required this.onToggle,
    required this.onDelete,
    required this.onSetChanged,
    required this.onSetDeleted,
    required this.onSetAdded,
  });

  /// Indent that lines the prescription up under the exercise name rather than
  /// under its index badge.
  static const double _nameIndent = 20 + AppSpacing.sm;

  /// What this exercise prescribes, in one line, so a collapsed card reads as a
  /// plan instead of just a title.
  ///
  /// Spans rather than a plain string because the numbers carry the line and the
  /// units step back out of the way — the same hierarchy as the entry table, so a collapsed card
  /// previews its own contents in the voice they are written in.
  List<TextSpan> _prescriptionGroups(TextStyle number, TextStyle unit) {
    final sets = exercise.sets;
    if (sets.isEmpty) return [TextSpan(text: 'No sets', style: unit)];
    final reps = sets.map((set) => set.reps);
    final weights = sets.map((set) => set.weight);
    final minReps = reps.reduce((a, b) => a < b ? a : b);
    final maxReps = reps.reduce((a, b) => a > b ? a : b);
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    return [
      if (minReps == maxReps)
        TextSpan(
          children: [
            TextSpan(text: '${sets.length}', style: number),
            TextSpan(text: ' × ', style: unit),
            TextSpan(text: '$maxReps', style: number),
          ],
        )
      else ...[
        TextSpan(
          children: [
            TextSpan(text: '${sets.length}', style: number),
            TextSpan(text: ' sets', style: unit),
          ],
        ),
        TextSpan(
          children: [
            TextSpan(text: '$minReps–$maxReps', style: number),
            TextSpan(text: ' reps', style: unit),
          ],
        ),
      ],
      if (maxWeight > 0)
        TextSpan(
          children: [
            TextSpan(
              text:
                  minWeight == maxWeight
                      ? formatWeight(maxWeight)
                      : '${formatWeight(minWeight)}–${formatWeight(maxWeight)}',
              style: number,
            ),
            TextSpan(text: ' kg', style: unit),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final border = borderColor(context);
    final expanded = exercise.expanded;
    final previous = previousExerciseSets(
      HiveService.getSessions(),
      exercise.name,
      splitId: splitId,
    );

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: border),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, expanded),
          if (expanded) ...[
            Container(
              // Narrower side padding than the header: the set table is the
              // widest thing on the screen and every pixel here keeps it from
              // scrolling sideways on a phone.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              // A hairline rule, not a filled band: the sets are the card's
              // content, not a separate region of it.
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: border)),
              ),
              child: SetEntryTable(
                showPrevious: false,
                sets: [
                  for (var i = 0; i < exercise.sets.length; i++)
                    SetEntry(
                      weight: exercise.sets[i].weight,
                      reps: exercise.sets[i].reps,
                      previous:
                          i < previous.length && previous[i].reps > 0
                              ? '${entryWeight(previous[i].weight)} × ${previous[i].reps}'
                              : null,
                    ),
                ],
                onChanged:
                    (index, weight, reps) => onSetChanged(index, reps, weight),
                onDelete: onSetDeleted,
              ),
            ),
            _buildFooter(context, border),
          ],
        ],
      ),
    );
  }

  Widget _prescriptionSummary(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.xs,
    children: [
      for (final group in _prescriptionGroups(
        GoogleFonts.jetBrainsMono(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          height: 1.4,
          color: textPrimaryColor(context),
        ),
        GoogleFonts.jetBrainsMono(
          fontSize: 12,
          height: 1.4,
          color: textSecondaryColor(context),
        ),
      ))
        Text.rich(group),
    ],
  );
  Widget _buildHeader(BuildContext context, bool expanded) {
    final textSecondary = textSecondaryColor(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: expanded ? AppRadius.cardTop : AppRadius.card,
      splashColor: accent.withValues(alpha: 0.2),
      highlightColor: accent.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          0,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Only a very narrow card (or very large text) gives the summary
            // the full width; otherwise it sits under the name it describes.
            final reflow =
                constraints.maxWidth <
                300 * MediaQuery.textScalerOf(context).scale(1);
            final title = Row(
              children: [
                _IndexBadge(
                  label: '${index + 1}',
                  borderTint: accent,
                  textTint: accent,
                  fontSize: 10,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    exercise.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: reflow ? null : 2,
                    overflow:
                        reflow ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Tooltip(
                        message: 'Drag to reorder',
                        child: SizedBox(
                          width: 44,
                          height: 48,
                          child: Icon(
                            LucideIcons.gripVertical,
                            size: 18,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            if (!reflow) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: _nameIndent,
                                ),
                                child: _prescriptionSummary(context),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 48,
                      child: AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          LucideIcons.chevronDown,
                          size: 18,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (reflow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: _prescriptionSummary(context),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, Color border) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
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
          const SizedBox(width: AppSpacing.sm),
          // Destructive, so it is drawn in the error role and kept at the far
          // end of the footer, away from Add set and from the header chevron,
          // where a mis-tap used to cost an exercise and all its sets.
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

/// The `1` / `2` pill on an exercise header or a set row.
///
/// Fixed width so names and values stay left-aligned once the count passes 9,
/// and tinted by its caller: accent on an exercise, hairline-and-muted on a set,
/// which is what marks the exercise index as the landmark you scan by.
class _IndexBadge extends StatelessWidget {
  final String label;
  final Color borderTint;
  final Color textTint;
  final double fontSize;

  const _IndexBadge({
    required this.label,
    required this.borderTint,
    required this.textTint,
    this.fontSize = 9,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: borderTint),
        borderRadius: AppRadius.badge,
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: textTint,
        ),
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

/// Shown in place of the exercise list until the first one is added.
class _EmptyExercises extends StatelessWidget {
  const _EmptyExercises();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
        borderRadius: AppRadius.card,
      ),
      child: Column(
        children: [
          Icon(LucideIcons.dumbbell, size: 24, color: secondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No exercises yet',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Pick from the exercise library or create your own, then set '
            'a target weight and reps for each set.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }
}

/// The editor's pinned footer: the one action the screen is mostly for.
class _AddExerciseBar extends StatelessWidget {
  final Color accent;
  final VoidCallback? onTap;

  const _AddExerciseBar({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border(top: BorderSide(color: borderColor(context))),
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
              child: OutlinedButton.icon(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: accent),
                ).copyWith(
                  overlayColor: WidgetStatePropertyAll(accent.withAlpha(24)),
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
