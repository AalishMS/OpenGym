import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/services/coach/proposal_diff.dart';
import 'package:gymapp/services/coach/proposal_selection.dart';

import 'support/coach_fixtures.dart';

CoachExercise coachExercise(String name, List<(int, double)> sets) =>
    CoachExercise(
      name: name,
      sets: [for (final (reps, kg) in sets) CoachSet(reps: reps, kg: kg)],
    );

List<CoachExercise> echo(WorkoutPlan plan) => [
  for (final exercise in plan.exercises)
    CoachExercise(
      name: exercise.name,
      sets: coachSetsOf(exercise),
      note: coachNote(exercise.note),
    ),
];

ProposalSelection select(
  List<CoachPlan> plans, {
  required List<WorkoutPlan> snapshotPlans,
  List<WorkoutPlan> removed = const [],
}) => ProposalSelection(
  ProposalDiff.compute(
    ValidatedProposal(
      target: CoachTarget.activeSplit,
      newSplitName: null,
      plans: plans,
      removedPlans: removed,
      snapshot: snapshot(snapshotPlans),
    ),
  ),
);

/// The change touching [name] in the plan called [planName].
ReviewChange change(
  ProposalSelection selection,
  String planName, [
  String? name,
  ReviewChangeKind kind = ReviewChangeKind.exercise,
]) => selection.changes.firstWhere(
  (change) =>
      change.plan.name == planName &&
      change.kind == kind &&
      (name == null || change.exercise?.name == name),
);

List<String> names(CoachPlan plan) => [
  for (final exercise in plan.exercises) exercise.name,
];

CoachPlan written(ValidatedProposal proposal, String name) =>
    proposal.plans.firstWhere((plan) => plan.name == name);

