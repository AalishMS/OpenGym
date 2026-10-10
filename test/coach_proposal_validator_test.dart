import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/services/coach/proposal_validator.dart';

import 'support/coach_fixtures.dart';

final push = plan('push', 'Push', [
  template('Bench Press', [(8, 60), (8, 60), (8, 60)], note: 'Pause rep one'),
  template('Lateral Raise', [(12, 8), (12, 8)]),
], position: 0);
final pull = plan('pull', 'Pull', [
  template('Barbell Row', [(8, 60), (8, 60)]),
], position: 1);
final legs = plan('legs', 'Legs', [
  template('Squat', [(5, 100), (5, 100), (5, 100)]),
], position: 2);

Map<String, dynamic> exercise(
  String name, {
  List<Object?>? sets,
  String? note,
  bool? custom,
}) => {
  'name': name,
  'sets':
      sets ??
      [
        {'reps': 10, 'kg': 20},
        {'reps': 10, 'kg': 20},
      ],
  'note': note,
  if (custom != null) 'custom': custom,
};

Map<String, dynamic> planJson(
  String? ref,
  String name, [
  List<Map<String, dynamic>>? exercises,
]) => {
  'ref': ref,
  'name': name,
  'exercises': exercises ?? [exercise('Bicep Curl')],
};

String output({
  String reply = 'Here you go.',
  String target = 'active_split',
  String? newSplitName,
  List<Object?> plans = const [],
  List<Object?> remove = const [],
}) => jsonEncode({
  'reply': reply,
  'proposal': {
    'target': target,
    'newSplitName': newSplitName,
    'plans': plans,
    'removePlanRefs': remove,
  },
});

