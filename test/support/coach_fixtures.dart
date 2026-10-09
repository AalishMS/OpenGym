import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';

const String kSplitId = 'split-1';

/// An exercise with one target per `(reps, kg)` pair.
ExerciseTemplate template(
  String name,
  List<(int, double)> sets, {
  String? note,
}) => ExerciseTemplate(
  name: name,
  sets: sets.length,
  setTargets: [
    for (final (reps, kg) in sets) SetTemplate(reps: reps, weight: kg),
  ],
  note: note,
);

WorkoutPlan plan(
  String id,
  String name,
  List<ExerciseTemplate> exercises, {
  String splitId = kSplitId,
  int? position,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) => WorkoutPlan(
  id: id,
  name: name,
  exercises: exercises,
  splitId: splitId,
  position: position,
  updatedAt: updatedAt ?? DateTime(2026, 9, 1),
  deletedAt: deletedAt,
);

/// A completed session; each exercise maps to `(reps, kg)` sets.
WorkoutSession session(
  DateTime date,
  Map<String, List<(int, double)>> exercises, {
  String splitId = kSplitId,
  bool isCompleted = true,
  DateTime? deletedAt,
  String? note,
}) => WorkoutSession(
  id: 'session-${date.toIso8601String()}-$splitId',
  date: date,
  planName: 'Plan',
  splitId: splitId,
  isCompleted: isCompleted,
  deletedAt: deletedAt,
  exercises: [
    for (final entry in exercises.entries)
      Exercise(
        name: entry.key,
        note: note,
        sets: [
          for (final (reps, kg) in entry.value)
            gym.Set(reps: reps, weight: kg, note: note),
        ],
      ),
  ],
);

CoachSnapshot snapshot(
  List<WorkoutPlan> plans, {
  List<String> splitNames = const ['Push Pull Legs'],
  List<String> customExercises = const [],
  int maxSplits = 5,
}) => CoachSnapshot(
  splitId: kSplitId,
  splitName: 'Push Pull Legs',
  plans: plans,
  splitNames: splitNames,
  maxSplits: maxSplits,
  customExercises: customExercises,
);