void main() {
  final push = plan('push', 'Push', [
    template('Bench Press', [(8, 60), (8, 60), (8, 60)]),
    template('Overhead Press', [(8, 40), (8, 40)]),
    template('Lateral Raise', [(12, 8), (12, 8)], note: 'Slow'),
    template('Tricep Pushdown', [(12, 25), (12, 25)]),
  ], position: 0);
  final legs = plan('legs', 'Legs', [
    template('Squat', [(5, 100)]),
  ], position: 1);

  /// Renames Push, adds one exercise, changes one, removes two, adds an Arms
  /// plan, and removes Legs.
  ProposalSelection mixed() => select(
    [
      CoachPlan(
        existing: push,
        name: 'Push A',
        exercises: [
          coachExercise('Incline Dumbbell Press', [(10, 22.5), (10, 22.5)]),
          coachExercise('Overhead Press', [(8, 40), (8, 40), (8, 40)]),
          echo(push)[2],
        ],
      ),
      CoachPlan(
        existing: null,
        name: 'Arms',
        exercises: [
          coachExercise('Barbell Curl', [(10, 30)]),
          coachExercise('Skull Crusher', [(10, 25)]),
        ],
      ),
    ],
    snapshotPlans: [push, legs],
    removed: [legs],
  );

  group('every change starts kept', () {
    test('one change per edit, rename, and removed plan', () {
      final selection = mixed();
      expect(selection.changes, hasLength(8));
      expect(selection.keepsAll, isTrue);
      expect(selection.keptCount, 8);
      expect(selection.problems, isEmpty);
      expect(selection.changesIn(selection.plans.first).map((c) => c.kind), [
        ReviewChangeKind.rename,
        ...List.filled(4, ReviewChangeKind.exercise),
      ]);
    });

    test('and resolves to the whole proposal', () {
      final resolved = mixed().resolve();
      expect(resolved.plans.map((plan) => plan.name), ['Push A', 'Arms']);
      expect(resolved.removedPlans, [legs]);
      expect(names(written(resolved, 'Push A')), [
        'Incline Dumbbell Press',
        'Overhead Press',
        'Lateral Raise',
      ]);
    });
  });

  test('a skipped change keeps the stored exercise exactly', () {
    final legacy = plan('legacy', 'Pull', [
      ExerciseTemplate(name: 'Face Pull', sets: 2, note: '  High elbows '),
      template('Barbell Row', [(10, 50)]),
    ]);
    final selection = select(
      [
        CoachPlan(
          existing: legacy,
          name: 'Pull',
          exercises: [
            echo(legacy).first,
            coachExercise('Barbell Row', [(8, 55)]),
          ],
        ),
      ],
      snapshotPlans: [legacy],
    );
    expect(selection.changes, hasLength(1));
    selection.setKept(change(selection, 'Pull', 'Barbell Row'), false);

    // Nothing kept in the plan, so it isn't written at all.
    expect(selection.resolve().plans, isEmpty);

    // Kept, the unchanged exercise is still copied as stored: no padded
    // targets, note untrimmed.
    selection.setAllKept(true);
    final templates = [
      for (final exercise in selection.resolve().plans.single.exercises)
        exercise.toTemplate(),
    ];
    expect(templates.first.setTargets, isNull);
    expect(templates.first.note, '  High elbows ');
    expect(templates.last.setTargets!.single.weight, 55);
  });

  test('a skipped set change writes the stored sets', () {
    final selection = mixed();
    selection.setKept(change(selection, 'Push A', 'Overhead Press'), false);
    final press = written(selection.resolve(), 'Push A').exercises[1];
    expect(press.toTemplate().sets, 2);
    expect(press.toTemplate().setTargets!.first.weight, 40);
  });

  test('a skipped removal goes back where it was', () {
    final selection = mixed();
    selection.setKept(change(selection, 'Push A', 'Bench Press'), false);
    selection.setKept(change(selection, 'Push A', 'Tricep Pushdown'), false);
    expect(names(written(selection.resolve(), 'Push A')), [
      'Bench Press',
      'Incline Dumbbell Press',
      'Overhead Press',
      'Lateral Raise',
      'Tricep Pushdown',
    ]);
  });

  test('a skipped addition is left out', () {
    final selection = mixed();
    selection.setKept(
      change(selection, 'Push A', 'Incline Dumbbell Press'),
      false,
    );
    expect(names(written(selection.resolve(), 'Push A')), [
      'Overhead Press',
      'Lateral Raise',
    ]);
  });

  test('a skipped rename keeps the stored name', () {
    final selection = mixed();
    selection.setKept(
      change(selection, 'Push A', null, ReviewChangeKind.rename),
      false,
    );
    final resolved = selection.resolve();
    expect(resolved.plans.first.name, 'Push');
    expect(resolved.plans.first.existing, push);
  });

  test('a new plan keeps only its kept exercises, or is left out', () {
    final selection = mixed();
    selection.setKept(change(selection, 'Arms', 'Skull Crusher'), false);
    expect(names(written(selection.resolve(), 'Arms')), ['Barbell Curl']);

    final arms = selection.plans.elementAt(1);
    expect(selection.planState(arms), isNull);
    selection.setPlanKept(arms, false);
    expect(selection.planState(arms), isFalse);
    expect(selection.resolve().plans.map((plan) => plan.name), ['Push A']);
  });

  test('a skipped plan removal keeps the plan', () {
    final selection = mixed();
    selection.setKept(
      change(selection, 'Legs', null, ReviewChangeKind.removePlan),
      false,
    );
    expect(selection.resolve().removedPlans, isEmpty);
  });

  group('order', () {
    final day = plan('day', 'Full body', [
      template('Squat', [(5, 100)]),
      template('Bench Press', [(5, 80)]),
      template('Barbell Row', [(8, 60)]),
    ]);
    // Row moves to the top and a curl follows it.
    ProposalSelection reordered() => select(
      [
        CoachPlan(
          existing: day,
          name: 'Full body',
          exercises: [
            echo(day)[2],
            coachExercise('Barbell Curl', [(10, 30)]),
            echo(day)[0],
            echo(day)[1],
          ],
        ),
      ],
      snapshotPlans: [day],
    );

    test('a move is its own change', () {
      final selection = reordered();
      expect(selection.changes.map((c) => c.kind), [
        ReviewChangeKind.exercise,
        ReviewChangeKind.reorder,
      ]);
      expect(names(selection.resolve().plans.single), [
        'Barbell Row',
        'Barbell Curl',
        'Squat',
        'Bench Press',
      ]);
    });

    test('skipped, the stored order stays and additions follow their '
        'neighbour', () {
      final selection = reordered();
      selection.setKept(
        change(selection, 'Full body', null, ReviewChangeKind.reorder),
        false,
      );
      expect(names(selection.resolve().plans.single), [
        'Squat',
        'Bench Press',
        'Barbell Row',
        'Barbell Curl',
      ]);
    });
  });

  group('problems', () {
    test('a plan left with no exercises', () {
      final solo = plan('solo', 'Push', [
        template('Bench Press', [(8, 60)]),
      ]);
      final selection = select(
        [
          CoachPlan(
            existing: solo,
            name: 'Push',
            exercises: [
              coachExercise('Push-up', [(15, 0)]),
            ],
          ),
        ],
        snapshotPlans: [solo],
      );
      selection.setKept(change(selection, 'Push', 'Push-up'), false);
      expect(selection.problems, [
        'Push would have no exercises. Keep at least one.',
      ]);
    });

    test('a split left with no plans', () {
      final selection = select(
        [
          CoachPlan(
            existing: null,
            name: 'Arms',
            exercises: [
              coachExercise('Barbell Curl', [(10, 30)]),
            ],
          ),
        ],
        snapshotPlans: [legs],
        removed: [legs],
      );
      selection.setKept(change(selection, 'Arms', 'Barbell Curl'), false);
      expect(selection.problems, [
        'The split would have no plans. Keep at least one.',
      ]);
    });

    test('a split over the plan limit', () {
      final full = [
        for (var index = 0; index < 10; index++)
          plan('p$index', 'Day $index', [
            template('Squat', [(5, 100)]),
          ]),
      ];
      final selection = select(
        [
          CoachPlan(
            existing: null,
            name: 'Arms',
            exercises: [
              coachExercise('Barbell Curl', [(10, 30)]),
            ],
          ),
        ],
        snapshotPlans: full,
        removed: [full.first],
      );
      expect(selection.problems, isEmpty);
      selection.setKept(
        change(selection, 'Day 0', null, ReviewChangeKind.removePlan),
        false,
      );
      expect(selection.problems.single, startsWith('The split would have 11'));
    });

    test('two plans with one name', () {
      final pull = plan('pull', 'Pull', [
        template('Barbell Row', [(10, 50)]),
      ]);
      final selection = select(
        [
          CoachPlan(existing: pull, name: 'Back', exercises: echo(pull)),
          CoachPlan(
            existing: null,
            name: 'Pull',
            exercises: [
              coachExercise('Pull-up', [(8, 0)]),
            ],
          ),
        ],
        snapshotPlans: [pull],
      );
      expect(selection.problems, isEmpty);
      selection.setKept(
        change(selection, 'Back', null, ReviewChangeKind.rename),
        false,
      );
      expect(selection.problems, [
        'Two plans would be named Pull. Keep or skip both.',
      ]);
    });

    test('nothing kept is not a problem, just nothing to apply', () {
      final selection = mixed()..setAllKept(false);
      expect(selection.keptCount, 0);
      expect(selection.problems, isEmpty);
    });
  });

  test('a new split keeps only the plans with kept exercises', () {
    final selection = ProposalSelection(
      ProposalDiff.compute(
        ValidatedProposal(
          target: CoachTarget.newSplit,
          newSplitName: 'Upper lower',
          plans: [
            CoachPlan(
              existing: null,
              name: 'Upper',
              exercises: [
                coachExercise('Bench Press', [(8, 60)]),
              ],
            ),
            CoachPlan(
              existing: null,
              name: 'Lower',
              exercises: [
                coachExercise('Squat', [(5, 100)]),
              ],
            ),
          ],
          removedPlans: const [],
          snapshot: snapshot([push]),
        ),
      ),
    );
    selection.setPlanKept(selection.plans.first, false);
    final resolved = selection.resolve();
    expect(resolved.target, CoachTarget.newSplit);
    expect(resolved.newSplitName, 'Upper lower');
    expect(resolved.plans.map((plan) => plan.name), ['Lower']);
  });
}
