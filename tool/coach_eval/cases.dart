// The eval set: realistic requests, each with a fixture split and history.
// `good` says what a good answer looks like, for the manual grade. See
// docs/coach.md, "Eval".

import 'dart:convert';

import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/coach/coach_context_builder.dart';

import 'fixtures.dart';

class EvalCase {
  final String id;
  final String covers;
  final String message;

  /// Earlier turns, as (user message, model output) pairs. The output is
  /// sent compact, as `CoachProvider` sends it.
  final List<(String, Map<String, dynamic>)> history;
  final String good;
  final EvalFixture Function() fixture;

  const EvalCase({
    required this.id,
    required this.covers,
    required this.message,
    required this.good,
    required this.fixture,
    this.history = const [],
  });

  /// The context exactly as the app builds it.
  CoachContext context() {
    final data = fixture();
    return const CoachContextBuilder().build(
      split: data.splits.first,
      splits: data.splits,
      plans: data.plans,
      sessions: data.sessions,
      now: kEvalNow,
    );
  }

  List<(String, String)> encodedHistory() => [
    for (final (question, output) in history) (question, jsonEncode(output)),
  ];
}

/// The active split comes first in [splits].
class EvalFixture {
  final List<Split> splits;
  final List<WorkoutPlan> plans;
  final List<WorkoutSession> sessions;

  const EvalFixture(this.splits, this.plans, [this.sessions = const []]);
}

// --- Shared fixtures --------------------------------------------------------

List<WorkoutPlan> pplPlans() => [
  plan('push', 'Push', 0, [
    ex('Bench Press', 3, 5, 80),
    ex('Overhead Press', 3, 8, 45),
    ex('Incline Dumbbell Press', 3, 10, 26),
    ex('Chest Dips', 3, 10, 0),
    ex('Lateral Raise', 3, 15, 8),
    ex('Tricep Pushdown', 3, 12, 25),
  ]),
  plan('pull', 'Pull', 1, [
    ex('Deadlift', 1, 5, 140),
    ex('Barbell Row', 3, 8, 70),
    ex('Lat Pulldown', 3, 10, 60),
    ex('Face Pull', 3, 15, 20),
    ex('Bicep Curl', 3, 12, 14),
  ]),
  plan('legs', 'Legs', 2, [
    ex('Squat', 3, 5, 110),
    ex('Romanian Deadlift', 3, 8, 90),
    ex('Leg Press', 3, 12, 180),
    ex('Leg Curl', 3, 12, 45),
    ex('Calf Raise', 3, 15, 60),
  ]),
];

/// Push Pull Legs, trained three times a week for six weeks. Bench has
/// stalled; everything else is improving unless [lifts] says otherwise.
EvalFixture ppl({
  List<WorkoutPlan>? plans,
  Map<String, Lift> lifts = const {},
  List<Split> extraSplits = const [],
  int weeks = 6,
}) {
  final all = plans ?? pplPlans();
  final trained = all.take(3).toList();
  return EvalFixture(
    [split('Push Pull Legs'), ...extraSplits],
    all,
    logHistory(
      plans: trained,
      weeks: weeks,
      lifts: {'Bench Press': const Lift(Pattern.stalled), ...lifts},
    ),
  );
}

final List<Split> fourOtherSplits = [
  split('Strength', id: 'split-2'),
  split('Upper Lower', id: 'split-3'),
  split('Summer Cut', id: 'split-4'),
  split('Home Workouts', id: 'split-5'),
];

WorkoutPlan armsPlan() => plan('arms', 'Arms', 3, [
  ex('Bicep Curl', 3, 12, 14),
  ex('Hammer Curl', 3, 10, 16),
  ex('Preacher Curl', 3, 10, 25),
  ex('Tricep Pushdown', 3, 12, 25),
  ex('Skull Crusher', 3, 10, 30),
]);

// --- Cases ------------------------------------------------------------------

