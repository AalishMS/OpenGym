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

  Exercise({required this.name, required this.sets, this.note});

  Exercise copyWith({String? name, List<Set>? sets, String? note}) {
    return Exercise(
      name: name ?? this.name,
      sets: sets ?? this.sets,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': sets.map((s) => s.toJson()).toList(),
        'note': note,
      };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        name: json['name'] as String,
        sets: (json['sets'] as List)
            .map((s) => Set.fromJson(s as Map<String, dynamic>))
            .toList(),
        note: json['note'] as String?,
      );
}
