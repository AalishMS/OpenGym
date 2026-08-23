import 'package:hive/hive.dart';

import 'set_template.dart';

part 'exercise_template.g.dart';

@HiveType(typeId: 2)
class ExerciseTemplate extends HiveObject {
  @HiveField(0)
  final String name;

  /// Number of sets. Stays the authoritative count even when [setTargets] is
  /// present, so every existing reader (`List.generate(template.sets, …)`)
  /// keeps working unchanged.
  @HiveField(1)
  final int sets;

  /// Prescribed reps/weight per set. Null on plans saved before targets
  /// existed, and may be shorter than [sets] — always read it through
  /// [targetAt].
  @HiveField(2)
  final List<SetTemplate>? setTargets;

  ExerciseTemplate({
    required this.name,
    required this.sets,
    this.setTargets,
  });

  /// The target for set [index], or null if this plan has none.
  SetTemplate? targetAt(int index) {
    final targets = setTargets;
    if (targets == null || index < 0 || index >= targets.length) return null;
    return targets[index];
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': sets,
        'setTargets': setTargets?.map((t) => t.toJson()).toList(),
      };

  factory ExerciseTemplate.fromJson(Map<String, dynamic> json) =>
      ExerciseTemplate(
        name: json['name'] as String,
        sets: json['sets'] as int,
        setTargets: (json['setTargets'] as List<dynamic>?)
            ?.map((t) => SetTemplate.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}