final List<EvalCase> evalCases = [
  EvalCase(
    id: 'new_from_nothing',
    covers: 'A new program from nothing (empty split, no history)',
    message:
        "I'm new to the gym. Build me a 3-day full body routine I can do "
        'Monday, Wednesday and Friday.',
    good:
        'Three added full-body plans in the active split (or a new split), '
        'library names only, kg 0 with a note on picking a starting weight, '
        'beginner-friendly volume. Mentions it can\'t schedule days but the '
        'plans can be done in any order.',
    fixture: () => EvalFixture([split('My Split')], const []),
  ),
  const EvalCase(
    id: 'new_split_upper_lower',
    covers: 'A new split built from existing history',
    message:
        'I want to try a separate 4-day upper/lower program next block. Keep '
        'my PPL as it is.',
    good:
        'target new_split with a fresh name, four plans (2 upper, 2 lower), '
        'working weights derived from the PPL history (bench ~80, squat ~110, '
        'deadlift ~140), PPL untouched.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'edit_pull_volume',
    covers: 'Edit one existing plan',
    message: 'My pull day feels too short. Add more back volume.',
    good:
        'Changes only p2: one or two added back exercises (e.g. Seated Cable '
        'Row, Pull-ups) or an extra set, existing targets kept.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'add_arms_day',
    covers: 'Add a plan',
    message: 'Add a fourth day for arms and shoulders.',
    good:
        'One added plan (ref null), 4–7 arm and shoulder exercises with '
        'weights from history where they exist; no other plan touched.',
    fixture: ppl,
  ),
  EvalCase(
    id: 'remove_day',
    covers: 'Remove a plan',
    message: 'I can only train 3 days a week now. Drop a day.',
    good:
        'removePlanRefs ["p4"] (the untrained Arms day), optionally moving one '
        'or two arm exercises into Push/Pull. Keeps the three trained plans '
        'otherwise unchanged.',
    fixture: () => ppl(plans: [...pplPlans(), armsPlan()]),
  ),
  const EvalCase(
    id: 'stalled_question',
    covers: 'A stalled lift, answered with proposal: null',
    message: 'Why has my bench stalled?',
    good:
        'proposal null. Reads the data: bench flat at 80 kg x5 for weeks while '
        'other lifts improve. Suggests a ~10% deload or rep-range change and '
        'offers to update the plan.',
    fixture: ppl,
  ),
  EvalCase(
    id: 'stalled_fix',
    covers: 'A stalled lift, fixed in the plan',
    message: 'My squat has been stuck for a month. Fix it.',
    good:
        'Changes only the squat in p3: a deload of about 10% (≈100 kg) or '
        'more reps at a lighter load, with a note on building back. No other '
        'exercise touched.',
    fixture: () => ppl(lifts: {'Squat': const Lift(Pattern.stalled)}),
  ),
  const EvalCase(
    id: 'sore_shoulder',
    covers: 'Pain or injury (health guidance), minimal change',
    message: 'Swap exercises for a sore shoulder',
    good:
        'Changes p1 only, swapping the most shoulder-provocative lifts '
        '(Overhead Press, Chest Dips) for gentler ones and/or lighter load. '
        'Pull and Legs untouched (Face Pull can stay). Suggests a '
        'professional if pain is sharp, persistent or worsening; no diagnosis.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'knee_pain',
    covers: 'Pain or injury, lower body',
    message: 'My right knee aches when I squat deep. What should I change?',
    good:
        'No diagnosis. Reduces or swaps deep knee flexion in p3 (squat lighter '
        'or to a box depth via note, more hip-dominant work) and suggests a '
        'professional for persistent pain. A proposal: null with clear advice '
        'is also acceptable.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'custom_exercises',
    covers: 'Exercises outside the library (custom)',
    message: 'Add Landmine Press to my push day and Nordic Curls to legs.',
    good:
        'Two plans changed, one added exercise each, both custom: true with '
        'their names as asked, kg 0 for Nordic Curls and a sensible landmine '
        'load or kg 0 with a note. Nothing else changes.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'abbreviations',
    covers: 'Abbreviations (DB, BB, OHP)',
    message:
        'Swap OHP for DB shoulder press, change the DB incline to BB incline, '
        'and add DB rows 3x10 to pull.',
    good:
        'Overhead Press → Dumbbell Shoulder Press, Incline Dumbbell Press → '
        'Incline Bench Press (both p1), Dumbbell Row 3x10 added to p2. Library '
        'names, custom false, reasonable starting weights.',
    fixture: ppl,
  ),
  EvalCase(
    id: 'split_limit',
    covers: 'The five-split limit',
    message: 'Create a separate powerlifting split for my meet prep.',
    good:
        'proposal null (or an active_split edit only if it says so). Explains '
        'they already have five splits and must delete one first. Must not '
        'propose new_split.',
    fixture: () => ppl(extraSplits: fourOtherSplits),
  ),
  EvalCase(
    id: 'limit_unrelated',
    covers: 'At the five-split limit, a question that has nothing to do with it',
    message: 'Why has my squat stalled?',
    good:
        'proposal null. Talks about the squat only: flat at 110 kg for weeks, '
        'a ~10% deload or rep change. Never mentions the split limit (found '
        'on the device, 2026-10-10).',
    fixture: () => ppl(
      extraSplits: fourOtherSplits,
      lifts: {'Squat': const Lift(Pattern.stalled)},
    ),
  ),
  EvalCase(
    id: 'plan_limit',
    covers: 'A split near the 10-plan limit',
    message:
        'Add three more days: a second arms day, a calves day, and a core day.',
    good:
        'Explains the 10-plan limit (9 exist, room for one) and adds at most '
        'one plan, or folds the work into existing plans. Never leaves more '
        'than 10 plans.',
    fixture: () {
      final plans = [
        plan('chest', 'Chest', 0, [
          ex('Bench Press', 4, 8, 75),
          ex('Incline Dumbbell Press', 3, 10, 26),
          ex('Cable Fly', 3, 12, 15),
        ]),
        plan('back', 'Back', 1, [
          ex('Deadlift', 3, 5, 140),
          ex('Lat Pulldown', 3, 10, 60),
          ex('Seated Cable Row', 3, 10, 55),
        ]),
        plan('shoulders', 'Shoulders', 2, [
          ex('Overhead Press', 3, 8, 45),
          ex('Lateral Raise', 4, 15, 8),
          ex('Rear Delt Fly', 3, 15, 8),
        ]),
        plan('arms', 'Arms', 3, [
          ex('Bicep Curl', 3, 12, 14),
          ex('Tricep Pushdown', 3, 12, 25),
        ]),
        plan('quads', 'Quads', 4, [
          ex('Squat', 4, 6, 100),
          ex('Leg Extension', 3, 12, 50),
        ]),
        plan('hams', 'Hamstrings & Glutes', 5, [
          ex('Romanian Deadlift', 3, 8, 90),
          ex('Leg Curl', 3, 12, 45),
          ex('Hip Thrust', 3, 10, 100),
        ]),
        plan('upper-pump', 'Upper Pump', 6, [
          ex('Machine Chest Press', 3, 12, 50),
          ex('Cable Lateral Raise', 3, 15, 5),
        ]),
        plan('lower-pump', 'Lower Pump', 7, [
          ex('Leg Press', 3, 15, 160),
          ex('Calf Raise', 3, 15, 60),
        ]),
        plan('cardio', 'Conditioning', 8, [
          ex('Mountain Climbers', 3, 30, 0),
          ex('Push-ups', 3, 15, 0),
        ]),
      ];
      return EvalFixture(
        [split('Bodybuilding')],
        plans,
        logHistory(
          plans: plans,
          weeks: 6,
          weekdays: const [
            DateTime.monday,
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
            DateTime.saturday,
          ],
        ),
      );
    },
  ),
  EvalCase(
    id: 'follow_up_plan',
    covers: 'A follow-up turn that uses history (edits a plan it proposed)',
    history: [
      (
        'Add an arms day to my split.',
        {
          'reply':
              'I added an Arms day with five exercises, using the curl and '
              'pushdown weights from your Push and Pull days.',
          'proposal': {
            'target': 'active_split',
            'newSplitName': null,
            'plans': [
              {
                'ref': null,
                'name': 'Arms',
                'exercises': [
                  for (final (name, sets, reps, kg) in const [
                    ('Bicep Curl', 3, 12, 14),
                    ('Hammer Curl', 3, 10, 16),
                    ('Preacher Curl', 3, 10, 25),
                    ('Tricep Pushdown', 3, 12, 25),
                    ('Skull Crusher', 3, 10, 30),
                  ])
                    {
                      'name': name,
                      'sets': [
                        for (var index = 0; index < sets; index++)
                          {'reps': reps, 'kg': kg},
                      ],
                      'note': null,
                      'custom': false,
                    },
                ],
              },
            ],
            'removePlanRefs': <String>[],
          },
        },
      ),
    ],
    message: "I applied it, but it's too long. Cut that day to 3 exercises.",
    good:
        'Edits p4 (Arms) only, keeping 3 of its 5 exercises with their '
        'targets, ideally one biceps, one triceps, one more. Does not add a '
        'second Arms plan.',
    fixture: () => ppl(plans: [...pplPlans(), armsPlan()]),
  ),
  const EvalCase(
    id: 'follow_up_question',
    covers: 'A follow-up that acts on advice from the previous turn',
    history: [
      (
        'Why has my bench stalled?',
        {
          'reply':
              "Your bench has sat at 80 kg for 5 reps for the last month while "
              'your other lifts kept climbing. A short deload usually helps: '
              'drop to about 72.5 kg for a couple of weeks, then build back up '
              'in 2.5 kg steps. Want me to update your Push day?',
          'proposal': null,
        },
      ),
    ],
    message: 'Yes, do that.',
    good:
        'Changes only Bench Press in p1 to ~72.5 kg (the deload it offered), '
        'with a note on building back up. Nothing else changes.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'vague',
    covers: 'A vague request',
    message: 'Make my plans better.',
    good:
        'Either asks what "better" means (proposal null) or makes a small, '
        'clearly justified change tied to the data (e.g. the stalled bench), '
        'explaining it. Not a rewrite of all three plans.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'log_and_schedule',
    covers: 'Logging a workout and moving a day (not expressible)',
    message:
        "Log today's workout: bench 3x5 at 82.5 kg. And move leg day to "
        'Saturdays.',
    good:
        'proposal null. Says it can\'t log workouts or schedule days, and '
        'points to logging the session in the app. No bench target change '
        'pretending to be a log.',
    fixture: ppl,
  ),
  const EvalCase(
    id: 'edit_history',
    covers: 'Editing logged history (not expressible)',
    message:
        'Last Monday I actually benched 85 kg, not 80. Fix my history so my '
        'PR is right.',
    good:
        'proposal null. Says it can\'t edit logged workouts and the user can '
        'edit the session in History. No plan change.',
    fixture: ppl,
  ),
  EvalCase(
    id: 'progress_weights',
    covers: 'Sensible load progression',
    message:
        "I've been hitting all my reps. Bump my weights where it makes sense.",
    good:
        'Small steps (≈2.5 kg upper, ≈5 kg lower) only on improving lifts '
        'whose plan targets lag the last top set; bench left alone or '
        'deloaded because it stalled. No large jumps.',
    fixture:
        () => ppl(
          lifts: {
            'Squat': const Lift(Pattern.improving, lastKg: 115),
            'Deadlift': const Lift(Pattern.improving, lastKg: 145),
            'Barbell Row': const Lift(Pattern.improving, lastKg: 72.5),
            'Overhead Press': const Lift(Pattern.improving, lastKg: 47.5),
          },
        ),
  ),
  const EvalCase(
    id: 'out_of_scope',
    covers: 'Out of scope',
    message: 'Write me a meal plan for cutting.',
    good:
        'Politely declines (no meal plan), proposal null, offers training '
        'help instead.',
    fixture: ppl,
  ),
];
