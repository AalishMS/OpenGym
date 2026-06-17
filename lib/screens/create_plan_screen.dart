import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/settings_provider.dart';
import '../models/workout_plan.dart';
import '../models/exercise_template.dart';
import '../data/exercise_library.dart';
import '../theme/app_theme.dart';

class _ExerciseSetData {
  final int reps;
  final double weight;

  _ExerciseSetData({required this.reps, required this.weight});

  _ExerciseSetData copyWith({int? reps, double? weight}) {
    return _ExerciseSetData(
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
    );
  }
}

class _ExerciseWithSets {
  final String name;
  final List<_ExerciseSetData> sets;

  _ExerciseWithSets({required this.name, required this.sets});

  _ExerciseWithSets copyWith({String? name, List<_ExerciseSetData>? sets}) {
    return _ExerciseWithSets(
      name: name ?? this.name,
      sets: sets ?? this.sets,
    );
  }
}

class CreatePlanScreen extends StatefulWidget {
  const CreatePlanScreen({super.key});

  @override
  State<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends State<CreatePlanScreen> {
  final _nameController = TextEditingController();
  final List<_ExerciseWithSets> _exercises = [];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addExercise() {
    final accent = context.read<SettingsProvider>().accentColor;
    final setsController = TextEditingController(text: '3');
    String? selectedCategory;
    String? selectedExercise;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: surfaceColor(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: borderColor(context), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '> ADD EXERCISE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SELECT CATEGORY',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: textSecondaryColor(context)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: Text('Choose category',
                          style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                      items: ExerciseLibrary.categoryNames.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category,
                              style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedCategory = value;
                          selectedExercise = null;
                        });
                      },
                    ),
                    if (selectedCategory != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'SELECT EXERCISE',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10, color: textSecondaryColor(context)),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedExercise,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        hint: Text('Choose exercise',
                            style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                        items: ExerciseLibrary
                            .exercisesByCategory[selectedCategory]!
                            .map((exercise) {
                          return DropdownMenuItem(
                            value: exercise,
                            child: Text(exercise,
                                style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedExercise = value;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'OR ENTER CUSTOM EXERCISE',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: textSecondaryColor(context)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Custom Exercise Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          setDialogState(() {
                            selectedExercise = value;
                            selectedCategory = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: setsController,
                      decoration: const InputDecoration(
                        labelText: 'Sets',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('[CANCEL]',
                              style: GoogleFonts.jetBrainsMono(
                                  color: textSecondaryColor(context))),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final name = selectedExercise;
                            if (name == null || name.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '> Please select or enter an exercise',
                                      style: GoogleFonts.jetBrainsMono()),
                                  backgroundColor: errorColor(context),
                                ),
                              );
                              return;
                            }

                            final numSets =
                                int.tryParse(setsController.text) ?? 3;
                            final sets = List.generate(
                              numSets,
                              (i) => _ExerciseSetData(reps: 8, weight: 0),
                            );

                            setState(() {
                              _exercises.add(_ExerciseWithSets(
                                name: name.trim(),
                                sets: sets,
                              ));
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.black,
                          ),
                          child: Text('[ ADD ]',
                              style: GoogleFonts.jetBrainsMono()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _duplicateSet(int exerciseIndex, int setIndex) {
    setState(() {
      final exercise = _exercises[exerciseIndex];
      final setToCopy = exercise.sets[setIndex];
      final newSets = List<_ExerciseSetData>.from(exercise.sets);
      newSets.insert(setIndex + 1, setToCopy.copyWith());
      _exercises[exerciseIndex] = exercise.copyWith(sets: newSets);
    });
  }

  void _updateSet(int exerciseIndex, int setIndex, int reps, double weight) {
    setState(() {
      final exercise = _exercises[exerciseIndex];
      final newSets = List<_ExerciseSetData>.from(exercise.sets);
      newSets[setIndex] = _ExerciseSetData(reps: reps, weight: weight);
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
      final newSets = List<_ExerciseSetData>.from(exercise.sets);
      newSets.removeAt(setIndex);
      _exercises[exerciseIndex] = exercise.copyWith(sets: newSets);
    });
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
    );
    context.read<WorkoutPlanProvider>().addPlan(plan);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<SettingsProvider>().accentColor;

    return Scaffold(
      backgroundColor: backgroundColor(context),
      appBar: AppBar(
        backgroundColor: surfaceColor(context),
        title: Text(
          '> CREATE PLAN',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 16, fontWeight: FontWeight.bold, color: accent),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: accent),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          InkWell(
            onTap: _savePlan,
            splashColor: accent.withValues(alpha: 0.2),
            highlightColor: accent.withValues(alpha: 0.1),
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Text('[ SAVE ]',
                  style: GoogleFonts.jetBrainsMono(color: accent)),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Plan Name',
                hintText: 'e.g., PUSH DAY',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: borderColor(context)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: textSecondaryColor(context)),
                  const SizedBox(width: 8),
                  Text(
                    'Tap [+ ADD EXERCISE] below to add exercises',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 12, color: textSecondaryColor(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: borderColor(context)),
            Expanded(
              child: _exercises.isEmpty
                  ? Center(
                      child: Text(
                        '> No exercises added yet',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondaryColor(context)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _exercises.length,
                      itemBuilder: (context, exerciseIndex) {
                        final exercise = _exercises[exerciseIndex];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: surfaceColor(context),
                            border: Border.all(
                                color: borderColor(context), width: 1),
                          ),
                          child: _buildExerciseCard(
                              exercise, exerciseIndex, accent),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _addExercise,
              splashColor: accent.withValues(alpha: 0.2),
              highlightColor: accent.withValues(alpha: 0.1),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: accent, width: 1),
                ),
                child: Center(
                  child: Text(
                    '[ + ADD EXERCISE ]',
                    style: GoogleFonts.jetBrainsMono(color: accent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _savePlan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                ),
                child: Text('[ SAVE PLAN ]',
                    style:
                        GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
      _ExerciseWithSets exercise, int exerciseIndex, Color accent) {
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
                  border: Border.all(color: accent),
                ),
                child: Text(
                  '[${exerciseIndex + 1}]',
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, color: accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  exercise.name.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${exercise.sets.length} SETS',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10, color: textSecondaryColor(context)),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _exercises.removeAt(exerciseIndex);
                  });
                },
                splashColor: errorColor(context).withValues(alpha: 0.2),
                highlightColor: errorColor(context).withValues(alpha: 0.1),
                child: Text('[DEL]',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 12, color: errorColor(context))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: borderColor(context)),
          ...exercise.sets.asMap().entries.map((entry) {
            final setIndex = entry.key;
            final set = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor(context)),
                    ),
                    child: Text(
                      'SET ${(setIndex + 1).toString().padLeft(2, '0')}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: set.reps.toString(),
                            decoration: const InputDecoration(
                              labelText: 'REPS',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.jetBrainsMono(fontSize: 12),
                            onChanged: (value) {
                              final reps = int.tryParse(value) ?? 8;
                              _updateSet(
                                  exerciseIndex, setIndex, reps, set.weight);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: set.weight.toString(),
                            decoration: const InputDecoration(
                              labelText: 'KG',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.jetBrainsMono(fontSize: 12),
                            onChanged: (value) {
                              final weight = double.tryParse(value) ?? 0.0;
                              _updateSet(
                                  exerciseIndex, setIndex, set.reps, weight);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _duplicateSet(exerciseIndex, setIndex),
                    splashColor: accent.withValues(alpha: 0.2),
                    highlightColor: accent.withValues(alpha: 0.1),
                    child: Text('[COPY]',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10, color: accent)),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _deleteSet(exerciseIndex, setIndex),
                    splashColor: errorColor(context).withValues(alpha: 0.2),
                    highlightColor: errorColor(context).withValues(alpha: 0.1),
                    child: Text('[DEL]',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10, color: errorColor(context))),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              setState(() {
                final exercise = _exercises[exerciseIndex];
                final newSets = List<_ExerciseSetData>.from(exercise.sets);
                newSets.add(_ExerciseSetData(reps: 8, weight: 0));
                _exercises[exerciseIndex] = exercise.copyWith(sets: newSets);
              });
            },
            splashColor: accent.withValues(alpha: 0.2),
            highlightColor: accent.withValues(alpha: 0.1),
            child: Text(
              '[ + ADD SET ]',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
