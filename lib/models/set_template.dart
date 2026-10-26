import 'package:hive/hive.dart';

part 'set_template.g.dart';

/// A prescribed set on a plan, used to initialize the first workout week.
/// Later weeks copy the previous session rather than the prescription.
@HiveType(typeId: 5)
class SetTemplate extends HiveObject {
  @HiveField(0)
  final int reps;

  @HiveField(1)
  final double weight;

  /// Optional effort target. Null for older plans or unprescribed effort.
  @HiveField(2)
  final int? rpe;

  SetTemplate({required this.reps, required this.weight, this.rpe});

  Map<String, dynamic> toJson() => {'reps': reps, 'weight': weight, 'rpe': rpe};

  factory SetTemplate.fromJson(Map<String, dynamic> json) => SetTemplate(
    reps: json['reps'] as int,
    weight: (json['weight'] as num).toDouble(),
    rpe: json['rpe'] as int?,
  );
}
