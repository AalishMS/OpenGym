import 'package:hive/hive.dart';

part 'set_template.g.dart';

/// A *prescribed* set on a plan — the reps and weight you intend to lift.
///
/// Distinct from [Set], which records what was actually lifted in a session.
/// Targets never enter a [WorkoutSession]: seeding them would make
/// `PRTrackingService` declare PRs for weights that were only ever planned.
/// They surface as a dim hint next to the live value instead.
@HiveType(typeId: 5)
class SetTemplate extends HiveObject {
  @HiveField(0)
  final int reps;

  @HiveField(1)
  final double weight;

  SetTemplate({required this.reps, required this.weight});

  Map<String, dynamic> toJson() => {
        'reps': reps,
        'weight': weight,
      };

  factory SetTemplate.fromJson(Map<String, dynamic> json) => SetTemplate(
        reps: json['reps'] as int,
        weight: (json['weight'] as num).toDouble(),
      );
}