void main() {
  const validator = ProposalValidator();
  final current = snapshot(
    [push, pull, legs],
    splitNames: ['Push Pull Legs', 'Strength'],
    customExercises: ['Landmine Press'],
  );

  ProposalValidationResult check(String raw) =>
      validator.validate(raw, current);

  ValidatedProposal valid(String raw) {
    final result = check(raw);
    expect(result.errors, isEmpty);
    return result.reply!.proposal!;
  }

  List<String> errorsOf(String raw) {
    final result = check(raw);
    expect(result.isValid, isFalse);
    return result.errors;
  }

  group('envelope', () {
    test('a reply without a proposal is valid', () {
      final result = check(
        jsonEncode({'reply': '  Deload next week.  ', 'proposal': null}),
      );
      expect(result.isValid, isTrue);
      expect(result.reply!.reply, 'Deload next week.');
      expect(result.reply!.proposal, isNull);
    });

    test('a fenced JSON answer is accepted', () {
      final raw =
          '```json\n${jsonEncode({'reply': 'Hi', 'proposal': null})}\n```';
      expect(check(raw).isValid, isTrue);
    });

    test('text that is not JSON is one clear error', () {
      expect(errorsOf('Sure! Here is your plan.'), [
        contains('not valid JSON'),
      ]);
      expect(errorsOf('[1, 2]'), [contains('JSON object')]);
    });

    test('a missing reply and a bad proposal are both reported', () {
      final errors = errorsOf(jsonEncode({'proposal': 'none'}));
      expect(errors, hasLength(2));
      expect(errors[0], startsWith('reply:'));
      expect(errors[1], startsWith('proposal:'));
    });

    test('an unknown target is rejected', () {
      expect(errorsOf(output(target: 'everything')), [
        startsWith('proposal.target:'),
      ]);
    });
  });

  group('editing the active split', () {
    test('a ref replaces that plan and keeps its identity', () {
      final proposal = valid(
        output(
          plans: [
            planJson('p2', 'Pull day', [
              exercise('pull-ups'),
              exercise('  barbell   row '),
            ]),
          ],
        ),
      );
      expect(proposal.target, CoachTarget.activeSplit);
      expect(proposal.newSplitName, isNull);
      final edited = proposal.plans.single;
      expect(edited.existing, same(pull));
      expect(edited.name, 'Pull day');
      expect(edited.exercises.map((e) => e.name), ['Pull-ups', 'Barbell Row']);
      expect(edited.exercises.every((e) => !e.custom), isTrue);
    });

    test('a null ref adds a plan and refs can be removed', () {
      final proposal = valid(
        output(plans: [planJson(null, 'Arms')], remove: ['p3']),
      );
      expect(proposal.plans.single.isNew, isTrue);
      expect(proposal.removedPlans, [legs]);
    });

    test('an unknown ref lists the valid ones', () {
      expect(errorsOf(output(plans: [planJson('p9', 'Arms')])), [
        'proposal.plans[0].ref: "p9" is not a plan ref. '
            'Valid refs: p1, p2, p3.',
      ]);
      expect(errorsOf(output(remove: ['legs'])), [
        startsWith('proposal.removePlanRefs[0]:'),
      ]);
    });

    test('a ref cannot be edited twice, or edited and removed', () {
      final twice = errorsOf(
        output(plans: [planJson('p1', 'Push A'), planJson('p1', 'Push B')]),
      );
      expect(twice, [contains('more than one plan')]);
      final both = errorsOf(
        output(plans: [planJson('p1', 'Push A')], remove: ['p1']),
      );
      expect(both, [contains('also in removePlanRefs')]);
    });

    test('plan names stay unique in the resulting split', () {
      expect(errorsOf(output(plans: [planJson(null, 'legs')])), [
        startsWith('proposal.plans[0].name: "legs" is already a plan name'),
      ]);
      // Swapping two names is fine: neither old name survives.
      valid(output(plans: [planJson('p1', 'Pull'), planJson('p2', 'Push')]));
      // Reusing a removed plan's name is fine too.
      valid(output(plans: [planJson(null, 'Legs')], remove: ['p3']));
    });

    test('the split keeps between 1 and 10 plans', () {
      expect(errorsOf(output(remove: ['p1', 'p2', 'p3'])), [
        contains('would have 0 plans'),
      ]);
      final tooMany = [for (var i = 0; i < 8; i++) planJson(null, 'Extra $i')];
      expect(errorsOf(output(plans: tooMany)), [
        contains('would have 11 plans'),
      ]);
    });

    test('a proposal that changes nothing is rejected', () {
      final echo = planJson('p1', 'Push', [
        exercise(
          'Bench Press',
          sets: [
            for (var i = 0; i < 3; i++) {'reps': 8, 'kg': 60},
          ],
          note: 'Pause rep one',
        ),
        exercise(
          'Lateral Raise',
          sets: [
            for (var i = 0; i < 2; i++) {'reps': 12, 'kg': 8},
          ],
        ),
      ]);
      expect(errorsOf(output(plans: [echo])), [contains('changes nothing')]);
      expect(errorsOf(output()), [contains('changes nothing')]);
    });
  });

  group('exercises', () {
    test('an unknown name suggests the closest library names', () {
      final errors = errorsOf(
        output(
          plans: [
            planJson(null, 'Upper', [exercise('Incline DB Press')]),
          ],
        ),
      );
      expect(errors.single, startsWith('proposal.plans[0].exercises[0].name:'));
      expect(errors.single, contains('Closest: "Incline Dumbbell Press"'));
    });

    test('custom names need the flag unless the split already uses them', () {
      final proposal = valid(
        output(
          plans: [
            planJson(null, 'Upper', [
              exercise('landmine press'),
              exercise('Sled Push', custom: true),
              exercise('Bench Press', custom: true),
            ]),
          ],
        ),
      );
      final exercises = proposal.plans.single.exercises;
      expect(exercises.map((e) => (e.name, e.custom)), [
        ('Landmine Press', true),
        ('Sled Push', true),
        ('Bench Press', false),
      ]);
    });

    test('an exercise appears once per plan', () {
      final errors = errorsOf(
        output(
          plans: [
            planJson(null, 'Upper', [
              exercise('Bench Press'),
              exercise('bench press'),
            ]),
          ],
        ),
      );
      expect(errors, [contains('already in this plan')]);
    });

    test('a plan needs 1 to 15 exercises', () {
      expect(errorsOf(output(plans: [planJson(null, 'Empty', [])])), [
        contains('1 to 15 exercises, not 0'),
      ]);
    });

    test('sets are bounded and weights round to a quarter kilo', () {
      final proposal = valid(
        output(
          plans: [
            planJson(null, 'Upper', [
              exercise(
                'Bench Press',
                sets: [
                  {'reps': 8, 'kg': 61.3},
                  {'reps': 8.0},
                ],
              ),
            ]),
          ],
        ),
      );
      expect(proposal.plans.single.exercises.single.sets, const [
        CoachSet(reps: 8, kg: 61.25),
        CoachSet(reps: 8, kg: 0),
      ]);

      final errors = errorsOf(
        output(
          plans: [
            planJson(null, 'Upper', [
              exercise(
                'Bench Press',
                sets: [
                  {'reps': 0, 'kg': 60},
                  {'reps': 8.5, 'kg': 60},
                  {'reps': 8, 'kg': -5},
                  [8, 60],
                ],
              ),
              exercise(
                'Squat',
                sets: [
                  for (var i = 0; i < 11; i++) {'reps': 5, 'kg': 100},
                ],
              ),
            ]),
          ],
        ),
      );
      expect(errors, [
        startsWith('proposal.plans[0].exercises[0].sets[0].reps:'),
        startsWith('proposal.plans[0].exercises[0].sets[1].reps:'),
        startsWith('proposal.plans[0].exercises[0].sets[2].kg:'),
        startsWith('proposal.plans[0].exercises[0].sets[3]:'),
        startsWith('proposal.plans[0].exercises[1].sets:'),
      ]);
    });

    test('notes are trimmed, blank becomes null, and length is capped', () {
      final proposal = valid(
        output(
          plans: [
            planJson(null, 'Upper', [
              exercise('Bench Press', note: '  Slow eccentric  '),
              exercise('Squat', note: '   '),
            ]),
          ],
        ),
      );
      expect(proposal.plans.single.exercises.map((e) => e.note), [
        'Slow eccentric',
        null,
      ]);
      expect(
        errorsOf(
          output(
            plans: [
              planJson(null, 'Upper', [exercise('Squat', note: 'x' * 201)]),
            ],
          ),
        ),
        [contains('at most 200 characters')],
      );
    });
  });

  group('new split', () {
    test('creates plans under a new name', () {
      final proposal = valid(
        output(
          target: 'new_split',
          newSplitName: ' Upper Lower ',
          plans: [planJson(null, 'Upper'), planJson(null, 'Lower')],
        ),
      );
      expect(proposal.target, CoachTarget.newSplit);
      expect(proposal.newSplitName, 'Upper Lower');
      expect(proposal.plans.every((plan) => plan.isNew), isTrue);
      expect(proposal.removedPlans, isEmpty);
    });

    test('plans in a new split may reuse active split plan names', () {
      valid(
        output(
          target: 'new_split',
          newSplitName: 'Five day',
          plans: [planJson(null, 'Push')],
        ),
      );
    });

    test('the name must be present, short, and unused', () {
      List<String> named(String? name) => errorsOf(
        output(
          target: 'new_split',
          newSplitName: name,
          plans: [planJson(null, 'Upper')],
        ),
      );
      expect(named(null), [contains('required')]);
      expect(named('strength'), [contains('already exists')]);
      expect(named('A very long split name indeed'), [
        contains('longer than 24'),
      ]);
    });

    test('refs, removals, and too many plans are rejected', () {
      final errors = errorsOf(
        output(
          target: 'new_split',
          newSplitName: 'Upper Lower',
          plans: [planJson('p1', 'Upper')],
          remove: ['p2'],
        ),
      );
      expect(errors, [
        contains('ref: must be null'),
        contains('removePlanRefs: must be empty'),
      ]);
      expect(
        errorsOf(
          output(
            target: 'new_split',
            newSplitName: 'Upper Lower',
            plans: [for (var i = 0; i < 8; i++) planJson(null, 'Day $i')],
          ),
        ),
        [contains('1 to 7 plans, not 8')],
      );
    });

    test('is refused at the split limit', () {
      final full = snapshot([push], splitNames: ['A', 'B', 'C', 'D', 'E']);
      final result = validator.validate(
        output(
          target: 'new_split',
          newSplitName: 'F',
          plans: [planJson(null, 'Upper')],
        ),
        full,
      );
      expect(result.errors, [contains('already has 5 splits')]);
      // Steering the retry to active_split made it rewrite the whole split.
      expect(result.errors.single, contains('"proposal": null'));
    });
  });

  test('every problem is reported at once', () {
    final errors = errorsOf(
      output(
        plans: [
          planJson('p7', '', [
            exercise('Moon Press'),
            exercise('Squat', sets: []),
          ]),
        ],
        remove: ['p8'],
      ),
    );
    expect(errors, hasLength(5));
  });

  group('closestExercises', () {
    test('expands abbreviations and plurals', () {
      expect(ProposalValidator.closestExercises('OHP').first, 'Overhead Press');
      expect(
        ProposalValidator.closestExercises('RDL').first,
        'Romanian Deadlift',
      );
      expect(
        ProposalValidator.closestExercises('Lateral Raises').first,
        'Lateral Raise',
      );
    });

    test('returns nothing when no word is shared', () {
      expect(ProposalValidator.closestExercises('Zumba'), isEmpty);
    });
  });
}
