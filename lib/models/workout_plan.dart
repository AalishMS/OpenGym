import 'package:hive/hive.dart';
import 'exercise_template.dart';

part 'workout_plan.g.dart';

@HiveType(typeId: 3)
class WorkoutPlan extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final List<ExerciseTemplate> exercises;

  WorkoutPlan({required this.name, required this.exercises});

  Map<String, dynamic> toJson() => {
        'name': name,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        name: json['name'] as String,
        exercises: (json['exercises'] as List)
            .map(
                (e) => ExerciseTemplate.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
