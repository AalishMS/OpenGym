import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/data/plan_colors.dart';
import 'package:gymapp/models/coach_proposal.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/services/coach/coach_applier.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/utils/split_identity.dart';

import 'support/coach_fixtures.dart';
import 'support/hive_test_harness.dart';

const String _userId = 'coach-user';
final DateTime _seeded = DateTime(2026, 9, 1);

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open(includeSplits: true);
  });

  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  group('active split', () {
    test('an edit changes only the name and exercises', () async {
      await _seedSplit([
        _owned(plan('a', 'Push', [_bench], position: 0), color: 3),
        _owned(plan('b', 'Pull', [_row], position: 1), color: 5),
      ]);
      final snap = _snapshot();
      final outcome = await const CoachApplier().apply(
        _proposal(
          snap,
          plans: [
            CoachPlan(
              existing: snap.plans.first,
              name: 'Push day',
              exercises: [_coachSquat],
            ),
          ],
        ),
        userId: _userId,
      );

      expect(outcome, isA<CoachApplied>());
      expect((outcome as CoachApplied).splitId, kSplitId);
      final edited = HiveService.getPlanById('a')!;
      expect(edited.id, 'a');
      expect(edited.position, 0);
      expect(edited.planColor, kPlanColors[3]);
      expect(edited.splitId, kSplitId);
      expect(edited.userId, _userId);
      expect(edited.deletedAt, isNull);
      expect(edited.name, 'Push day');
      expect(edited.exercises.single.name, 'Squat');
      expect(edited.exercises.single.sets, 2);
      expect(
        edited.exercises.single.setTargets!.map((t) => (t.reps, t.weight)),
        [(5, 100.0), (5, 100.0)],
      );
      expect(edited.dirty, isTrue);
      expect(edited.updatedAt!.isAfter(_seeded), isTrue);

      final untouched = HiveService.getPlanById('b')!;
      expect(untouched.name, 'Pull');
      expect(untouched.updatedAt, _seeded);
      expect(untouched.dirty, isFalse);
    });

    test(
      'new plans follow the highest position and take free colours',
      () async {
        await _seedSplit([
          _owned(plan('a', 'Push', [_bench], position: 0), color: 0),
          _owned(plan('b', 'Pull', [_row], position: 4), color: 2),
        ]);
        final snap = _snapshot();
        await const CoachApplier().apply(
          _proposal(
            snap,
            plans: [
              CoachPlan(existing: null, name: 'Legs', exercises: [_coachSquat]),
              CoachPlan(existing: null, name: 'Arms', exercises: [_coachSquat]),
            ],
          ),
          userId: _userId,
        );

        final added = {
          for (final plan in HiveService.getPlans(splitId: kSplitId))
            if (plan.id != 'a' && plan.id != 'b') plan.name: plan,
        };
        expect(added.keys, unorderedEquals(['Legs', 'Arms']));
        expect(added['Legs']!.position, 5);
        expect(added['Arms']!.position, 6);
        expect(added['Legs']!.planColor, kPlanColors[1]);
        expect(added['Arms']!.planColor, kPlanColors[3]);
        for (final plan in added.values) {
          expect(plan.id, isNotEmpty);
          expect(plan.splitId, kSplitId);
          expect(plan.userId, _userId);
          expect(plan.dirty, isTrue);
          expect(plan.updatedAt!.isAfter(_seeded), isTrue);
          expect(plan.deletedAt, isNull);
        }
        expect(
          HiveService.getPlans(splitId: kSplitId).map((plan) => plan.name),
          ['Push', 'Pull', 'Legs', 'Arms'],
        );
      },
    );

    test(
      'a new plan in a legacy-ordered split keeps a null position',
      () async {
        await _seedSplit([
          _owned(plan('a', 'Push', [_bench]), color: 0),
          _owned(plan('b', 'Pull', [_row], position: 1), color: 1),
        ]);
        await const CoachApplier().apply(
          _proposal(
            _snapshot(),
            plans: [
              CoachPlan(existing: null, name: 'Legs', exercises: [_coachSquat]),
            ],
          ),
          userId: _userId,
        );

        final legs = HiveService.getPlans(
          splitId: kSplitId,
        ).firstWhere((plan) => plan.name == 'Legs');
        expect(legs.position, isNull);
      },
    );

    test('a new plan in an empty split starts at position 0', () async {
      await _seedSplit([]);
      await const CoachApplier().apply(
        _proposal(
          _snapshot(),
          plans: [
            CoachPlan(existing: null, name: 'Legs', exercises: [_coachSquat]),
          ],
        ),
        userId: _userId,
      );

      final legs = HiveService.getPlans(splitId: kSplitId).single;
      expect(legs.position, 0);
      expect(legs.planColor, kPlanColors[0]);
    });

    test('colours cycle once every slot is taken', () async {
      await _seedSplit([
        for (var index = 0; index < kPlanColors.length; index++)
          _owned(
            plan('p$index', 'Day $index', [_bench], position: index),
            color: index,
          ),
      ]);
      await const CoachApplier().apply(
        _proposal(
          _snapshot(),
          plans: [
            CoachPlan(existing: null, name: 'Extra', exercises: [_coachSquat]),
          ],
        ),
        userId: _userId,
      );

      final extra = HiveService.getPlans(
        splitId: kSplitId,
      ).firstWhere((plan) => plan.name == 'Extra');
      expect(extra.planColor, kPlanColors[0]);
      expect(extra.position, kPlanColors.length);
    });

    test('a removed plan becomes a tombstone and frees its colour', () async {
      await _seedSplit([
        _owned(plan('a', 'Push', [_bench], position: 0), color: 0),
        _owned(plan('b', 'Pull', [_row], position: 1), color: 1),
      ]);
      final snap = _snapshot();
      await const CoachApplier().apply(
        _proposal(
          snap,
          plans: [
            CoachPlan(existing: null, name: 'Legs', exercises: [_coachSquat]),
          ],
          removed: [snap.plans.first],
        ),
        userId: _userId,
      );

      final tombstone = HiveService.getPlanById('a')!;
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.updatedAt, tombstone.deletedAt);
      expect(tombstone.dirty, isTrue);
      expect(tombstone.name, 'Push');
      expect(tombstone.userId, _userId);
      expect(HiveService.getPlans(splitId: kSplitId).map((plan) => plan.name), [
        'Pull',
        'Legs',
      ]);
      final legs = HiveService.getPlans(splitId: kSplitId).last;
      expect(legs.planColor, kPlanColors[0]);
      expect(legs.position, 2);
    });

    test('sessions are never created or changed', () async {
      await _seedSplit([
        _owned(plan('a', 'Push', [_bench], position: 0), color: 0),
        _owned(plan('b', 'Pull', [_row], position: 1), color: 1),
      ]);
      await HiveService.putSessionRaw(
        session(DateTime(2026, 9, 2), {
          'Bench Press': [(5, 80)],
        }),
      );
      final before = _sessionsFingerprint();
      final snap = _snapshot();
      await const CoachApplier().apply(
        _proposal(
          snap,
          plans: [
            CoachPlan(
              existing: snap.plans.first,
              name: 'Push day',
              exercises: [_coachSquat],
            ),
            CoachPlan(existing: null, name: 'Legs', exercises: [_coachSquat]),
          ],
          removed: [snap.plans.last],
        ),
        userId: _userId,
      );

      expect(_sessionsFingerprint(), before);
    });
  });

  group('stale proposals write nothing', () {
    Future<ValidatedProposal> seeded() async {
      await _seedSplit([
        _owned(plan('a', 'Push', [_bench], position: 0), color: 0),
        _owned(plan('b', 'Pull', [_row], position: 1), color: 1),
      ]);
      final snap = _snapshot();
      return _proposal(
        snap,
        plans: [
          CoachPlan(
            existing: snap.plans.first,
            name: 'Push day',
            exercises: [_coachSquat],
          ),
          CoachPlan(existing: null, name: 'Legs', exercises: [_coachSquat]),
        ],
        removed: [snap.plans.last],
      );
    }

    Future<void> expectStale(
      ValidatedProposal proposal,
      CoachStaleReason reason,
    ) async {
      final before = _fingerprint();
      final outcome = await const CoachApplier().apply(
        proposal,
        userId: _userId,
      );
      expect(outcome, isA<CoachApplyStale>());
      expect((outcome as CoachApplyStale).reason, reason);
      expect(_fingerprint(), before);
    }

    test('when a plan was edited since the snapshot', () async {
      final proposal = await seeded();
      await HiveService.upsertPlan(
        HiveService.getPlanById('b')!.copyWith(name: 'Pull (edited)'),
      );
      await expectStale(proposal, CoachStaleReason.plansChanged);
    });

    test('when a plan was added since the snapshot', () async {
      final proposal = await seeded();
      await HiveService.putPlanRaw(
        _owned(plan('c', 'Core', [_bench], position: 2), color: 2),
      );
      await expectStale(proposal, CoachStaleReason.plansChanged);
    });

    test('when a plan was removed since the snapshot', () async {
      final proposal = await seeded();
      await HiveService.softDeletePlan('b');
      await expectStale(proposal, CoachStaleReason.plansChanged);
    });

    test('when the active split was switched', () async {
      final proposal = await seeded();
      await HiveService.putSplitRaw(
        Split(
          id: 'other',
          name: 'Other',
          userId: _userId,
          createdAt: DateTime(2026, 9, 2),
        ),
      );
      await HiveService.putSplitPreferenceRaw(
        SplitPreference(userId: _userId, activeSplitId: 'other'),
      );
      await expectStale(proposal, CoachStaleReason.activeSplitChanged);
    });

    test(
      'a sync clearing dirty without a new updatedAt is not stale',
      () async {
        final proposal = await seeded();
        await HiveService.clearPlanDirty('b');
        final outcome = await const CoachApplier().apply(
          proposal,
          userId: _userId,
        );
        expect(outcome, isA<CoachApplied>());
      },
    );
  });

  group('rollback restores Hive exactly', () {
    for (final stage in [
      CoachApplyStage.plansWritten,
      CoachApplyStage.tombstonesWritten,
    ]) {
      test('after an active-split failure at $stage', () async {
        await _seedSplit([
          _owned(plan('a', 'Push', [_bench], position: 0), color: 0),
          _owned(plan('b', 'Pull', [_row], position: 1), color: 1),
          _owned(plan('c', 'Legs', [_row], position: 2), color: 2),
        ]);
        final snap = _snapshot();
        final before = _fingerprint();
        final applier = CoachApplier(
          applyHook: (current) async {
            if (current == stage) throw StateError('Injected failure');
          },
        );

        await expectLater(
          applier.apply(
            _proposal(
              snap,
              plans: [
                CoachPlan(
                  existing: snap.plans.first,
                  name: 'Push day',
                  exercises: [_coachSquat],
                ),
                CoachPlan(
                  existing: null,
                  name: 'Arms',
                  exercises: [_coachSquat],
                ),
              ],
              removed: [snap.plans[1]],
            ),
            userId: _userId,
          ),
          throwsA(isA<StateError>()),
        );

        expect(_fingerprint(), before);
      });
    }

    for (final stage in [
      CoachApplyStage.plansWritten,
      CoachApplyStage.splitWritten,
      CoachApplyStage.preferenceWritten,
    ]) {
      test('after a new-split failure at $stage', () async {
        await _seedSplit([
          _owned(plan('a', 'Push', [_bench], position: 0), color: 0),
        ]);
        final before = _fingerprint();
        final applier = CoachApplier(
          applyHook: (current) async {
            if (current == stage) throw StateError('Injected failure');
          },
        );

        await expectLater(
          applier.apply(_newSplitProposal(_snapshot()), userId: _userId),
          throwsA(isA<StateError>()),
        );

        expect(_fingerprint(), before);
      });
    }

    test('after a failure while reusing the default split', () async {
      final defaultId = await _seedDefault();
      final before = _fingerprint();
      final applier = CoachApplier(
        applyHook: (current) async {
          if (current == CoachApplyStage.preferenceWritten) {
            throw StateError('Injected failure');
          }
        },
      );

      await expectLater(
        applier.apply(
          _newSplitProposal(_snapshot(splitId: defaultId)),
          userId: _userId,
        ),
        throwsA(isA<StateError>()),
      );

      expect(_fingerprint(), before);
    });
  });

  group('new split', () {
    test('creates the split, makes it active, and orders its plans', () async {
      await _seedSplit([
        _owned(plan('a', 'Push', [_bench], position: 0), color: 4),
      ]);
      final outcome = await const CoachApplier().apply(
        _newSplitProposal(_snapshot()),
        userId: _userId,
      );

      expect(outcome, isA<CoachApplied>());
      final applied = outcome as CoachApplied;
      expect(applied.reusedDefaultSplit, isFalse);
      expect(applied.splitId, isNot(kSplitId));
      expect(applied.splitName, 'Upper lower');

      final split = HiveService.getSplitById(applied.splitId)!;
      expect(split.name, 'Upper lower');
      expect(split.userId, _userId);
      expect(split.dirty, isTrue);
      expect(split.updatedAt!.isAfter(_seeded), isTrue);
      final preference = HiveService.getSplitPreference(_userId)!;
      expect(preference.activeSplitId, applied.splitId);
      expect(preference.dirty, isTrue);
      expect(HiveService.getActiveSplitId(_userId), applied.splitId);

      final plans = HiveService.getPlans(splitId: applied.splitId);
      expect(plans.map((plan) => plan.name), ['Upper', 'Lower', 'Upper B']);
      expect(plans.map((plan) => plan.position), [0, 1, 2]);
      expect(plans.map((plan) => plan.planColor), kPlanColors.take(3));
      for (final plan in plans) {
        expect(plan.userId, _userId);
        expect(plan.dirty, isTrue);
        expect(plan.updatedAt, split.updatedAt);
      }

      final old = HiveService.getPlanById('a')!;
      expect(old.splitId, kSplitId);
      expect(old.deletedAt, isNull);
      expect(old.dirty, isFalse);
    });

    test('reuses an untouched default split', () async {
      final defaultId = await _seedDefault();
      final outcome = await const CoachApplier().apply(
        _newSplitProposal(_snapshot(splitId: defaultId)),
        userId: _userId,
      );

      final applied = outcome as CoachApplied;
      expect(applied.reusedDefaultSplit, isTrue);
      expect(applied.splitId, defaultId);
      final split = HiveService.getSplits().single;
      expect(split.id, defaultId);
      expect(split.name, 'Upper lower');
      expect(split.dirty, isTrue);
      expect(HiveService.getPlans(splitId: defaultId), hasLength(3));
    });

    test('the split limit blocks it unless My Split is reusable', () async {
      await _seedSplit([]);
      for (var index = 1; index < 5; index++) {
        await HiveService.putSplitRaw(
          Split(
            id: 'split-extra-$index',
            name: 'Extra $index',
            userId: _userId,
            createdAt: DateTime(2026, 9, 1 + index),
          ),
        );
      }
      final before = _fingerprint();

      await expectLater(
        const CoachApplier().apply(
          _newSplitProposal(_snapshot()),
          userId: _userId,
        ),
        throwsA(isA<StateError>()),
      );

      expect(_fingerprint(), before);
    });

    test('a taken name gets a bounded suffix', () async {
      await _seedSplit([]);
      await HiveService.putSplitRaw(
        Split(
          id: 'taken',
          name: 'Upper lower',
          userId: _userId,
          createdAt: DateTime(2026, 9, 2),
        ),
      );
      final outcome = await const CoachApplier().apply(
        _newSplitProposal(_snapshot()),
        userId: _userId,
      );
      expect((outcome as CoachApplied).splitName, 'Upper lower (2)');
    });
  });

  test('SplitProvider reloads splits and plans after applying', () async {
    await _seedSplit([
      _owned(plan('a', 'Push', [_bench], position: 0), color: 0),
    ]);
    final splits = SplitProvider(userIdProvider: () => _userId);
    final plans = WorkoutPlanProvider(splits);
    addTearDown(() {
      plans.dispose();
      splits.dispose();
    });

    final outcome = await splits.applyCoachProposal(
      _newSplitProposal(_snapshot()),
    );

    final applied = outcome as CoachApplied;
    expect(splits.activeSplitId, applied.splitId);
    expect(plans.plans.map((plan) => plan.name), ['Upper', 'Lower', 'Upper B']);
  });
}

