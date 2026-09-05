import 'package:hive/hive.dart';

part 'set.g.dart';

@HiveType(typeId: 0)
class Set extends HiveObject {
  @HiveField(0)
  final int reps;

  @HiveField(1)
  final double weight;

  @HiveField(2)
  final int? rpe;

  @HiveField(3)
  final String? note;

  /// Whether the athlete confirmed this prescribed or entered set as done.
  ///
  /// Existing records predate this field, so they remain completed by default.
  @HiveField(4, defaultValue: true)
  final bool completed;

  Set({
    required this.reps,
    required this.weight,
    this.rpe,
    this.note,
    this.completed = true,
  });

  Set copyWith({
    int? reps,
    double? weight,
    int? rpe,
    String? note,
    bool? completed,
  }) {
    return Set(
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
      rpe: rpe ?? this.rpe,
      note: note ?? this.note,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'reps': reps,
    'weight': weight,
    'rpe': rpe,
    'note': note,
    'completed': completed,
  };

  factory Set.fromJson(Map<String, dynamic> json) => Set(
    reps: json['reps'] as int,
    weight: (json['weight'] as num).toDouble(),
    rpe: json['rpe'] as int?,
    note: json['note'] as String?,
    completed: json['completed'] as bool? ?? true,
  );
}
