import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/adopt_local_data.dart';
import 'package:gymapp/services/training_block_graph.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';

import 'support/hive_test_harness.dart';

const splitId = '05120ff6-66b5-48cd-9808-141bcb949f24';
const planId = '00000000-0000-4000-8000-000000000001';
final stamp = DateTime.utc(2025, 1, 1);

class InterruptedMigration extends TrainingBlockMigration {
  final String stopAfter;
  InterruptedMigration(this.stopAfter);

  @override
  Future<void> checkpoint(
    String owner,
    Map<String, dynamic> journal,
    String phase,
  ) async {
    await super.checkpoint(owner, journal, phase);
    if (phase == stopAfter) throw const FileSystemException('Interrupted');
  }
}

void main() {
  final storage = HiveTestHarness();
  final repository = TrainingBlockRepository();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    await HiveService.putSplitRaw(
      Split(id: splitId, name: 'A', createdAt: stamp),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(id: planId, name: 'Push', exercises: [], splitId: splitId),
    );
  });
  tearDown(storage.close);

  Future<void> session(
    String id,
    int week, {
    bool completed = true,
    bool running = false,
    String? plan = planId,
    String name = 'Push',
    bool deleted = false,
  }) => HiveService.putSessionRaw(
    WorkoutSession(
      id: id,
      date: stamp.add(Duration(days: week)),
      planName: name,
      planId: plan,
      splitId: splitId,
      weekNumber: week,
      isCompleted: completed,
      updatedAt: stamp,
      dirty: false,
      deletedAt: deleted ? stamp : null,
      startedAt: running ? stamp : null,
      timerStartedAt: running ? stamp : null,
      durationSeconds: 72,
      exercises: [
        Exercise(
          name: 'Squat',
          sets: [Set(reps: 8, weight: 80, rpe: 7, note: 'Keep me')],
        ),
      ],
    ),
  );

  test('frozen URL UUID vectors canonicalize UUID case', () {
    expect(
      legacyTrainingBlockId(splitId.toUpperCase()),
      '9dcb7f75-fb0d-5c2b-8cec-c66b46a9386d',
    );
    expect(
      legacyTrainingWeekId(splitId, 3),
      '39e7f177-288f-5c49-bdcc-e0ccf45671de',
    );
    expect(
      workoutProgressId(splitId, planId),
      'fe40b608-43e5-566a-ba8f-1a71159cd1a7',
    );
    expect(
      initialProgressRevision(splitId, planId),
      'f4b5039f-16e7-5024-b662-bf6b0b6f4b01',
    );
  });

  test(
    'sparse union includes tombstones and preserves complete exercise/timer payload',
    () async {
      await session('one', 1);
      await session('three', 3, running: true, completed: false);
      await session('twelve', 12, deleted: true, plan: null, name: 'Removed');
      final before = {
        for (final s in HiveService.getAllSessionsRaw())
          s.id: jsonEncode(s.toJson()),
      };
      await TrainingBlockMigration().normalize(ownerId: null);
      final block = repository.blocksForSplit(splitId).single;
      expect(repository.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
        3,
        12,
      ]);
      for (final s in HiveService.getAllSessionsRaw()) {
        final old = jsonDecode(before[s.id]!) as Map<String, dynamic>;
        final current = s.toJson()..remove('trainingWeekId');
        old.remove('trainingWeekId');
        for (final row in current['exercises'] as List) {
          expect(row['exerciseId'], 'builtin:squat');
          row.remove('exerciseId');
        }
        for (final row in old['exercises'] as List) {
          row.remove('exerciseId');
        }
        expect(jsonEncode(current), jsonEncode(old));
        expect(s.updatedAt, stamp);
        expect(s.dirty, isTrue);
      }
      expect(
        repository.progressForPlan(splitId, planId)!.activeWeekId,
        legacyTrainingWeekId(splitId, 3),
      );
      final snapshot = jsonEncode(
        repository.progressForPlan(splitId, planId)!.toJson(),
      );
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(
        jsonEncode(repository.progressForPlan(splitId, planId)!.toJson()),
        snapshot,
      );
      expect(repository.blocksForSplit(splitId), hasLength(1));
      await session('late', 22);
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(repository.weeksForBlock(splitId, block.id).last.number, 22);
      expect(
        jsonEncode(repository.progressForPlan(splitId, planId)!.toJson()),
        snapshot,
      );
    },
  );

  test(
    'migration bootstrap metadata is distinguishable from a structural edit',
    () async {
      await HiveService.putSplitRaw(
        HiveService.getSplitById(
          splitId,
        )!.copyWith(updatedAt: DateTime.utc(2030)),
      );
      await HiveService.putPlanRaw(
        HiveService.getPlanById(
          planId,
        )!.copyWith(updatedAt: DateTime.utc(2030)),
      );
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(repository.blocksForSplit(splitId).single.updatedAt, isNull);
      expect(HiveService.getAllTrainingWeeksRaw().single.updatedAt, isNull);
      expect(repository.progressForPlan(splitId, planId)!.updatedAt, isNull);
    },
  );

  test('empty split starts at Week 1 without fake history', () async {
    await TrainingBlockMigration().normalize(ownerId: null);
    final b = repository.blocksForSplit(splitId).single;
    expect(repository.weeksForBlock(splitId, b.id).single.number, 1);
    expect(HiveService.getAllSessionsRaw(), isEmpty);
  });

  test(
    'unambiguous missing plan resolves; ambiguous and dangling IDs stay historical',
    () async {
      await session('resolved', 1, plan: null);
      await session('dangling', 3, plan: 'gone');
      await HiveService.putPlanRaw(
        WorkoutPlan(id: 'p2', name: 'Pull', exercises: [], splitId: splitId),
      );
      await HiveService.putPlanRaw(
        WorkoutPlan(id: 'p3', name: 'Pull', exercises: [], splitId: splitId),
      );
      await session('ambiguous', 12, plan: null, name: 'Pull');
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(HiveService.getSessionById('resolved')!.planId, planId);
      expect(HiveService.getSessionById('dangling')!.planId, 'gone');
      expect(HiveService.getSessionById('ambiguous')!.planId, isNull);
    },
  );

  test(
    'running draft outranks later draft; without drafts completion uses next supplied week',
    () async {
      await session('running', 1, completed: false, running: true);
      await session('future', 12, completed: false);
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(
        repository.progressForPlan(splitId, planId)!.activeWeekId,
        legacyTrainingWeekId(splitId, 1),
      );
      expect(HiveService.getSessionById('future'), isNotNull);
    },
  );

  test(
    'highest completed final week awaits boundary, deleted logs do not advance',
    () async {
      await session('done', 3);
      await session('deleted', 12, deleted: true);
      await TrainingBlockMigration().normalize(ownerId: null);
      final p = repository.progressForPlan(splitId, planId)!;
      expect(p.activeWeekId, legacyTrainingWeekId(splitId, 12));
      expect(p.state, WorkoutProgressState.ready);
    },
  );

  test(
    'invalid weeks are recoverable; foreign cache is never migrated',
    () async {
      await session('bad', 0);
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: null),
        throwsA(isA<TrainingPreparationException>()),
      );
      expect(repository.blocksForSplit(splitId), isEmpty);
      await HiveService.putSplitRaw(
        Split(id: 'foreign', name: 'B', userId: 'B', createdAt: stamp),
      );
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: 'B'),
        throwsA(isA<TrainingPreparationException>()),
      );
      expect(repository.blocksForSplit('foreign'), isEmpty);
    },
  );

  test(
    'offline preparation assigns missing splits before training migration',
    () async {
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'unscoped',
          date: stamp,
          planName: 'Removed',
          exercises: [],
          weekNumber: 3,
        ),
      );
      await AdoptLocalData.prepareOffline();
      final saved = HiveService.getSessionById('unscoped')!;
      expect(saved.splitId, isNotNull);
      expect(saved.trainingWeekId, legacyTrainingWeekId(saved.splitId!, 3));
    },
  );

  test(
    'supplied conflicting week links fail before structure is mutated',
    () async {
      await session('linked', 1);
      final linked = HiveService.getSessionById(
        'linked',
      )!.copyWith(trainingWeekId: 'missing');
      await HiveService.putSessionRaw(linked);
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: null),
        throwsA(isA<TrainingPreparationException>()),
      );
      expect(repository.blocksForSplit(splitId), isEmpty);
      expect(HiveService.getSessionById('linked')!.trainingWeekId, 'missing');
    },
  );

  test(
    'late legacy labels reserve original numbers and rebase random additions with saved values',
    () async {
      await session('one', 1);
      await TrainingBlockMigration().normalize(ownerId: null);
      final block = repository.blocksForSplit(splitId).single;
      final randomWeek = await TrainingBlockRepository(
        ownerId: () => null,
      ).appendWeek(splitId, block.id);
      final randomSession = WorkoutSession(
        id: 'random',
        date: stamp,
        planName: 'Push',
        exercises: [
          Exercise(name: 'Squat', sets: [Set(reps: 9, weight: 100)]),
        ],
        planId: planId,
        splitId: splitId,
        trainingWeekId: randomWeek.id,
        weekNumber: 2,
      );
      await HiveService.putSessionRaw(randomSession);
      await session('late', 2);
      await TrainingBlockMigration().normalize(ownerId: null);
      final saved = HiveService.getSessionById('random')!;
      expect(saved.trainingWeekId, randomWeek.id);
      expect(saved.weekNumber, 3);
      expect(saved.exercises.single.sets.single.weight, 100);
      expect(
        HiveService.getSessionById('late')!.trainingWeekId,
        legacyTrainingWeekId(splitId, 2),
      );
      expect(repository.weeksForBlock(splitId, block.id).map((w) => w.number), [
        1,
        2,
        3,
      ]);
    },
  );

  test(
    'latest incomplete draft wins deterministically when no timer is running',
    () async {
      await session('older', 1, completed: false);
      await session('newer', 12, completed: false);
      await TrainingBlockMigration().normalize(ownerId: null);
      expect(
        repository.progressForPlan(splitId, planId)!.activeWeekId,
        legacyTrainingWeekId(splitId, 12),
      );
    },
  );

  test('completed last supplied week keeps a pending boundary', () async {
    await session('done', 3);
    await TrainingBlockMigration().normalize(ownerId: null);
    expect(
      repository.progressForPlan(splitId, planId)!.state,
      WorkoutProgressState.awaitingBoundary,
    );
  });

  test(
    'late normalization replaces a successful safety snapshot before touching new inputs',
    () async {
      await session('one', 1);
      await TrainingBlockMigration().normalize(ownerId: null);
      final path = TrainingBlockMigration().snapshotPath(null);
      await session('late-invalid', 0);
      await expectLater(
        TrainingBlockMigration().normalize(ownerId: null),
        throwsA(isA<TrainingPreparationException>()),
      );
      final snapshot =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      expect(
        (snapshot['sessions'] as List).map((s) => (s as Map)['id']),
        contains('late-invalid'),
      );
    },
  );

  for (final writtenSessions in [-1, 0, 1]) {
    test(
      'pending rebase recovers after week and $writtenSessions session writes',
      () async {
        await TrainingBlockMigration().normalize(ownerId: null);
        final block = repository.blocksForSplit(splitId).single;
        final week = await TrainingBlockRepository(
          ownerId: () => null,
        ).appendWeek(splitId, block.id);
        for (final id in ['first', 'second']) {
          await HiveService.putSessionRaw(
            WorkoutSession(
              id: id,
              date: stamp,
              planName: 'Push',
              planId: planId,
              splitId: splitId,
              trainingWeekId: week.id,
              weekNumber: 2,
              durationSeconds: 72,
              exercises: [
                Exercise(name: 'Squat', sets: [Set(reps: 8, weight: 80)]),
              ],
            ),
          );
        }
        final target = week.copyWith(number: 3, dirty: true);
        final operations = Hive.box<dynamic>(HiveService.trainingOperationsBox);
        await operations.put('weekRebase', {
          'ownerId': null,
          'previousNumber': 2,
          'week': target.toJson(),
          'dirty': true,
        });
        await operations.flush();
        if (writtenSessions >= 0) await HiveService.putTrainingWeekRaw(target);
        if (writtenSessions == 1) {
          await HiveService.putSessionRaw(
            HiveService.getSessionById('first')!.copyWith(weekNumber: 3),
          );
        }
        await TrainingBlockMigration().normalize(ownerId: null);
        for (final id in ['first', 'second']) {
          final saved = HiveService.getSessionById(id)!;
          expect(saved.trainingWeekId, week.id);
          expect(saved.weekNumber, 3);
          expect(saved.durationSeconds, 72);
          expect(saved.exercises.single.sets.single.weight, 80);
        }
        expect(operations.get('weekRebase'), isNull);
        await TrainingBlockMigration().normalize(ownerId: null);
        expect(repository.weeksForBlock(splitId, block.id).last.id, week.id);
      },
    );
  }

  for (final phase in [
    'snapshot',
    'parents',
    'links',
    'progress',
    'verification',
    'complete',
  ]) {
    test(
      'restart after $phase rolls forward once, retaining original snapshot',
      () async {
        await session('draft', 3, completed: false, running: true);
        await expectLater(
          InterruptedMigration(phase).normalize(ownerId: null),
          throwsA(isA<TrainingPreparationException>()),
        );
        final path = TrainingBlockMigration().snapshotPath(null);
        final bytes = await File(path).readAsBytes();
        await TrainingBlockMigration().normalize(ownerId: null);
        expect(await File(path).readAsBytes(), bytes);
        expect(repository.blocksForSplit(splitId), hasLength(1));
        expect(
          repository.progressForPlan(splitId, planId)!.activeWeekId,
          legacyTrainingWeekId(splitId, 3),
        );
        expect(HiveService.getSessionById('draft')!.isTimerRunning, isTrue);
      },
    );
  }

  group('rescuing work from a deleted block', () {
    const u = 'user-1';
    const planA = 'plan-a';
    const planB = 'plan-b';
    final t0 = DateTime.utc(2026, 1, 1);
    final tDelete = DateTime.utc(2026, 11, 16, 12);
    final clock = DateTime.utc(2026, 6, 1);

    Split split0([String id = splitId, DateTime? deleted]) => Split(
      id: id,
      name: 'S-${id.substring(0, 4)}',
      createdAt: t0,
      userId: u,
      updatedAt: t0,
      deletedAt: deleted,
      dirty: false,
    );
    WorkoutPlan plan0(String id, {DateTime? deleted, String sid = splitId}) =>
        WorkoutPlan(
          id: id,
          name: id,
          exercises: [],
          splitId: sid,
          userId: u,
          updatedAt: t0,
          deletedAt: deleted,
          dirty: false,
        );
    TrainingBlock block0(
      String id, {
      int count = 4,
      int position = 0,
      DateTime? deleted,
      String sid = splitId,
      DateTime? durationClock,
      String name = 'Block',
    }) => TrainingBlock(
      id: id,
      splitId: sid,
      name: name,
      position: position,
      createdAt: t0,
      userId: u,
      updatedAt: deleted ?? t0,
      deletedAt: deleted,
      plannedWeekCount: count,
      plannedWeekCountUpdatedAt: durationClock,
      dirty: false,
    );
    TrainingWeek week0(
      String id,
      String blockId,
      int n, {
      DateTime? deleted,
      String sid = splitId,
    }) => TrainingWeek(
      id: id,
      splitId: sid,
      blockId: blockId,
      number: n,
      createdAt: t0,
      userId: u,
      updatedAt: deleted ?? t0,
      deletedAt: deleted,
      dirty: false,
    );
    WorkoutProgress progress0(
      String plan,
      String active,
      List<String> available, {
      String state = WorkoutProgressState.ready,
      String sid = splitId,
      DateTime? deleted,
    }) => WorkoutProgress(
      id: workoutProgressId(sid, plan),
      splitId: sid,
      planId: plan,
      activeWeekId: active,
      availableWeekIds: available,
      state: state,
      revision: 'rev-$plan',
      userId: u,
      updatedAt: t0,
      deletedAt: deleted,
      dirty: false,
    );
    WorkoutSession session0(
      String id,
      String plan,
      String weekId,
      int number, {
      String? nextWeekId,
      bool completed = true,
      DateTime? deleted,
      String sid = splitId,
    }) => WorkoutSession(
      id: id,
      date: t0.add(Duration(days: number)),
      planName: plan,
      planId: plan,
      splitId: sid,
      weekNumber: number,
      trainingWeekId: weekId,
      isCompleted: completed,
      completionTransition:
          nextWeekId == null
              ? null
              : {
                'expectedRevision': 'rev-$plan',
                'sourceWeekId': weekId,
                'nextWeekId': nextWeekId,
                'resultRevision': id,
                'committedAt': t0.toIso8601String(),
              },
      exercises: [],
      userId: u,
      updatedAt: t0,
      deletedAt: deleted,
      dirty: false,
    );
    TrainingBlockGraph graph0({
      List<Split>? splits,
      List<WorkoutPlan>? plans,
      required List<TrainingBlock> blocks,
      required List<TrainingWeek> weeks,
      List<WorkoutProgress> progress = const [],
      List<WorkoutSession> sessions = const [],
    }) => TrainingBlockGraph(
      ownerId: u,
      splits: splits ?? [split0()],
      plans: plans ?? [plan0(planA)],
      blocks: blocks,
      weeks: weeks,
      progress: progress,
      sessions: sessions,
    );
    String dump(TrainingBlockGraph g) => jsonEncode(g.toJson());
    TrainingBlockGraph prep(TrainingBlockGraph g) {
      final out = TrainingBlockMigration.prepareGraph(g);
      out.validate();
      return out;
    }

    const x = 'block-x';
    const y = 'block-y';
    final xw1 = lazyTrainingWeekId(splitId, x, 1);
    final xw2 = lazyTrainingWeekId(splitId, x, 2);
    final xw3 = lazyTrainingWeekId(splitId, x, 3);
    final yw1 = lazyTrainingWeekId(splitId, y, 1);
    final xPrime = rescuedTrainingBlockId(x);
    String xpw(int n) => lazyTrainingWeekId(splitId, xPrime, n);

    /// Block X deleted elsewhere, Y live. Weeks 1..3 of X exist (tombstoned as
    /// the server does it); Y has Week 1.
    TrainingBlockGraph deleted({
      List<WorkoutProgress>? progress,
      List<WorkoutSession> sessions = const [],
      List<WorkoutPlan>? plans,
      List<TrainingBlock> extraBlocks = const [],
      List<TrainingWeek> extraWeeks = const [],
      bool xWeeksTombstoned = true,
      int xCount = 4,
    }) => graph0(
      plans: plans,
      blocks: [
        block0(
          x,
          count: xCount,
          position: 0,
          deleted: tDelete,
          durationClock: clock,
          name: 'Bulk',
        ),
        block0(y, position: 1),
        ...extraBlocks,
      ],
      weeks: [
        week0(xw1, x, 1, deleted: xWeeksTombstoned ? tDelete : null),
        week0(xw2, x, 2, deleted: xWeeksTombstoned ? tDelete : null),
        week0(xw3, x, 3, deleted: xWeeksTombstoned ? tDelete : null),
        week0(yw1, y, 1),
        ...extraWeeks,
      ],
      progress:
          progress ??
          [
            progress0(planA, yw1, [yw1]),
          ],
      sessions: sessions,
    );

    test('no deleted block: the graph comes back byte for byte', () {
      final g = graph0(
        blocks: [block0(x, durationClock: clock), block0(y, position: 1)],
        weeks: [week0(xw1, x, 1), week0(xw2, x, 2), week0(yw1, y, 1)],
        progress: [
          progress0(planA, xw2, [xw1, xw2]),
        ],
        sessions: [session0('s1', planA, xw1, 1, nextWeekId: xw2)],
      );
      final out = prep(g);
      expect(dump(out), dump(g));
      expect(out.blocks.any((b) => b.dirty == true), isFalse);
      expect(out.sessions.any((s) => s.dirty == true), isFalse);
      expect(out.progress.any((p) => p.dirty == true), isFalse);
      expect(dump(prep(out)), dump(out));
    });

    test('a deleted block with no live dependents keeps today behaviour', () {
      final g = deleted(
        xWeeksTombstoned: false,
        sessions: [
          // A session the deleting replica already tombstoned is not live work.
          session0('old', planB, xw1, 1, deleted: tDelete),
        ],
        plans: [plan0(planA), plan0(planB, deleted: tDelete)],
      );
      final out = prep(g);
      expect(out.blocks.map((b) => b.id), isNot(contains(xPrime)));
      expect(out.blocks, hasLength(2));
      // The existing cascade: weeks and sessions under the deleted block go.
      for (final w in out.weeks.where((w) => w.blockId == x)) {
        expect(w.deletedAt, isNotNull);
      }
      expect(out.sessions.single.deletedAt, tDelete);
      expect(out.progress.single.deletedAt, isNull);
    });

    test('live progress alone moves into a rescued block', () {
      final out = prep(
        deleted(
          progress: [
            progress0(planA, xw2, [xw1, xw2]),
          ],
        ),
      );
      final rescued = out.blocks.singleWhere((b) => b.id == xPrime);
      expect(rescued.deletedAt, isNull);
      expect(rescued.dirty, isTrue);
      expect(rescued.name, 'Bulk');
      expect(rescued.position, 0);
      expect(rescued.plannedWeekCount, 4);
      expect(rescued.plannedWeekCountUpdatedAt, clock);
      expect(rescued.userId, u);
      final weeks =
          out.weeks.where((w) => w.blockId == xPrime).toList()
            ..sort((a, b) => a.number.compareTo(b.number));
      expect(weeks.map((w) => (w.id, w.number, w.dirty, w.deletedAt)), [
        (xpw(1), 1, true, null),
        (xpw(2), 2, true, null),
      ]);
      final p = out.progress.single;
      expect(p.activeWeekId, xpw(2));
      expect(p.availableWeekIds, [xpw(1), xpw(2)]);
      // It must win last-write-wins on the server, whose stored row still
      // points into the deleted block: a new revision derived from the old one
      // and the successor, and a time one millisecond after the row's own, never
      // the deletion's.
      expect(p.revision, rescuedProgressRevision('rev-$planA', xPrime));
      expect(p.revision, isNot('rev-$planA'));
      expect(p.updatedAt, t0.add(const Duration(milliseconds: 1)));
      expect(p.deletedAt, isNull);
      expect(p.dirty, isTrue);
      // The deleted block itself stays deleted.
      expect(out.blocks.singleWhere((b) => b.id == x).deletedAt, tDelete);
    });

    test('live sessions alone are relinked and keep their identity', () {
      final done = session0('s1', planA, xw3, 3);
      final out = prep(deleted(sessions: [done]));
      final s = out.sessions.single;
      expect(s.id, 's1');
      expect(s.trainingWeekId, xpw(3));
      expect(s.weekNumber, 3);
      expect(s.deletedAt, isNull);
      expect(s.dirty, isTrue);
      expect(s.updatedAt, t0);
      expect(out.blocks.singleWhere((b) => b.id == xPrime).plannedWeekCount, 4);
      // Only the referenced number is allocated.
      expect(out.weeks.where((w) => w.blockId == xPrime).map((w) => w.number), [
        3,
      ]);
    });

    test('progress and sessions together move to the same weeks', () {
      final out = prep(
        deleted(
          progress: [
            progress0(planA, xw2, [xw1, xw2]),
          ],
          sessions: [session0('s1', planA, xw1, 1, nextWeekId: xw2)],
        ),
      );
      final s = out.sessions.single;
      expect(s.trainingWeekId, xpw(1));
      expect(s.completionTransition!['sourceWeekId'], xpw(1));
      expect(s.completionTransition!['nextWeekId'], xpw(2));
      expect(s.completionTransition!['resultRevision'], 's1');
      expect(s.completionTransition!['expectedRevision'], 'rev-$planA');
      expect(out.progress.single.activeWeekId, xpw(2));
      expect(out.weeks.where((w) => w.blockId == xPrime).map((w) => w.number), [
        1,
        2,
      ]);
    });

    test(
      'the rescued length covers the highest week even past the old one',
      () {
        final out = prep(
          deleted(
            xCount: 2,
            progress: [
              progress0(planA, xw3, [xw3]),
            ],
          ),
        );
        expect(
          out.blocks.singleWhere((b) => b.id == xPrime).plannedWeekCount,
          3,
        );
      },
    );

    test('a progress row that only lists the block as available does not '
        'bring a deleted block back', () {
      final out = prep(
        deleted(
          progress: [
            progress0(planA, yw1, [xw1, yw1]),
          ],
        ),
      );
      expect(out.blocks.map((b) => b.id), isNot(contains(xPrime)));
      expect(out.progress.single.deletedAt, isNull);
      expect(out.progress.single.availableWeekIds, [xw1, yw1]);
    });

    test(
      'once a rescue runs, other available entries in the block move too',
      () {
        final out = prep(
          deleted(
            plans: [plan0(planA), plan0(planB)],
            progress: [
              progress0(planA, xw2, [xw2]),
              progress0(planB, yw1, [xw1, yw1]),
            ],
          ),
        );
        final b = out.progress.singleWhere((p) => p.planId == planB);
        expect(b.activeWeekId, yw1);
        expect(b.availableWeekIds, [xpw(1), yw1]);
      },
    );

    test('only live plans have their work rescued', () {
      final out = prep(
        deleted(
          plans: [plan0(planA), plan0(planB, deleted: tDelete)],
          progress: [
            progress0(planA, yw1, [yw1]),
            progress0(planB, xw1, [xw1], deleted: tDelete),
          ],
          sessions: [session0('gone', planB, xw1, 1, deleted: tDelete)],
        ),
      );
      expect(out.blocks.map((b) => b.id), isNot(contains(xPrime)));
    });

    test('running again changes nothing', () {
      final once = prep(
        deleted(
          progress: [
            progress0(planA, xw2, [xw1, xw2]),
          ],
          sessions: [
            session0('s1', planA, xw1, 1, nextWeekId: xw2),
            session0('s2', planA, xw2, 2, completed: false),
          ],
        ),
      );
      final twice = prep(once);
      expect(dump(twice), dump(once));
      expect(dump(prep(twice)), dump(once));
    });

    test('two replicas rescuing the same block produce identical rows', () {
      TrainingBlockGraph replica(bool dirtyLocal, DateTime createdAt) => prep(
        deleted(
          progress: [
            progress0(planA, xw2, [xw1, xw2]),
          ],
          sessions: [
            session0(
              'mine-${dirtyLocal ? 1 : 2}',
              planA,
              xw1,
              1,
              nextWeekId: xw2,
            ),
          ],
        ),
      );
      final a = replica(true, t0);
      final b = replica(false, t0.add(const Duration(days: 9)));
      String rows(TrainingBlockGraph g) => jsonEncode([
        for (final blk in g.blocks.where((b) => b.id == xPrime)) blk.toJson(),
        for (final w in g.weeks.where((w) => w.blockId == xPrime)) w.toJson(),
      ]);
      expect(rows(a), rows(b));
      expect(rows(a), contains(xPrime));
      expect(
        rescuedTrainingBlockId(x),
        rescuedTrainingBlockId(x.toUpperCase()),
      );
    });

    test('a rescued id that is itself deleted derives the next one', () {
      final second = rescuedTrainingBlockId(xPrime);
      final out = prep(
        deleted(
          progress: [
            progress0(planA, xw2, [xw2]),
          ],
          extraBlocks: [block0(xPrime, deleted: tDelete, position: 0)],
          extraWeeks: [week0(xpw(2), xPrime, 2, deleted: tDelete)],
        ),
      );
      expect(out.blocks.singleWhere((b) => b.id == second).deletedAt, isNull);
      expect(
        out.blocks.singleWhere((b) => b.id == xPrime).deletedAt,
        isNotNull,
      );
      expect(
        out.progress.single.activeWeekId,
        lazyTrainingWeekId(splitId, second, 2),
      );
    });

    test('work in an already deleted successor moves on in the same run', () {
      final second = rescuedTrainingBlockId(xPrime);
      final out = prep(
        deleted(
          progress: [
            progress0(planA, xpw(1), [xpw(1)]),
          ],
          sessions: [session0('s1', planA, xw1, 1)],
          extraBlocks: [block0(xPrime, deleted: tDelete)],
          extraWeeks: [week0(xpw(1), xPrime, 1, deleted: tDelete)],
        ),
      );
      final target = lazyTrainingWeekId(splitId, second, 1);
      expect(out.progress.single.activeWeekId, target);
      expect(out.sessions.single.trainingWeekId, target);
      expect(out.blocks.where((b) => b.deletedAt == null && b.dirty == true), [
        isA<TrainingBlock>().having((b) => b.id, 'id', second),
      ]);
    });

    test('a partly persisted rescue is completed without duplicates', () {
      final out = prep(
        deleted(
          progress: [
            progress0(planA, xw2, [xw1, xw2]),
          ],
          extraBlocks: [block0(xPrime, count: 4)],
          extraWeeks: [week0(xpw(1), xPrime, 1)],
        ),
      );
      expect(out.blocks.where((b) => b.id == xPrime), hasLength(1));
      expect(out.weeks.where((w) => w.blockId == xPrime).map((w) => w.number), [
        1,
        2,
      ]);
      expect(out.progress.single.availableWeekIds, [xpw(1), xpw(2)]);
    });

    test('an unsent live week of the deleted block is still cascaded', () {
      final out = prep(
        deleted(
          xWeeksTombstoned: false,
          progress: [
            progress0(planA, xw1, [xw1]),
          ],
        ),
      );
      for (final w in out.weeks.where((w) => w.blockId == x)) {
        expect(w.deletedAt, isNotNull);
      }
      expect(out.progress.single.deletedAt, isNull);
      expect(out.progress.single.activeWeekId, xpw(1));
    });

    test('Clear All Data and a deleted split rescue nothing', () {
      final live = graph0(
        blocks: [block0(x), block0(y, position: 1)],
        weeks: [week0(xw1, x, 1), week0(yw1, y, 1)],
        progress: [
          progress0(planA, xw1, [xw1]),
        ],
        sessions: [session0('s1', planA, xw1, 1)],
      );
      final cleared = prep(live.clearWorkouts());
      expect(cleared.blocks.map((b) => b.id), isNot(contains(xPrime)));
      expect(cleared.sessions.single.deletedAt, isNotNull);
      expect(cleared.progress.single.deletedAt, isNotNull);
      expect(cleared.blocks.where((b) => b.deletedAt == null), hasLength(1));
      final byParent = prep(
        graph0(
          splits: [split0(splitId, tDelete)],
          blocks: [block0(x, deleted: tDelete)],
          weeks: [week0(xw1, x, 1, deleted: tDelete)],
          plans: [plan0(planA, deleted: tDelete)],
          progress: [
            progress0(planA, xw1, [xw1], deleted: tDelete),
          ],
        ),
      );
      expect(byParent.blocks.single.id, x);
    });

    test('the legacy deterministic block is rescued like any other', () {
      final legacy = legacyTrainingBlockId(splitId);
      final legacyWeek = legacyTrainingWeekId(splitId, 1);
      final out = prep(
        graph0(
          blocks: [block0(legacy, deleted: tDelete), block0(y, position: 1)],
          weeks: [
            week0(legacyWeek, legacy, 1, deleted: tDelete),
            week0(yw1, y, 1),
          ],
          progress: [
            progress0(planA, legacyWeek, [legacyWeek]),
          ],
        ),
      );
      final rescued = rescuedTrainingBlockId(legacy);
      expect(out.blocks.singleWhere((b) => b.id == rescued).deletedAt, isNull);
      expect(
        out.progress.single.activeWeekId,
        lazyTrainingWeekId(splitId, rescued, 1),
      );
    });

    test('split-scoped: another split is untouched', () {
      const other = '99999999-9999-4999-8999-999999999999';
      final ox = lazyTrainingWeekId(other, 'o-block', 1);
      final g = deleted(
        progress: [
          progress0(planA, xw1, [xw1]),
        ],
        extraBlocks: [block0('o-block', sid: other)],
        extraWeeks: [week0(ox, 'o-block', 1, sid: other)],
      ).copyWith(
        splits: [split0(), split0(other)],
        plans: [plan0(planA), plan0('plan-o', sid: other)],
        progress: [
          progress0(planA, xw1, [xw1]),
          progress0('plan-o', ox, [ox], sid: other),
        ],
      );
      final out = prep(g);
      expect(
        out.progress.singleWhere((p) => p.planId == 'plan-o').dirty,
        isFalse,
      );
      expect(out.blocks.where((b) => b.splitId == other), hasLength(1));
    });

    test(
      'heal raises a count below the highest live week and keeps the clock',
      () {
        final g = graph0(
          blocks: [block0(y, count: 4, durationClock: clock)],
          weeks: [
            for (var n = 1; n <= 5; n++)
              week0(lazyTrainingWeekId(splitId, y, n), y, n),
          ],
          progress: [
            progress0(planA, lazyTrainingWeekId(splitId, y, 5), [
              for (var n = 1; n <= 5; n++) lazyTrainingWeekId(splitId, y, n),
            ]),
          ],
        );
        final out = prep(g);
        final b = out.blocks.single;
        expect(b.plannedWeekCount, 5);
        expect(b.plannedWeekCountUpdatedAt, clock);
        expect(b.updatedAt, t0);
        expect(b.dirty, isTrue);
        expect(dump(prep(out)), dump(out));
      },
    );

    test('heal leaves healthy, deleted and unknown counts alone', () {
      final healthy = graph0(
        blocks: [block0(y, count: 5, durationClock: clock)],
        weeks: [
          week0(yw1, y, 1),
          week0(lazyTrainingWeekId(splitId, y, 5), y, 5),
          // A tombstoned later week never raises the count.
          week0(lazyTrainingWeekId(splitId, y, 9), y, 9, deleted: tDelete),
        ],
        progress: [
          progress0(planA, yw1, [yw1]),
        ],
      );
      final out = prep(healthy);
      expect(out.blocks.single.plannedWeekCount, 5);
      expect(out.blocks.single.dirty, isFalse);
      expect(dump(out), dump(healthy));
    });

    test('a null count is still normalised from the allocated weeks', () {
      final g = graph0(
        blocks: [
          TrainingBlock(
            id: y,
            splitId: splitId,
            name: 'Block',
            position: 0,
            createdAt: t0,
            userId: u,
            updatedAt: t0,
            dirty: false,
          ),
        ],
        weeks: [
          week0(yw1, y, 1),
          week0(lazyTrainingWeekId(splitId, y, 3), y, 3),
        ],
        progress: [
          progress0(planA, yw1, [yw1]),
        ],
      );
      final b = prep(g).blocks.single;
      expect(b.plannedWeekCount, 3);
      expect(b.plannedWeekCountUpdatedAt, isNull);
    });

    // F2: a live session is rescued whatever its plan's state.
    test('a live session of a deleted plan is rescued, not cascaded', () {
      final out = prep(
        deleted(
          plans: [plan0(planA), plan0(planB, deleted: tDelete)],
          progress: [
            progress0(planA, yw1, [yw1]),
            progress0(planB, xw1, [xw1], deleted: tDelete),
          ],
          sessions: [
            session0('history', planB, xw2, 2),
            session0('orphan', 'no-such-plan-needed', xw1, 1),
          ],
        ),
      );
      final history = out.sessions.singleWhere((s) => s.id == 'history');
      expect(history.deletedAt, isNull);
      expect(history.trainingWeekId, xpw(2));
      expect(history.dirty, isTrue);
      expect(history.updatedAt, t0);
      expect(out.blocks.singleWhere((b) => b.id == xPrime).deletedAt, isNull);
      // The deleted plan's progress stays deleted.
      expect(
        out.progress.singleWhere((p) => p.planId == planB).deletedAt,
        isNotNull,
      );
      expect(dump(prep(out)), dump(out));
    });

    test('a live session with no plan at all is rescued', () {
      final s = session0('planless', planA, xw1, 1).copyWith(planId: null);
      final out = prep(deleted(sessions: [s]));
      expect(out.sessions.single.deletedAt, isNull);
      expect(out.sessions.single.trainingWeekId, xpw(1));
    });

    test('a tombstoned session is not live work and rescues nothing', () {
      final out = prep(
        deleted(sessions: [session0('gone', planA, xw1, 1, deleted: tDelete)]),
      );
      expect(out.blocks.map((b) => b.id), isNot(contains(xPrime)));
      expect(out.sessions.single.deletedAt, tDelete);
    });

    // F1: a rescued progress row has to win last-write-wins on the server.
    test('a rescued progress row gets a new revision and a time one '
        'millisecond after its own, the same on every replica, never the '
        'bootstrap revision and never the deletion\'s time', () {
      final late = tDelete.add(const Duration(hours: 5));
      final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      for (final updated in [t0, late, null]) {
        final row = progress0(planA, xw2, [xw1, xw2]).copyWith(
          updatedAt: updated,
          revision: initialProgressRevision(splitId, planA),
        );
        final first = prep(deleted(progress: [row])).progress.single;
        final second = prep(deleted(progress: [row])).progress.single;
        expect(first.revision, second.revision);
        expect(first.updatedAt, second.updatedAt);
        expect(first.revision, isNot(row.revision));
        expect(first.revision, isNot(initialProgressRevision(splitId, planA)));
        expect(
          first.updatedAt,
          (updated ?? epoch).add(const Duration(milliseconds: 1)),
        );
        expect(first.updatedAt!.isAfter(updated ?? epoch), isTrue);
      }
    });

    test('R1: a deleting device\'s clock never reaches a rescued row, and '
        'two versions of a row keep their order after the rescue', () {
      final ahead = DateTime.utc(2030);
      final blockAhead = deleted().copyWith(
        blocks: [
          block0(x, deleted: ahead, durationClock: clock, name: 'Bulk'),
          block0(y, position: 1),
        ],
      );
      final older = progress0(planA, xw2, [
        xw1,
        xw2,
      ]).copyWith(updatedAt: t0, revision: 'rev-old');
      final newer = older.copyWith(
        updatedAt: t0.add(const Duration(days: 3)),
        revision: 'rev-new',
      );
      final a = prep(blockAhead.copyWith(progress: [older])).progress.single;
      final b = prep(blockAhead.copyWith(progress: [newer])).progress.single;
      expect(a.updatedAt, t0.add(const Duration(milliseconds: 1)));
      expect(
        b.updatedAt,
        newer.updatedAt!.add(const Duration(milliseconds: 1)),
      );
      expect(b.updatedAt!.isAfter(a.updatedAt!), isTrue);
      expect(a.updatedAt!.isBefore(ahead), isTrue);
    });

    test(
      'a progress row only listing the block keeps its revision and time',
      () {
        final out = prep(
          deleted(
            plans: [plan0(planA), plan0(planB)],
            progress: [
              progress0(planA, xw2, [xw2]),
              progress0(planB, yw1, [xw1, yw1]),
            ],
          ),
        );
        final b = out.progress.singleWhere((p) => p.planId == planB);
        expect(b.revision, 'rev-$planB');
        expect(b.updatedAt, t0);
      },
    );

    // F8: mapping by week id, and rescue is never the reason this throws.
    group('rescue never makes preparation fail', () {
      final xw2dup = lazyTrainingWeekId(splitId, 'dup-source', 2);

      TrainingBlockGraph duplicateWeekGraph({
        required List<WorkoutSession> sessions,
        List<WorkoutProgress>? progress,
      }) => deleted(
        sessions: sessions,
        progress: progress,
        extraWeeks: [week0(xw2dup, x, 2, deleted: null)],
      );

      test('two week rows of one number, one tombstoned and one live, share '
          'a target without collapsing a completion', () {
        final out = prep(
          duplicateWeekGraph(
            sessions: [
              session0('a', planA, xw1, 1, nextWeekId: xw2),
              session0('b', planA, xw2dup, 2),
            ],
            progress: [
              progress0(planA, xw2dup, [xw1, xw2, xw2dup]),
            ],
          ),
        );
        for (final s in out.sessions) {
          expect(s.deletedAt, isNull, reason: s.id);
        }
        final a = out.sessions.singleWhere((s) => s.id == 'a');
        expect(a.completionTransition!['sourceWeekId'], xpw(1));
        expect(a.completionTransition!['nextWeekId'], xpw(2));
        expect(
          out.sessions.singleWhere((s) => s.id == 'b').trainingWeekId,
          xpw(2),
        );
        expect(out.progress.single.availableWeekIds, [xpw(1), xpw(2)]);
        expect(
          out.weeks.where((w) => w.blockId == xPrime && w.deletedAt == null),
          hasLength(2),
        );
      });

      test('a completion between two weeks of the same number cannot be '
          'rescued: the block is left exactly as without rescue', () {
        final g = duplicateWeekGraph(
          sessions: [session0('c', planA, xw2, 2, nextWeekId: xw2dup)],
          progress: [
            progress0(planA, yw1, [yw1]),
          ],
        );
        // Rescuing it would map both weeks onto one and invalidate the
        // evidence; the block is left as the cascade alone treats it.
        final out = prep(g);
        expect(
          dump(out),
          dump(TrainingBlockMigration.prepareGraphWithoutRescue(g)),
        );
        expect(out.blocks.map((b) => b.id), isNot(contains(xPrime)));
        expect(out.sessions.single.deletedAt, isNotNull);
      });

      test(
        'sixteen unusable derivations leave the block as without rescue',
        () {
          var id = x;
          final chain = <TrainingBlock>[];
          for (var i = 0; i < 17; i++) {
            id = rescuedTrainingBlockId(id);
            chain.add(block0(id, deleted: tDelete, position: 5 + i));
          }
          final g = deleted(
            sessions: [session0('s', planA, xw1, 1)],
            extraBlocks: chain,
          );
          final out = prep(g);
          expect(out.sessions.single.deletedAt, isNotNull);
          expect(
            dump(out),
            dump(TrainingBlockMigration.prepareGraphWithoutRescue(g)),
          );
        },
      );

      test('a successor id held by another split is not used', () {
        final g = deleted(
          sessions: [session0('s', planA, xw1, 1)],
          extraBlocks: [block0(xPrime, sid: 'other-split')],
          extraWeeks: [
            week0(
              lazyTrainingWeekId('other-split', xPrime, 1),
              xPrime,
              1,
              sid: 'other-split',
            ),
          ],
        ).copyWith(splits: [split0(), split0('other-split')]);
        final out = prep(g);
        final s = out.sessions.single;
        expect(s.deletedAt, isNull);
        final home = out.weeks.singleWhere((w) => w.id == s.trainingWeekId);
        expect(home.splitId, splitId);
        expect(
          out.blocks.singleWhere((b) => b.id == home.blockId).splitId,
          splitId,
        );
      });
    });

    // R3: every block is rescued or skipped on its own, and every skip is
    // logged. A block whose rescue breaks validation is the only one left to
    // the older cascade.
    group('rescue is isolated per block and every skip is visible', () {
      const z = 'block-z';
      final zw1 = lazyTrainingWeekId(splitId, z, 1);
      final zPrime = rescuedTrainingBlockId(z);

      TrainingBlockGraph twoBlocks() => deleted(
        sessions: [
          session0('sx', planA, xw1, 1),
          session0('sz', planA, zw1, 1),
        ],
        extraBlocks: [block0(z, deleted: tDelete, position: 2)],
        extraWeeks: [week0(zw1, z, 1, deleted: tDelete)],
      );

      late List<String> logs;
      late DebugPrintCallback savedPrint;
      var validations = 0;
      setUp(() {
        logs = [];
        validations = 0;
        savedPrint = debugPrint;
        debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      });
      tearDown(() {
        debugPrint = savedPrint;
        TrainingBlockMigration.extraValidationForTesting = null;
      });

      test('without a failure both blocks are rescued, nothing is logged '
          'and the graph is prepared once', () {
        TrainingBlockMigration.extraValidationForTesting = (_) => validations++;
        final r = TrainingBlockMigration.prepareGraphReporting(twoBlocks());
        expect(r.report.rescued, unorderedEquals([x, z]));
        expect(r.report.skipped, isEmpty);
        expect(r.report.fallbacks, 0);
        expect(logs, isEmpty);
        expect(validations, 1);
        for (final s in r.graph.sessions) {
          expect(s.deletedAt, isNull, reason: s.id);
        }
      });

      test('with nothing deleted the graph is prepared once and nothing is '
          'logged', () {
        TrainingBlockMigration.extraValidationForTesting = (_) => validations++;
        final g = graph0(
          blocks: [block0(x), block0(y, position: 1)],
          weeks: [week0(xw1, x, 1), week0(yw1, y, 1)],
          progress: [
            progress0(planA, xw1, [xw1]),
          ],
        );
        final r = TrainingBlockMigration.prepareGraphReporting(g);
        expect(r.report.rescued, isEmpty);
        expect(r.report.skipped, isEmpty);
        expect(validations, 1);
        expect(logs, isEmpty);
      });

      test('a block whose rescue breaks validation is skipped and logged; the '
          'other one stays rescued', () {
        TrainingBlockMigration.extraValidationForTesting = (g) {
          validations++;
          if (g.blocks.any((b) => b.id == zPrime && b.deletedAt == null)) {
            throw const FormatException('injected');
          }
        };
        final g = twoBlocks();
        final r = TrainingBlockMigration.prepareGraphReporting(g);
        expect(r.report.rescued, [x]);
        expect(r.report.skipped.keys, [z]);
        expect(r.report.skipped[z], contains('does not validate'));
        expect(r.report.fallbacks, 1);
        final sx = r.graph.sessions.singleWhere((s) => s.id == 'sx');
        final sz = r.graph.sessions.singleWhere((s) => s.id == 'sz');
        expect(sx.deletedAt, isNull);
        expect(sx.trainingWeekId, xpw(1));
        // Z follows the older cascade.
        expect(sz.deletedAt, isNotNull);
        expect(r.graph.blocks.map((b) => b.id), isNot(contains(zPrime)));
        // Every skip is logged with the block id and a reason, no user data.
        final skipLogs = logs.where((l) => l.contains('skipped')).toList();
        expect(skipLogs, hasLength(1));
        expect(skipLogs.single, contains(z));
        expect(skipLogs.single, isNot(contains(planA)));
        expect(logs.any((l) => l.contains('one at a time')), isTrue);
        // Pure and idempotent.
        expect(dump(prep(r.graph)), dump(r.graph));
        validations = 0;
        final again = TrainingBlockMigration.prepareGraphReporting(g);
        expect(dump(again.graph), dump(r.graph));
      });

      test('when every rescue fails the result is the pre-rescue graph', () {
        TrainingBlockMigration.extraValidationForTesting = (g) {
          if (g.blocks.any(
            (b) => b.deletedAt == null && b.id != y && b.id != 'b9',
          )) {
            throw const FormatException('injected');
          }
        };
        final g = twoBlocks();
        final r = TrainingBlockMigration.prepareGraphReporting(g);
        expect(r.report.rescued, isEmpty);
        expect(r.report.skipped.keys, unorderedEquals([x, z]));
        expect(
          dump(r.graph),
          dump(TrainingBlockMigration.prepareGraphWithoutRescue(g)),
        );
        expect(logs.where((l) => l.contains('skipped')), hasLength(2));
      });

      test('a graph the pre-rescue path rejects is rejected, and no block '
          'is blamed', () {
        TrainingBlockMigration.extraValidationForTesting =
            (_) => throw const FormatException('always');
        expect(
          () => TrainingBlockMigration.prepareGraph(twoBlocks()),
          throwsFormatException,
        );
        expect(logs.where((l) => l.contains('skipped')), isEmpty);
      });

      test('a skip decided inside the rescue is reported and logged too', () {
        // A completion between two weeks of one number cannot be relinked.
        final xw2dup = lazyTrainingWeekId(splitId, 'dup-source', 2);
        final g = deleted(
          sessions: [session0('c', planA, xw2, 2, nextWeekId: xw2dup)],
          extraWeeks: [week0(xw2dup, x, 2, deleted: null)],
        );
        final r = TrainingBlockMigration.prepareGraphReporting(g);
        expect(r.report.rescued, isEmpty);
        expect(r.report.skipped.keys, [x]);
        expect(r.report.fallbacks, 0);
        final line = logs.singleWhere((l) => l.contains('skipped'));
        expect(line, contains(x));
        expect(line, contains('relinked'));
      });
    });

    // Random graphs. A well-formed graph has distinct week numbers in each
    // block and evidence between different weeks; the malformed generator
    // breaks that on purpose, which makes some rescues skip.
    ({TrainingBlockGraph g, bool splitDeleted})? generate(
      int seed, {
      required bool wellFormed,
    }) {
      final blockIds = ['b0', 'b1', 'b2', 'b3'];
      final r = Random(seed);
      T pick<T>(List<T> items) => items[r.nextInt(items.length)];
      bool chance(double p) => r.nextDouble() < p;
      final splitDeleted = chance(0.1);
      final plans = [
        plan0(planA),
        if (chance(0.7)) plan0(planB, deleted: chance(0.5) ? tDelete : null),
      ];
      // Blocks, some tombstoned, some holding a derived rescue id so that
      // derivations collide.
      final blocks = <TrainingBlock>[];
      final ids = <String>{};
      for (var i = 0; i < 1 + r.nextInt(3); i++) {
        final id =
            i == 0 || !chance(0.25)
                ? blockIds[i]
                : rescuedTrainingBlockId(blockIds[i - 1]);
        if (!ids.add(id)) continue;
        blocks.add(
          block0(
            id,
            position: i,
            count: 1 + r.nextInt(4),
            deleted: chance(0.5) ? tDelete : null,
          ),
        );
      }
      if (chance(0.2) && blocks.any((b) => b.deletedAt != null)) {
        final id = rescuedTrainingBlockId(
          rescuedTrainingBlockId(blocks.first.id),
        );
        if (ids.add(id)) {
          blocks.add(block0(id, position: 9, deleted: tDelete));
        }
      }
      if (blocks.every((b) => b.deletedAt != null) && chance(0.8)) {
        blocks.add(block0('b9', position: 8));
      }
      final weeks = <TrainingWeek>[];
      for (final b in blocks) {
        final count = r.nextInt(4);
        final numbers = [1, 2, 3]..shuffle(r);
        for (var k = 0; k < count; k++) {
          final n =
              wellFormed ? numbers[k] : 1 + (chance(0.3) ? 0 : r.nextInt(3));
          final id =
              chance(0.5)
                  ? lazyTrainingWeekId(splitId, b.id, n)
                  : '${b.id}-w$k-$n';
          if (weeks.any((w) => w.id == id)) continue;
          weeks.add(
            week0(
              id,
              b.id,
              n,
              // Weeks only go with their block, unless the graph is malformed.
              deleted:
                  b.deletedAt != null || (!wellFormed && chance(0.3))
                      ? tDelete
                      : null,
            ),
          );
        }
      }
      if (weeks.isEmpty) return null;
      final sessions = <WorkoutSession>[];
      for (var i = 0; i < r.nextInt(5); i++) {
        final w = pick(weeks);
        final planChoice = r.nextInt(4);
        final plan = planChoice == 0 ? null : (planChoice == 1 ? planB : planA);
        final sameBlock =
            weeks
                .where(
                  (o) =>
                      o.blockId == w.blockId &&
                      o.id != w.id &&
                      (!wellFormed || o.number != w.number),
                )
                .toList();
        final evidenceNext =
            sameBlock.isNotEmpty && chance(0.5) ? pick(sameBlock) : null;
        var session = session0(
          's$i',
          plan ?? planA,
          w.id,
          w.number,
          nextWeekId: evidenceNext?.id,
          completed: evidenceNext != null || chance(0.5),
          deleted: chance(0.2) ? tDelete : null,
        );
        if (plan == null) session = session.copyWith(planId: null);
        sessions.add(session);
      }
      final progress = <WorkoutProgress>[];
      for (final plan in plans) {
        if (chance(0.15)) continue;
        final active = pick(weeks);
        final available =
            {
              active.id,
              for (final w in weeks)
                if (chance(0.3)) w.id,
            }.toList();
        progress.add(
          progress0(
            plan.id!,
            active.id,
            available,
            deleted: plan.deletedAt != null || chance(0.15) ? tDelete : null,
          ),
        );
      }
      return (
        g: graph0(
          splits: [split0(splitId, splitDeleted ? tDelete : null)],
          plans: plans,
          blocks: blocks,
          weeks: weeks,
          sessions: sessions,
          progress: progress,
        ),
        splitDeleted: splitDeleted,
      );
    }

    bool acceptedAsInput(TrainingBlockGraph g) {
      try {
        g.validate(
          allowLegacyLinks: true,
          allowLiveChildrenOfDeletedParents: true,
        );
        return true;
      } catch (_) {
        return false;
      }
    }

    /// Deleted blocks of a live split which a live session or the active week
    /// of live progress of a live plan points into.
    List<String> referencedBlocks(TrainingBlockGraph g, bool splitDeleted) => [
      if (!splitDeleted)
        for (final b in g.blocks)
          if (b.deletedAt != null)
            if (() {
              final ids = {
                for (final w in g.weeks)
                  if (w.blockId == b.id) w.id,
              };
              return g.sessions.any(
                    (s) =>
                        s.deletedAt == null &&
                        (ids.contains(s.trainingWeekId) ||
                            ids.contains(
                              s.completionTransition?['sourceWeekId'],
                            ) ||
                            ids.contains(
                              s.completionTransition?['nextWeekId'],
                            )),
                  ) ||
                  g.progress.any(
                    (p) =>
                        p.deletedAt == null &&
                        g.plans.any(
                          (pl) => pl.id == p.planId && pl.deletedAt == null,
                        ) &&
                        ids.contains(p.activeWeekId),
                  );
            }())
              b.id,
    ];

    void fuzz({required bool wellFormed}) {
      var generated = 0;
      var inputAccepted = 0;
      var accepted = 0;
      var referencedGraphs = 0;
      var rescues = 0;
      var skips = 0;
      var fallbacks = 0;
      var thrownByBaseline = 0;
      var graphsWithSkips = 0;
      for (var seed = 0; seed < 600; seed++) {
        final made = generate(seed, wellFormed: wellFormed);
        if (made == null) continue;
        generated++;
        final g = made.g;
        if (acceptedAsInput(g)) inputAccepted++;
        final reason = 'seed $seed';
        String baseline;
        try {
          baseline = dump(TrainingBlockMigration.prepareGraphWithoutRescue(g));
        } catch (e) {
          baseline = 'throws $e';
          thrownByBaseline++;
        }
        ({TrainingBlockGraph graph, BlockRescueReport report}) result;
        try {
          result = TrainingBlockMigration.prepareGraphReporting(g);
          result.graph.validate();
        } catch (e) {
          // Rescue is never the reason: the plain path throws the same way.
          expect('throws $e', baseline, reason: reason);
          continue;
        }
        accepted++;
        final out = result.graph;
        final report = result.report;
        final referenced = referencedBlocks(g, made.splitDeleted).toSet();
        if (referenced.isNotEmpty) referencedGraphs++;
        rescues += report.rescued.length;
        skips += report.skipped.length;
        fallbacks += report.fallbacks;
        if (report.skipped.isNotEmpty) graphsWithSkips++;
        // (i) No live session is tombstoned unless its block's rescue was
        // skipped (or its split was deleted, or only its own week was).
        final weekBlock = {for (final w in g.weeks) w.id: w.blockId};
        final blockById = {for (final b in g.blocks) b.id: b};
        for (final before in g.sessions.where((s) => s.deletedAt == null)) {
          final after = out.sessions.singleWhere((s) => s.id == before.id);
          if (after.deletedAt == null || made.splitDeleted) continue;
          final block = blockById[weekBlock[before.trainingWeekId]]!;
          expect(
            block.deletedAt == null || report.skipped.containsKey(block.id),
            isTrue,
            reason:
                '$reason: ${before.id} lost although block ${block.id} was '
                'not skipped',
          );
        }
        if (wellFormed) {
          // (ii) A well-formed graph never skips, never falls back, and every
          // referenced block is rescued.
          expect(report.skipped, isEmpty, reason: reason);
          expect(report.fallbacks, 0, reason: reason);
          expect(
            report.rescued.toSet().containsAll(referenced),
            isTrue,
            reason: '$reason: ${report.rescued} vs $referenced',
          );
        } else if (referenced.isEmpty) {
          expect(report.rescued, isEmpty, reason: reason);
        }
        if (referenced.isEmpty) expect(dump(out), baseline, reason: reason);
        // (iii) The result validates and a second run changes nothing.
        expect(out.validate, returnsNormally, reason: reason);
        final again = TrainingBlockMigration.prepareGraphReporting(out);
        expect(dump(again.graph), dump(out), reason: reason);
        expect(again.report.rescued, isEmpty, reason: reason);
      }
      // ignore: avoid_print
      print(
        '${wellFormed ? 'well-formed' : 'malformed'}: generated $generated, '
        'validator accepts the input $inputAccepted, prepared $accepted, with a tombstoned-but-referenced block '
        '$referencedGraphs, rescues $rescues, skips $skips (in '
        '$graphsWithSkips graphs), fallbacks $fallbacks, baseline throws '
        '$thrownByBaseline',
      );
      expect(referencedGraphs, greaterThan(20));
      expect(rescues, greaterThan(20));
      if (wellFormed) {
        expect(skips, 0);
        expect(fallbacks, 0);
      } else {
        expect(skips, greaterThan(0));
        expect(thrownByBaseline, greaterThan(0));
      }
    }

    test(
      'well-formed random graphs: every referenced block is rescued, '
      'none is skipped, no live workout is lost, results validate and a '
      'second run changes nothing',
      () => fuzz(wellFormed: true),
    );

    test(
      'malformed random graphs: rescue is never the reason preparation '
      'throws, skips happen only where expected, results validate and a '
      'second run changes nothing',
      () => fuzz(wellFormed: false),
    );
  });
}
