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

  WorkoutSession({
    required this.date,
    required this.planName,
    required this.exercises,
    this.weekNumber = 1,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'planName': planName,
        'weekNumber': weekNumber,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) =>
      WorkoutSession(
        date: DateTime.parse(json['date'] as String),
        planName: json['planName'] as String,
        weekNumber: json['weekNumber'] as int? ?? 1,
        exercises: (json['exercises'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  WorkoutSession copyWith({
    DateTime? date,
    String? planName,
    List<Exercise>? exercises,
    int? weekNumber,
  }) {
    return WorkoutSession(
      date: date ?? this.date,
      planName: planName ?? this.planName,
      exercises: exercises ?? this.exercises,
      weekNumber: weekNumber ?? this.weekNumber,
    );
  }
}
