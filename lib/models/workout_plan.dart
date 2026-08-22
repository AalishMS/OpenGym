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

  // --- Sync / identity metadata ---
  // All nullable so pre-existing on-disk records (written before these fields
  // existed) still deserialize. Non-final so the sync engine can flip
  // dirty/updatedAt/deletedAt in place and persist with box.put(id, obj).
  // NOTE: field index 3 is intentionally unused (harmless gap).
  @HiveField(4)
  String? id;

  @HiveField(5)
  String? userId;

  @HiveField(6)
  DateTime? updatedAt;

  @HiveField(7)
  DateTime? deletedAt;

  @HiveField(8)
  bool? dirty;

  WorkoutPlan({
    required this.name,
    required this.exercises,
    this.planColor,
    this.id,
    this.userId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
  });

  WorkoutPlan copyWith({
    String? name,
    List<ExerciseTemplate>? exercises,
    int? planColor,
    String? id,
    String? userId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? dirty,
  }) =>
      WorkoutPlan(
        name: name ?? this.name,
        exercises: exercises ?? this.exercises,
        planColor: planColor ?? this.planColor,
        id: id ?? this.id,
        userId: userId ?? this.userId,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        dirty: dirty ?? this.dirty,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'planColor': planColor,
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        id: json['id'] as String?,
        name: json['name'] as String,
        exercises: (json['exercises'] as List)
            .map((e) => ExerciseTemplate.fromJson(e as Map<String, dynamic>))
            .toList(),
        planColor: json['planColor'] as int?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        deletedAt: json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
      );
}