final _bench = template('Bench Press', [(8, 60), (8, 60)]);
final _row = template('Barbell Row', [(10, 50)]);
final _coachSquat = CoachExercise(
  name: 'Squat',
  sets: const [CoachSet(reps: 5, kg: 100), CoachSet(reps: 5, kg: 100)],
  note: 'Brace hard.',
);

WorkoutPlan _owned(WorkoutPlan plan, {required int color}) =>
    plan.copyWith(userId: _userId, dirty: false, planColor: kPlanColors[color]);

/// The split `kSplitId`, active for the user, holding [plans].
Future<void> _seedSplit(List<WorkoutPlan> plans) async {
  await HiveService.putSplitRaw(
    Split(
      id: kSplitId,
      name: 'Push Pull Legs',
      userId: _userId,
      createdAt: _seeded,
      updatedAt: _seeded,
      dirty: false,
    ),
  );
  await HiveService.putSplitPreferenceRaw(
    SplitPreference(
      userId: _userId,
      activeSplitId: kSplitId,
      updatedAt: _seeded,
      dirty: false,
    ),
  );
  await HiveService.putPlansRaw({for (final plan in plans) plan.id!: plan});
}

/// The user's untouched `My Split`, active, with no plans or sessions.
Future<String> _seedDefault() async {
  final id = defaultSplitIdForUser(_userId);
  await HiveService.putSplitRaw(
    Split(
      id: id,
      name: 'My Split',
      userId: _userId,
      createdAt: _seeded,
      updatedAt: _seeded,
      dirty: false,
    ),
  );
  await HiveService.putSplitPreferenceRaw(
    SplitPreference(
      userId: _userId,
      activeSplitId: id,
      updatedAt: _seeded,
      dirty: false,
    ),
  );
  return id;
}

