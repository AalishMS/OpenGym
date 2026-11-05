import 'package:hive/hive.dart';

import 'set.dart';

part 'exercise.g.dart';

@HiveType(typeId: 1)
class Exercise extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final List<Set> sets;

  @HiveField(2)
  final String? note;

  /// Null only on legacy entries awaiting catalog migration.
  @HiveField(3)
  final String? exerciseId;

  Exercise({
    required this.name,
    required this.sets,
    this.note,
    this.exerciseId,
  });

  Exercise copyWith({
    String? name,
    String? exerciseId,
    List<Set>? sets,
    String? note,
  }) => Exercise(
    name: name ?? this.name,
    exerciseId: exerciseId ?? this.exerciseId,
    sets: sets ?? this.sets,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'exerciseId': exerciseId,
    'sets': sets.map((s) => s.toJson()).toList(),
    'note': note,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    name: json['name'] as String,
    exerciseId: json['exerciseId'] as String?,
    sets:
        (json['sets'] as List)
            .map((s) => Set.fromJson(s as Map<String, dynamic>))
            .toList(),
    note: json['note'] as String?,
  );
}
