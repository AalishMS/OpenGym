import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/services/coach/proposal_diff.dart';

import 'support/coach_fixtures.dart';

CoachExercise coachExercise(
  String name,
  List<(int, double)> sets, {
  String? note,
  bool custom = false,
}) => CoachExercise(
  name: name,
  sets: [for (final (reps, kg) in sets) CoachSet(reps: reps, kg: kg)],
  note: note,
  custom: custom,
);

/// The plan's exercises as the Coach would echo them back.
List<CoachExercise> echo(WorkoutPlan plan) => [
  for (final exercise in plan.exercises)
    CoachExercise(
      name: exercise.name,
      sets: coachSetsOf(exercise),
      note: coachNote(exercise.note),
    ),
];

ProposalDiff diff(
  List<CoachPlan> plans, {
  List<WorkoutPlan> removed = const [],
  List<WorkoutPlan>? snapshotPlans,
}) => ProposalDiff.compute(
  ValidatedProposal(
    target: CoachTarget.activeSplit,
    newSplitName: null,
    plans: plans,
    removedPlans: removed,
    snapshot: snapshot(
      snapshotPlans ??
          [
            for (final p in plans)
              if (p.existing != null) p.existing!,
          ],
    ),
  ),
);

void main() {
  final push = plan('push', 'Push', [
    template('Bench Press', [(8, 60), (8, 60), (8, 60)]),
    template('Overhead Press', [(8, 40), (8, 40)]),
    template('Lateral Raise', [(12, 8), (12, 8)], note: 'Slow'),
    template('Tricep Pushdown', [(12, 25), (12, 25)]),
  ]);

  test('an echoed plan is unchanged', () {
    final result = diff([
      CoachPlan(existing: push, name: 'Push', exercises: echo(push)),
    ]);
    final plan = result.plans.single;
    expect(plan.kind, DiffKind.unchanged);
    expect(plan.renamed, isFalse);
    expect(plan.exercises.every((e) => e.kind == DiffKind.unchanged), isTrue);
    expect(plan.exercises.any((e) => e.moved), isFalse);
    expect(result.hasChanges, isFalse);
  });

  test('targets padded by the plan editor compare equal', () {
    final legacy = plan('legacy', 'Legs', [
      ExerciseTemplate(name: 'Squat', sets: 2),
    ]);
    final result = diff([
      CoachPlan(
        existing: legacy,
        name: 'Legs',
        exercises: [
          coachExercise('Squat', [(8, 0), (8, 0)]),
        ],
      ),
    ]);
    expect(result.plans.single.kind, DiffKind.unchanged);
  });

  test('edits report sets, notes, additions, removals, and a rename', () {
    final result = diff([
      CoachPlan(
        existing: push,
        name: 'Push A',
        exercises: [
          coachExercise('bench press', [(5, 70), (5, 70), (5, 70)]),
          coachExercise('Overhead Press', [(8, 40), (8, 40)]),
          coachExercise('Lateral Raise', [(12, 8), (12, 8)]),
          coachExercise('Sled Push', [(1, 100)], custom: true),
        ],
      ),
    ]);
    final plan = result.plans.single;
    expect(plan.kind, DiffKind.changed);
    expect(plan.name, 'Push A');
    expect(plan.previousName, 'Push');
    expect(plan.existing, same(push));

    final byName = {for (final e in plan.exercises) e.name: e};
    expect(plan.exercises.map((e) => e.name), [
      'bench press',
      'Overhead Press',
      'Lateral Raise',
      'Sled Push',
      'Tricep Pushdown',
    ]);

    final bench = byName['bench press']!;
    expect(bench.kind, DiffKind.changed);
    expect(bench.setsChanged, isTrue);
    expect(bench.before.first, const CoachSet(reps: 8, kg: 60));
    expect(bench.after.first, const CoachSet(reps: 5, kg: 70));

    expect(byName['Overhead Press']!.kind, DiffKind.unchanged);

    final raise = byName['Lateral Raise']!;
    expect(raise.kind, DiffKind.changed);
    expect(raise.setsChanged, isFalse);
    expect(raise.noteChanged, isTrue);
    expect(raise.noteBefore, 'Slow');
    expect(raise.noteAfter, isNull);

    final sled = byName['Sled Push']!;
    expect(sled.kind, DiffKind.added);
    expect(sled.custom, isTrue);
    expect(sled.before, isEmpty);

    final pushdown = byName['Tricep Pushdown']!;
    expect(pushdown.kind, DiffKind.removed);
    expect(pushdown.after, isEmpty);
    expect(pushdown.before, hasLength(2));

    expect(plan.exercises.any((e) => e.moved), isFalse);
  });

  test('moving one exercise marks only that exercise', () {
    final reordered = echo(push);
    reordered.insert(0, reordered.removeLast());
    final plan =
        diff([
          CoachPlan(existing: push, name: 'Push', exercises: reordered),
        ]).plans.single;
    expect(plan.kind, DiffKind.changed);
    expect(
      [
        for (final e in plan.exercises)
          if (e.moved) e.name,
      ],
      ['Tricep Pushdown'],
    );
    expect(plan.exercises.every((e) => e.kind == DiffKind.unchanged), isTrue);
  });

  test('a repeated exercise pairs occurrence by occurrence', () {
    final repeated = plan('rep', 'Squat day', [
      template('Squat', [(5, 100)]),
      template('Leg Curl', [(10, 40)]),
      template('Squat', [(10, 70)]),
    ]);
    final squatDay =
        diff([
          CoachPlan(
            existing: repeated,
            name: 'Squat day',
            exercises: [
              coachExercise('Squat', [(5, 100)]),
              coachExercise('Squat', [(10, 70)]),
            ],
          ),
        ]).plans.single;
    expect(squatDay.exercises.map((e) => (e.name, e.kind)), [
      ('Squat', DiffKind.unchanged),
      ('Squat', DiffKind.unchanged),
      ('Leg Curl', DiffKind.removed),
    ]);
  });

  test('added and removed plans list every exercise', () {
    final legs = plan('legs', 'Legs', [
      template('Squat', [(5, 100)]),
      template('Leg Curl', [(10, 40)]),
    ]);
    final result = diff(
      [
        CoachPlan(
          existing: null,
          name: 'Arms',
          exercises: [
            coachExercise('Bicep Curl', [(10, 12)], note: 'Strict'),
          ],
        ),
        CoachPlan(existing: push, name: 'Push', exercises: echo(push)),
      ],
      removed: [legs],
      snapshotPlans: [push, legs],
    );

    expect(result.plans.map((p) => (p.name, p.kind)), [
      ('Arms', DiffKind.added),
      ('Push', DiffKind.unchanged),
      ('Legs', DiffKind.removed),
    ]);
    final arms = result.plans.first;
    expect(arms.existing, isNull);
    expect(arms.exercises.single.kind, DiffKind.added);
    expect(arms.exercises.single.noteAfter, 'Strict');
    expect(
      result.plans.last.exercises.map((e) => e.kind),
      everyElement(DiffKind.removed),
    );

    expect(result.count(DiffKind.added), 1);
    expect(result.count(DiffKind.removed), 1);
    expect(result.count(DiffKind.changed), 0);
    expect(result.hasChanges, isTrue);
  });
}
