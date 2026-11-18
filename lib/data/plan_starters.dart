import 'workout_presets.dart';

/// One common workout a new plan can start from instead of a blank list.
class PlanStarter {
  /// The chip label, and the plan's name when the name is still blank.
  final String name;
  final List<WorkoutPresetExercise> exercises;

  const PlanStarter({required this.name, required this.exercises});
}

/// Which preset day each starter borrows. Starters are single workouts taken
/// from the bundled hypertrophy presets, so they stay in step with the preset
/// research instead of keeping a second list of exercises and targets.
///
/// Labels avoid the bare muscle-group names (*Legs*, *Back*) the exercise
/// picker uses, so the two never read as the same control.
const List<(String, String, String)> _starterSources = [
  ('Push day', 'HYP-PPL-6', 'Push A'),
  ('Pull day', 'HYP-PPL-6', 'Pull A'),
  ('Leg day', 'HYP-PPL-6', 'Legs A'),
  ('Upper body', 'HYP-UL-4', 'Upper A'),
  ('Lower body', 'HYP-UL-4', 'Lower A'),
  ('Full body', 'HYP-FB-3', 'Full body A'),
];

/// The starters offered by an empty plan editor, in display order. A source
/// that no longer resolves is left out rather than shown empty.
final List<PlanStarter> planStarters = [
  for (final (name, presetId, planName) in _starterSources)
    if (_presetPlan(presetId, planName) case final plan?)
      PlanStarter(name: name, exercises: plan.exercises),
];

WorkoutPresetPlan? _presetPlan(String presetId, String planName) {
  for (final preset in workoutPresets) {
    if (preset.id != presetId) continue;
    for (final plan in preset.plans) {
      if (plan.name == planName) return plan;
    }
  }
  return null;
}
