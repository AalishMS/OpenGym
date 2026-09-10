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
import '../widgets/dashboard/dashboard_panel.dart';
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
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }

    final discard = await WorkoutDialogs.showDiscardChangesDialog(context);
    if (discard && mounted) Navigator.pop(context);
  }

  Future<void> _savePlan() async {
    if (!_canSave) return;

    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '> Add at least one exercise',
            style: GoogleFonts.jetBrainsMono(
              color: onColor(errorColor(context)),
            ),
          ),
          backgroundColor: errorColor(context),
        ),
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
      id: existing?.id,
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

    if (widget.isEdit) {
      await provider.updatePlan(plan);
    } else {
      await provider.addPlan(plan);
    }
    if (mounted) Navigator.pop(context);
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
          SnackBar(
            content: Text(
              '> Cannot delete the last set',
              style: GoogleFonts.jetBrainsMono(
                color: onColor(errorColor(context)),
              ),
            ),
            backgroundColor: errorColor(context),
          ),
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
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: backgroundColor(context),
        body: SafeArea(
          child: Column(
            children: [
              _EditorHeader(
                title: widget.isEdit ? 'EDIT PLAN' : 'CREATE PLAN',
                color: planColor,
                canSave: _canSave,
                onBack: _handleBack,
                onSave: _savePlan,
              ),
              Container(height: 2, color: planColor),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: Breakpoints.expanded,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DashboardPanel(
                            title: 'PLAN NAME',
                            child: _PlanNameField(controller: _nameController),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          DashboardPanel(
                            title: 'PLAN COLOR',
                            child: _ColorPicker(
                              selectedColor: _selectedColor,
                              onChanged:
                                  (value) =>
                                      setState(() => _selectedColor = value),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          DashboardPanel(
                            title: 'EXERCISES',
                            caption: '${_exercises.length} TOTAL',
                            child:
                                _exercises.isEmpty
                                    ? const DashboardEmptyLine(
                                      '> no exercises added yet',
                                    )
                                    : ReorderableListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: _exercises.length,
                                      buildDefaultDragHandles: false,
                                      proxyDecorator:
                                          _buildReorderProxyDecorator,
                                      itemBuilder: (context, index) {
                                        final exercise = _exercises[index];
                                        return Padding(
                                          key: ValueKey(exercise.id),
                                          padding: EdgeInsets.only(
                                            bottom:
                                                index == _exercises.length - 1
                                                    ? 0
                                                    : AppSpacing.sm,
                                          ),
                                          child: _ExerciseEditorCard(
                                            exercise: exercise,
                                            splitId: _splitId,
                                            index: index,
                                            accent: planColor,
                                            onToggle:
                                                () => setState(
                                                  () =>
                                                      exercise.expanded =
                                                          !exercise.expanded,
                                                ),
                                            onDelete:
                                                () => _deleteExercise(
                                                  exercise.id,
                                                  exercise.name,
                                                ),
                                            onSetChanged:
                                                (setIndex, reps, weight) =>
                                                    _updateSet(
                                                      index,
                                                      setIndex,
                                                      reps,
                                                      weight,
                                                    ),
                                            onSetDeleted:
                                                (setIndex) =>
                                                    _deleteSet(index, setIndex),
                                            onSetAdded:
                                                () => _addSetToExercise(index),
                                          ),
                                        );
                                      },
                                      onReorderItem: _onReorder,
                                    ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _FullWidthButton(
                            label: 'Add exercise',
                            accent: planColor,
                            onTap: _showAddExerciseSheet,
                          ),
                        ],
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
  final VoidCallback onBack;
  final VoidCallback onSave;

  const _EditorHeader({
    required this.title,
    required this.color,
    required this.canSave,
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
          InkWell(
            onTap: onBack,
            borderRadius: AppRadius.control,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(LucideIcons.chevronLeft, color: color, size: 20),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: textPrimaryColor(context),
              ),
            ),
          ),
          InkWell(
            onTap: canSave ? onSave : null,
            borderRadius: AppRadius.button,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: canSave ? color : color.withAlpha(32),
                borderRadius: AppRadius.button,
              ),
              child: Center(
                child: Text(
                  'SAVE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        canSave
                            ? onColor(color)
                            : textSecondaryColor(context).withAlpha(128),
                    letterSpacing: 0.1,
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

class _PlanNameField extends StatelessWidget {
  final TextEditingController controller;

  const _PlanNameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        letterSpacing: 0.04,
        color: textPrimaryColor(context),
      ),
      decoration: InputDecoration(
        hintText: 'e.g. PUSH DAY',
        hintStyle: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: textSecondaryColor(context),
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final int? selectedColor;
  final ValueChanged<int> onChanged;

  const _ColorPicker({required this.selectedColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: List.generate(kPlanColors.length, (slot) {
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
            borderRadius: AppRadius.control,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(
                  color:
                      selected ? textPrimaryColor(context) : Colors.transparent,
                  width: 2,
                ),
                borderRadius: AppRadius.control,
              ),
              child:
                  selected
                      ? Icon(LucideIcons.check, size: 16, color: onColor(color))
                      : null,
            ),
          ),
        );
      }),
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
  List<TextSpan> _prescriptionSpans(TextStyle number, TextStyle unit) {
    final sets = exercise.sets;
    if (sets.isEmpty) return [TextSpan(text: 'no sets', style: unit)];

    final reps = sets.map((set) => set.reps);
    final weights = sets.map((set) => set.weight);
    final minReps = reps.reduce((a, b) => a < b ? a : b);
    final maxReps = reps.reduce((a, b) => a > b ? a : b);
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);

    final spans = <TextSpan>[TextSpan(text: '${sets.length}', style: number)];

    if (minReps == maxReps) {
      spans.add(TextSpan(text: ' × ', style: unit));
      spans.add(TextSpan(text: '$maxReps', style: number));
    } else {
      // Ranges only once the sets actually disagree. `3 × 8` is the common case
      // and stays the short one.
      spans.add(TextSpan(text: ' sets  ·  ', style: unit));
      spans.add(TextSpan(text: '$minReps–$maxReps', style: number));
      spans.add(TextSpan(text: ' reps', style: unit));
    }

    // A draft with no weight on it yet is bodyweight or simply unfilled; either
    // way `0kg` is noise, so the whole clause drops out.
    if (maxWeight > 0) {
      spans.add(TextSpan(text: '  ·  ', style: unit));
      spans.add(
        TextSpan(
          text:
              minWeight == maxWeight
                  ? formatWeight(maxWeight)
                  : '${formatWeight(minWeight)}–${formatWeight(maxWeight)}',
          style: number,
        ),
      );
      spans.add(TextSpan(text: 'kg', style: unit));
    }

    return spans;
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              // A hairline rule, not a filled band: the sets are the card's
              // content, not a separate region of it.
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: border)),
              ),
              child: SetEntryTable(
                exerciseName: exercise.name,
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

  Widget _buildHeader(BuildContext context, bool expanded) {
    final textSecondary = textSecondaryColor(context);

    return InkWell(
      onTap: onToggle,
      // Collapsed, this header *is* the card, so its splash has to follow all
      // four corners; expanded, only the top two.
      borderRadius: expanded ? AppRadius.cardTop : AppRadius.card,
      splashColor: accent.withValues(alpha: 0.2),
      highlightColor: accent.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            // An explicit handle, so it drags the moment it is touched. Behind a
            // long-press it read as a handle that did not work.
            ReorderableDragStartListener(
              index: index,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  LucideIcons.gripVertical,
                  size: 14,
                  color: textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                          // The card's title, not its headline — the
                          // prescription below it is the data.
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(left: _nameIndent),
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: _prescriptionSpans(
                          GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                            color: textPrimaryColor(context),
                          ),
                          GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            height: 1.1,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // An indicator, not a tap target — the whole header toggles.
            Icon(
              expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 14,
              color: textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, Color border) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
      child: Row(
        children: [
          _FooterIconAction(
            semanticLabel: 'Add set',
            icon: LucideIcons.plus,
            color: accent,
            onTap: onSetAdded,
          ),
          const Spacer(),
          // Destructive, so it states its consequence in words down here rather
          // than sitting in the header as a grey glyph one thumb-width from the
          // chevron, where a mis-tap used to cost an exercise and all its sets.
          _FooterIconAction(
            semanticLabel: 'Delete exercise',
            icon: LucideIcons.trash2,
            color: textSecondaryColor(context),
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

/// An icon action in an exercise card's footer.
class _FooterIconAction extends StatelessWidget {
  final String semanticLabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FooterIconAction({
    required this.semanticLabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.badge,
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.1),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _FullWidthButton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _FullWidthButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.button,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withAlpha(64)),
          borderRadius: AppRadius.button,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (label == 'Add exercise') ...[
              Icon(LucideIcons.plus, size: 12, color: accent),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
