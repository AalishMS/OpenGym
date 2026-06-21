import 'package:hive/hive.dart';
import 'exercise_template.dart';

part 'workout_plan.g.dart';

@HiveType(typeId: 3)
class WorkoutPlan extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final List<ExerciseTemplate> exercises;

  @HiveField(2)
  final int? planColor;

  WorkoutPlan({required this.name, required this.exercises, this.planColor});

  Map<String, dynamic> toJson() => {
        'name': name,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'planColor': planColor,
      };

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        name: json['name'] as String,
        exercises: (json['exercises'] as List)
            .map(
                (e) => ExerciseTemplate.fromJson(e as Map<String, dynamic>))
            .toList(),
        planColor: json['planColor'] as int?,
      );
}
