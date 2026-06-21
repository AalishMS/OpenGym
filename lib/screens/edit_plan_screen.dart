// LIMITATION: ExerciseTemplate stores only name + sets (int count). Actual per-set
// reps/weight are never persisted. Editing a plan always destroys existing set data
// (resets to 8 reps, 0 kg). Fixing this requires a Hive model change (adding reps/weight
// to ExerciseTemplate or a new SetTemplate model) — out of scope.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/settings_provider.dart';
import '../models/workout_plan.dart';
import '../models/exercise_template.dart';
import '../data/exercise_library.dart';
import '../data/plan_colors.dart';
import '../models/exercise_with_sets.dart';
import '../services/hive_service.dart';
import '../theme/app_theme.dart';
import '../widgets/workout/stepper_widget.dart';

class EditPlanScreen extends StatefulWidget {
  final WorkoutPlan plan;
  final int planIndex;

  const EditPlanScreen({
    super.key,
    required this.plan,
    required this.planIndex,
  });

  @override
  State<EditPlanScreen> createState() => _EditPlanScreenState();
}

class _EditPlanScreenState extends State<EditPlanScreen> {
  late TextEditingController _nameController;
  late List<ExerciseWithSets> _exercises;
  Map<int, bool> _expandedExercises = {};
  int? _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan.name);
    _selectedColor = widget.plan.planColor;

    final plans = HiveService.getPlans();
    final freshPlan =
        plans.length > widget.planIndex ? plans[widget.planIndex] : null;

    _exercises = freshPlan?.exercises
            .map((e) => ExerciseWithSets(
                  name: e.name,
                  sets: List.generate(
                    e.sets,
                    (_) => ExerciseSetData(reps: 8, weight: 0),
                  ),
                ))
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _updateSet(int exerciseIndex, int setIndex, int reps, double weight) {
    setState(() {
      final exercise = _exercises[exerciseIndex];
      final newSets = List<ExerciseSetData>.from(exercise.sets);
      newSets[setIndex] = ExerciseSetData(reps: reps, weight: weight);
      _exercises[exerciseIndex] = exercise.copyWith(sets: newSets);
    });
  }

  void _deleteSet(int exerciseIndex, int setIndex) {
    setState(() {
      final exercise = _exercises[exerciseIndex];
      if (exercise.sets.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('> Cannot delete the last set',
                style: GoogleFonts.jetBrainsMono()),
            backgroundColor: errorColor(context),
          ),
        );
        return;
      }
      final newSets = List<ExerciseSetData>.from(exercise.sets);
      newSets.removeAt(setIndex);
      _exercises[exerciseIndex] = exercise.copyWith(sets: newSets);
    });
  }

  void _addSetToExercise(int exerciseIndex) {
    setState(() {
      final exercise = _exercises[exerciseIndex];
      final lastSet = exercise.sets.isNotEmpty ? exercise.sets.last : ExerciseSetData(reps: 8, weight: 0);
      final newSets = List<ExerciseSetData>.from(exercise.sets);
      newSets.add(ExerciseSetData(reps: lastSet.reps, weight: lastSet.weight));
      _exercises[exerciseIndex] = exercise.copyWith(sets: newSets);
    });
  }

  void _showAddExerciseSheet() {
    String selectedCategory = ExerciseLibrary.categoryNames.first;
    String? justAdded;
    final accent = context.read<SettingsProvider>().accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final exercises = ExerciseLibrary.exercisesByCategory[selectedCategory] ?? [];
            final onAccent = accent.computeLuminance() > 0.5
                ? Colors.black
                : Colors.white;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: borderColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '> ADD EXERCISE',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textPrimaryColor(context),
                            letterSpacing: 0.06,
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          child: Icon(Icons.close, size: 16, color: textSecondaryColor(context)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: ExerciseLibrary.categoryNames.map((cat) {
                        final active = cat == selectedCategory;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setSheetState(() => selectedCategory = cat),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: active ? accent : backgroundColor(context),
                                border: Border.all(
                                  color: active ? accent : borderColor(context),
                                ),
                              ),
                              child: Text(
                                cat,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: active ? onAccent : textSecondaryColor(context),
                                  letterSpacing: 0.06,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 3.5,
                      ),
                      itemCount: exercises.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == exercises.length) {
                          return InkWell(
                            onTap: () => _showCustomExerciseDialog(ctx, setSheetState),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: borderColor(context).withAlpha(128)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '[+ CUSTOM]',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final name = exercises[i];
                        final isJust = justAdded == name;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _exercises.add(ExerciseWithSets(
                                name: name,
                                sets: List.generate(3, (_) => ExerciseSetData(reps: 8, weight: 0)),
                              ));
                              _expandedExercises[_exercises.length - 1] = true;
                            });
                            setSheetState(() => justAdded = name);
                            Future.delayed(const Duration(milliseconds: 600), () {
                              if (ctx.mounted) Navigator.pop(ctx);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isJust ? accent.withAlpha(32) : backgroundColor(context),
                              border: Border.all(
                                color: isJust ? accent : borderColor(context),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isJust ? accent : textPrimaryColor(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isJust)
                                  Icon(Icons.check, size: 12, color: accent),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showCustomExerciseDialog(BuildContext sheetContext, void Function(void Function()) setSheetState) {
    // Design note: Custom exercises are session-only. They are added to the local
    // _exercises list but not persisted to ExerciseLibrary. The user cannot re-select
    // a previously created custom exercise from the grid. This is acceptable because the
    // plan creation flow is single-session. Cross-session persistence is future work.
    final accent = context.read<SettingsProvider>().accentColor;
    final existingNames = _exercises.map((e) => e.name).toSet();
    String? inputText;
    String? errorText;
    bool isValid = false;

    showDialog(
      context: sheetContext,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: surfaceColor(context),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              title: Text(
                '> CUSTOM EXERCISE',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: textPrimaryColor(context),
                  letterSpacing: 0.06,
                ),
              ),
              content: TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: textPrimaryColor(context),
                ),
                decoration: InputDecoration(
                  hintText: 'Enter exercise name',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: textSecondaryColor(context),
                  ),
                  errorText: errorText,
                  errorStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: Colors.red,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                ),
                onChanged: (val) {
                  setDialogState(() {
                    inputText = val;
                    if (val.trim().isEmpty) {
                      errorText = 'Name cannot be empty';
                      isValid = false;
                    } else if (existingNames.contains(val.trim())) {
                      errorText = 'Exercise with this name already exists';
                      isValid = false;
                    } else {
                      errorText = null;
                      isValid = true;
                    }
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(
                    '[CANCEL]',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: textSecondaryColor(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isValid
                      ? () {
                          Navigator.pop(dialogCtx);
                          setState(() {
                            _exercises.add(ExerciseWithSets(
                              name: inputText!.trim(),
                              sets: List.generate(3, (_) => ExerciseSetData(reps: 8, weight: 0)),
                            ));
                            _expandedExercises[_exercises.length - 1] = true;
                          });
                          Navigator.pop(sheetContext);
                        }
                      : null,
                  child: Text(
                    '[CONFIRM]',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: isValid ? accent : textSecondaryColor(context).withAlpha(96),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _savePlan() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> Plan name cannot be empty',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
      return;
    }

    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> Add at least one exercise',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
      return;
    }

    final exercises = _exercises
        .map((e) => ExerciseTemplate(
              name: e.name,
              sets: e.sets.length,
            ))
        .toList();

    final plan = WorkoutPlan(
      name: _nameController.text.trim(),
      exercises: exercises,
      planColor: _selectedColor,
    );
    context.read<WorkoutPlanProvider>().updatePlan(widget.planIndex, plan);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<SettingsProvider>().accentColor;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      body: Column(
        children: [
          _buildHeader(accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPlanNameInput(accent),
                  const SizedBox(height: 16),
                  _buildColorPicker(accent),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _exercises.isEmpty
                        ? _buildEmptyState()
                        : ReorderableListView.builder(
                            itemCount: _exercises.length,
                            buildDefaultDragHandles: false,
                            proxyDecorator: _buildReorderProxyDecorator,
                            itemBuilder: (context, i) => Padding(
                              key: ValueKey(_exercises[i].name),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildExerciseCard(_exercises[i], i, accent),
                            ),
                            onReorderItem: _onReorder,
                          ),
                  ),
                  const SizedBox(height: 8),
                  _buildAddExerciseButton(accent),
                  const SizedBox(height: 8),
                  _buildSaveButton(accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor(context))),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.chevron_left, color: accent),
          ),
          const SizedBox(width: 8),
          Text(
            '> EDIT PLAN',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: accent,
              letterSpacing: 0.08,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: _savePlan,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Text(
                '[SAVE]',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: accent,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanNameInput(Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              '>',
              style: GoogleFonts.jetBrainsMono(fontSize: 13, color: accent),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'e.g. PUSH DAY',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                letterSpacing: 0.04,
                color: textPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PLAN COLOR',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: textSecondaryColor(context),
            letterSpacing: 0.08,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kPlanColors.map((colorValue) {
            final color = Color(colorValue);
            final isSelected = _selectedColor == colorValue;
            return GestureDetector(
              onTap: () => setState(() => _selectedColor = colorValue),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(
                    color: isSelected ? accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 16,
                        color: color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final expandedByName = <String, bool>{};
      for (int i = 0; i < _exercises.length; i++) {
        if (_expandedExercises[i] == true) {
          expandedByName[_exercises[i].name] = true;
        }
      }

      final item = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, item);

      _expandedExercises = {};
      for (int i = 0; i < _exercises.length; i++) {
        if (expandedByName[_exercises[i].name] == true) {
          _expandedExercises[i] = true;
        }
      }
    });
  }

  Widget _buildReorderProxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Material(
          color: surfaceColor(context),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderColor(context)),
            borderRadius: BorderRadius.zero,
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  Widget _buildExerciseCard(
      ExerciseWithSets exercise, int exerciseIndex, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border.all(color: borderColor(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDelayedDragStartListener(
                index: exerciseIndex,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.drag_handle, size: 16, color: textSecondaryColor(context)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expandedExercises[exerciseIndex] =
                      !(_expandedExercises[exerciseIndex] ?? false)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 11),
                    child: Row(
                      children: [
                        Text(
                          '[${(exerciseIndex + 1).toString().padLeft(2, '0')}]',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            exercise.name,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textPrimaryColor(context),
                              letterSpacing: 0.03,
                            ),
                          ),
                        ),
                        Text(
                          '${exercise.sets.length} SETS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => setState(() => _exercises.removeAt(exerciseIndex)),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline, size: 14, color: textSecondaryColor(context)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          (_expandedExercises[exerciseIndex] ?? false)
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 14,
                          color: textSecondaryColor(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_expandedExercises[exerciseIndex] ?? false) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: backgroundColor(context)),
              child: Row(
                children: [
                  SizedBox(width: 52,
                      child: Text('SET', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: textSecondaryColor(context)))),
                  Expanded(child: Text('REPS', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: textSecondaryColor(context)))),
                  Expanded(child: Text('KG', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: textSecondaryColor(context)))),
                  const SizedBox(width: 28),
                ],
              ),
            ),
            ...exercise.sets.asMap().entries.map((entry) {
              final si = entry.key;
              final set = entry.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: borderColor(context))),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        (si + 1).toString().padLeft(2, '0'),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: textSecondaryColor(context).withAlpha(128),
                        ),
                      ),
                    ),
                    Expanded(
                      child: StepperWidget(
                        value: set.reps.toDouble(),
                        min: 1,
                        max: 999,
                        step: 1,
                        accent: accent,
                        backgroundColor: backgroundColor(context),
                        surfaceColor: surfaceColor(context),
                        borderColor: borderColor(context),
                        textPrimaryColor: textPrimaryColor(context),
                        textSecondaryColor: textSecondaryColor(context),
                        onChanged: (v) => _updateSet(exerciseIndex, si, v.toInt(), set.weight),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StepperWidget(
                        value: set.weight,
                        min: 0,
                        max: 999,
                        step: 2.5,
                        accent: accent,
                        backgroundColor: backgroundColor(context),
                        surfaceColor: surfaceColor(context),
                        borderColor: borderColor(context),
                        textPrimaryColor: textPrimaryColor(context),
                        textSecondaryColor: textSecondaryColor(context),
                        onChanged: (v) => _updateSet(exerciseIndex, si, set.reps, v),
                      ),
                    ),
                    if (exercise.sets.length > 1)
                      InkWell(
                        onTap: () => _deleteSet(exerciseIndex, si),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 12, color: textSecondaryColor(context)),
                        ),
                      )
                    else
                      const SizedBox(width: 28),
                  ],
                ),
              );
            }),
            InkWell(
              onTap: () => _addSetToExercise(exerciseIndex),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: borderColor(context))),
                ),
                child: Center(
                  child: Text(
                    '+ ADD SET',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      letterSpacing: 0.08,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '// NO EXERCISES ADDED',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: textSecondaryColor(context).withAlpha(96),
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '// TAP [+ ADD EXERCISE] BELOW',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: textSecondaryColor(context).withAlpha(96),
              letterSpacing: 0.06,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddExerciseButton(Color accent) {
    return InkWell(
      onTap: _showAddExerciseSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withAlpha(64)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 12, color: accent),
            const SizedBox(width: 8),
            Text(
              '[+ ADD EXERCISE]',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                letterSpacing: 0.1,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(Color accent) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _savePlan,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
        child: Text(
          '[SAVE PLAN]',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}
