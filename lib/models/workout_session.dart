import 'package:hive/hive.dart';
import 'exercise.dart';

part 'workout_session.g.dart';

@HiveType(typeId: 4)
class WorkoutSession extends HiveObject {
  @HiveField(0)
  final DateTime date;

  @HiveField(1)
  final String planName;

  @HiveField(2)
  final List<Exercise> exercises;

  @HiveField(3)
  final int weekNumber;

  // --- Sync / identity metadata (nullable + non-final; see WorkoutPlan) ---
  @HiveField(4)
  String? id;

  @HiveField(5)
  String? userId;

  @HiveField(6)
  String? planId;

  @HiveField(7)
  DateTime? updatedAt;

  @HiveField(8)
  DateTime? deletedAt;

  @HiveField(9)
  bool? dirty;

  WorkoutSession({
    required this.date,
    required this.planName,
    required this.exercises,
    this.weekNumber = 1,
    this.id,
    this.userId,
    this.planId,
    this.updatedAt,
    this.deletedAt,
    this.dirty,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'planName': planName,
        'planId': planId,
        'weekNumber': weekNumber,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        id: json['id'] as String?,
        date: DateTime.parse(json['date'] as String),
        planName: json['planName'] as String,
        planId: json['planId'] as String?,
        weekNumber: json['weekNumber'] as int? ?? 1,
        exercises: (json['exercises'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        deletedAt: json['deletedAt'] != null
            ? DateTime.parse(json['deletedAt'] as String)
            : null,
      );

  WorkoutSession copyWith({
    DateTime? date,
    String? planName,
    List<Exercise>? exercises,
    int? weekNumber,
    String? id,
    String? userId,
    String? planId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? dirty,
  }) {
    return WorkoutSession(
      date: date ?? this.date,
      planName: planName ?? this.planName,
      exercises: exercises ?? this.exercises,
      weekNumber: weekNumber ?? this.weekNumber,
      id: id ?? this.id,
      userId: userId ?? this.userId,
      planId: planId ?? this.planId,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      dirty: dirty ?? this.dirty,
    );
  }
}
