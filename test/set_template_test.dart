import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/services/hive_service.dart';

import 'support/hive_test_harness.dart';

void main() {
  test('plan JSON preserves optional RPE and reads older targets', () {
    final plan = WorkoutPlan(
      name: 'Strength',
      exercises: [
        ExerciseTemplate(
          name: 'Squat',
          sets: 2,
          setTargets: [
            SetTemplate(reps: 5, weight: 100.5, rpe: 8),
            SetTemplate(reps: 6, weight: 95),
          ],
        ),
      ],
    );
    final restored = WorkoutPlan.fromJson(
      jsonDecode(jsonEncode(plan.toJson())),
    );
    final targets = restored.exercises.single.setTargets!;
    expect(targets.map((set) => set.rpe), [8, null]);
    expect(SetTemplate.fromJson({'reps': 5, 'weight': 100}).rpe, isNull);
    final copied = CoachExercise.stored(plan.exercises.single).toTemplate();
    expect(copied.setTargets!.first.rpe, 8);
    expect(identical(copied.setTargets!.first, targets.first), isFalse);
  });

  test('Hive reads pre-RPE sets and preserves RPE after reopening', () async {
    final harness = HiveTestHarness();
    await harness.open();
    addTearDown(harness.close);
    Hive.registerAdapter<SetTemplate>(
      _LegacySetTemplateAdapter(),
      override: true,
    );
    var box = Hive.box<WorkoutPlan>(HiveService.plansBox);
    await box.put(
      'legacy',
      WorkoutPlan(
        name: 'Legacy',
        exercises: [
          ExerciseTemplate(
            name: 'Row',
            sets: 1,
            setTargets: [SetTemplate(reps: 8, weight: 60)],
          ),
        ],
      ),
    );
    await box.close();
    Hive.registerAdapter<SetTemplate>(SetTemplateAdapter(), override: true);
    box = await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    expect(box.get('legacy')!.exercises.single.targetAt(0)!.rpe, isNull);
    await box.put(
      'rpe',
      WorkoutPlan(
        name: 'Effort',
        exercises: [
          ExerciseTemplate(
            name: 'Squat',
            sets: 1,
            setTargets: [SetTemplate(reps: 5, weight: 90, rpe: 9)],
          ),
        ],
      ),
    );
    await box.close();
    box = await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    expect(box.get('rpe')!.exercises.single.targetAt(0)!.rpe, 9);
  });
}

/// The previous on-disk field layout, before optional RPE was added.
class _LegacySetTemplateAdapter extends TypeAdapter<SetTemplate> {
  @override
  int get typeId => 5;

  @override
  SetTemplate read(BinaryReader reader) => SetTemplateAdapter().read(reader);

  @override
  void write(BinaryWriter writer, SetTemplate obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.reps)
      ..writeByte(1)
      ..write(obj.weight);
  }
}