/// What the Coach would see for the active split right now.
CoachSnapshot _snapshot({String splitId = kSplitId}) {
  final splits = HiveService.getSplits();
  return CoachSnapshot(
    splitId: splitId,
    splitName: HiveService.getSplitById(splitId)!.name,
    plans: HiveService.getPlans(splitId: splitId),
    splitNames: [for (final split in splits) split.name],
    maxSplits: SplitProvider.maxSplits,
    customExercises: const [],
  );
}

ValidatedProposal _proposal(
  CoachSnapshot snapshot, {
  required List<CoachPlan> plans,
  List<WorkoutPlan> removed = const [],
}) => ValidatedProposal(
  target: CoachTarget.activeSplit,
  newSplitName: null,
  plans: plans,
  removedPlans: removed,
  snapshot: snapshot,
);

ValidatedProposal _newSplitProposal(CoachSnapshot snapshot) =>
    ValidatedProposal(
      target: CoachTarget.newSplit,
      newSplitName: 'Upper lower',
      plans: [
        for (final name in ['Upper', 'Lower', 'Upper B'])
          CoachPlan(existing: null, name: name, exercises: [_coachSquat]),
      ],
      removedPlans: const [],
      snapshot: snapshot,
    );

/// Every record in every box, including the fields `toJson` leaves out.
String _fingerprint() => jsonEncode({
  'plans': {
    for (final plan in HiveService.getAllPlansRaw())
      plan.id: {...plan.toJson(), 'userId': plan.userId, 'dirty': plan.dirty},
  },
  'splits': {
    for (final split in Hive.box<Split>(HiveService.splitsBox).values)
      split.id: {
        ...split.toJson(),
        'userId': split.userId,
        'dirty': split.dirty,
      },
  },
  'preferences': {
    for (final preference
        in Hive.box<SplitPreference>(HiveService.splitPreferencesBox).values)
      preference.userId: {
        'activeSplitId': preference.activeSplitId,
        'updatedAt': preference.updatedAt?.toIso8601String(),
        'dirty': preference.dirty,
      },
  },
  'sessions': _sessionsFingerprint(),
});

String _sessionsFingerprint() => jsonEncode({
  for (final session in HiveService.getAllSessionsRaw())
    session.id: {
      ...session.toJson(),
      'userId': session.userId,
      'dirty': session.dirty,
    },
});
