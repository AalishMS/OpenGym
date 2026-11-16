import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/training_block_lifecycle.dart';
import 'package:gymapp/utils/training_block_identity.dart';

final DateTime t0 = DateTime.utc(2026, 1, 1);
final DateTime t1 = DateTime.utc(2026, 2, 1);
final DateTime t2 = DateTime.utc(2026, 3, 1);

TrainingBlock block(String id, {String split = 's', int count = 6}) =>
    TrainingBlock(
      id: id,
      splitId: split,
      name: id,
      position: 0,
      createdAt: t0,
      plannedWeekCount: count,
    );

TrainingWeek week(String id, String blockId, int n, {DateTime? deleted}) =>
    TrainingWeek(
      id: id,
      splitId: 's',
      blockId: blockId,
      number: n,
      createdAt: t0,
      deletedAt: deleted,
    );

WorkoutProgress progress(
  String active,
  List<String> available, {
  DateTime? deleted,
}) => WorkoutProgress(
  id: 'p-$active',
  splitId: 's',
  planId: 'plan',
  activeWeekId: active,
  availableWeekIds: available,
  state: WorkoutProgressState.ready,
  revision: 'r',
  deletedAt: deleted,
);

WorkoutSession session(
  String id,
  String weekId, {
  DateTime? deleted,
  bool completed = true,
  String? next,
  String plan = 'plan',
}) => WorkoutSession(
  id: id,
  date: t0,
  planName: 'Push',
  planId: plan,
  splitId: 's',
  trainingWeekId: weekId,
  isCompleted: completed,
  deletedAt: deleted,
  exercises: [],
  completionTransition:
      next == null
          ? null
          : {
            'expectedRevision': 'r',
            'sourceWeekId': weekId,
            'nextWeekId': next,
            'resultRevision': id,
            'committedAt': t0.toIso8601String(),
          },
);

void main() {
  final TrainingBlock a = block('a');
  final TrainingBlock b = block('b');
  final List<TrainingWeek> weeks = [
    week('a1', 'a', 1),
    week('a2', 'a', 2),
    week('a3', 'a', 3),
    week('a5', 'a', 5, deleted: t1),
    week('b1', 'b', 1),
    week('b4', 'b', 4),
  ];

  group('minimumBlockWeekCount', () {
    int floor({
      Iterable<TrainingWeek>? w,
      Iterable<WorkoutProgress> p = const [],
      Iterable<WorkoutSession> s = const [],
      TrainingBlock? of,
    }) => minimumBlockWeekCount(
      of ?? a,
      weeks: w ?? weeks,
      progress: p,
      sessions: s,
    );

    test('is the highest live week row, tombstones ignored', () {
      expect(floor(), 3);
      expect(floor(of: b), 4);
    });

    test('is never below one, even with no rows', () {
      expect(floor(w: const []), 1);
      expect(floor(w: [week('a5', 'a', 5, deleted: t1)]), 1);
    });

    test('counts the active and every available week of live progress', () {
      expect(
        floor(
          w: [week('a1', 'a', 1)],
          p: [
            progress('b1', ['b1']),
          ],
        ),
        1,
      );
      expect(
        floor(
          w: [...weeks, week('a4', 'a', 4)]
            ..removeWhere((x) => x.id == 'a4' || x.id == 'a3' || x.id == 'a2'),
          p: [
            progress('a1', ['a1', 'a5']),
          ],
        ),
        5,
      );
      expect(
        floor(
          p: [
            progress('a5', ['a5']),
          ],
        ),
        5,
      );
    });

    test('counts weeks live sessions sit in, whatever their state', () {
      for (final done in [true, false]) {
        expect(floor(s: [session('x', 'a5', completed: done)]), 5);
      }
    });

    test('counts weeks named by completion evidence', () {
      expect(floor(s: [session('x', 'a1', next: 'a5')]), 5);
    });

    test('ignores tombstoned progress and sessions', () {
      expect(
        floor(
          p: [
            progress('a5', ['a5'], deleted: t1),
          ],
          s: [session('x', 'a5', deleted: t1)],
        ),
        3,
      );
    });

    test('ignores references into other blocks', () {
      expect(
        floor(
          p: [
            progress('b4', ['b4']),
          ],
          s: [session('x', 'b4')],
        ),
        3,
      );
    });
  });

  group('blockDeletionBlocker', () {
    BlockDeletionBlocker? blocker({
      TrainingBlock? target,
      List<TrainingBlock>? blocks,
      List<TrainingWeek>? w,
      List<WorkoutProgress> p = const [],
      List<WorkoutSession> s = const [],
    }) => blockDeletionBlocker(
      target ?? a,
      blocks: blocks ?? [a, b],
      weeks: w ?? weeks,
      progress: p,
      sessions: s,
    );

    test('an empty block of a split with another block can be deleted', () {
      expect(blocker(), isNull);
    });

    test('the last live block is kept', () {
      expect(blocker(blocks: [a]), BlockDeletionBlocker.lastBlock);
      expect(
        blocker(blocks: [a, block('b', count: 1)..deletedAt = t1]),
        BlockDeletionBlocker.lastBlock,
      );
      expect(
        blocker(blocks: [a, block('c', split: 'other')]),
        BlockDeletionBlocker.lastBlock,
      );
    });

    test('a live session in any week blocks, in every state', () {
      for (final done in [true, false]) {
        for (final week in ['a1', 'a5']) {
          // a5 is a tombstoned week row: a live session in it still counts.
          expect(
            blocker(s: [session('x', week, completed: done)]),
            BlockDeletionBlocker.hasWorkouts,
          );
        }
      }
      // A session of a deleted plan (orphan) counts too.
      expect(
        blocker(s: [session('x', 'a2', plan: 'deleted-plan')]),
        BlockDeletionBlocker.hasWorkouts,
      );
    });

    test('a tombstoned session does not block', () {
      expect(blocker(s: [session('x', 'a1', deleted: t1)]), isNull);
    });

    test('live progress on an active week blocks, even at the last week', () {
      expect(
        blocker(
          p: [
            progress('a3', ['a3']),
          ],
        ),
        BlockDeletionBlocker.workoutInBlock,
      );
    });

    test('available weeks and empty week rows do not block', () {
      expect(
        blocker(
          p: [
            progress('b1', ['a1', 'b1']),
          ],
        ),
        isNull,
      );
      expect(
        blocker(
          p: [
            progress('a1', ['a1'], deleted: t1),
          ],
        ),
        isNull,
      );
    });

    test('the deterministic legacy block is an ordinary block', () {
      final legacy = block(legacyTrainingBlockId('s'));
      expect(
        blocker(target: legacy, blocks: [legacy, b], w: [weeks.first]),
        isNull,
      );
    });

    test('sessions win over progress in the reported reason', () {
      expect(
        blocker(
          s: [session('x', 'a1')],
          p: [
            progress('a1', ['a1']),
          ],
        ),
        BlockDeletionBlocker.hasWorkouts,
      );
    });
  });

  group('mergeBlockDuration', () {
    BlockDuration d(int? count, DateTime? at) => (count: count, changedAt: at);

    test('the newer clock wins, even with a smaller count', () {
      expect(mergeBlockDuration(d(6, t1), d(4, t2)), d(4, t2));
      expect(mergeBlockDuration(d(4, t2), d(6, t1)), d(4, t2));
    });

    test('a tie keeps the larger count, including null against null', () {
      expect(mergeBlockDuration(d(6, t1), d(4, t1)), d(6, t1));
      expect(mergeBlockDuration(d(4, t1), d(6, t1)), d(6, t1));
      expect(mergeBlockDuration(d(4, null), d(6, null)), d(6, null));
    });

    test('a clock beats no clock, and no clock never beats a clock', () {
      expect(mergeBlockDuration(d(4, t1), d(6, null)), d(4, t1));
      expect(mergeBlockDuration(d(6, null), d(4, t1)), d(4, t1));
    });

    test('a null count never replaces a value', () {
      expect(mergeBlockDuration(d(5, t1), d(null, t2)), d(5, t1));
      expect(mergeBlockDuration(d(null, t2), d(5, t1)), d(5, t1));
      expect(mergeBlockDuration(d(null, t1), d(null, t2)).count, isNull);
    });

    test('is symmetric and idempotent', () {
      final values = [
        for (final c in [null, 2, 5])
          for (final at in [null, t0, t1, t2]) d(c, at),
      ];
      for (final x in values) {
        expect(mergeBlockDuration(x, x), x);
        for (final y in values) {
          final xy = mergeBlockDuration(x, y);
          final yx = mergeBlockDuration(y, x);
          expect(xy.count, yx.count, reason: '$x $y');
          expect(xy.changedAt, yx.changedAt, reason: '$x $y');
          expect(mergeBlockDuration(xy, y), xy);
          expect(mergeBlockDuration(xy, x), xy);
        }
      }
    });
  });

  group('copyWith and json', () {
    test('copyWith keeps the clock unless told otherwise', () {
      final base = block('a')..userId = null;
      final stamped = TrainingBlock(
        id: 'a',
        splitId: 's',
        name: 'a',
        position: 0,
        createdAt: t0,
        plannedWeekCount: 3,
        plannedWeekCountUpdatedAt: t1,
      );
      expect(stamped.copyWith(name: 'b').plannedWeekCountUpdatedAt, t1);
      expect(stamped.copyWith(position: 2).plannedWeekCountUpdatedAt, t1);
      expect(
        stamped.copyWith(plannedWeekCount: 5).plannedWeekCountUpdatedAt,
        t1,
      );
      expect(
        stamped
            .copyWith(plannedWeekCountUpdatedAt: t2)
            .plannedWeekCountUpdatedAt,
        t2,
      );
      expect(
        stamped
            .copyWith(plannedWeekCountUpdatedAt: null)
            .plannedWeekCountUpdatedAt,
        isNull,
      );
      expect(base.copyWith().plannedWeekCountUpdatedAt, isNull);
    });

    test('the clock round-trips through json; older json reads as null', () {
      final stamped = block('a').copyWith(plannedWeekCountUpdatedAt: t1);
      final back = TrainingBlock.fromJson(stamped.toJson());
      expect(back.plannedWeekCountUpdatedAt, t1);
      final legacy = stamped.toJson()..remove('plannedWeekCountUpdatedAt');
      expect(TrainingBlock.fromJson(legacy).plannedWeekCountUpdatedAt, isNull);
    });
  });

  test('rescued ids are stable, distinct and chainable', () {
    expect(rescuedTrainingBlockId('X'), rescuedTrainingBlockId('x'));
    expect(rescuedTrainingBlockId('x'), isNot('x'));
    expect(
      rescuedTrainingBlockId(rescuedTrainingBlockId('x')),
      isNot(rescuedTrainingBlockId('x')),
    );
    expect(rescuedTrainingBlockId('x'), isNot(rescuedTrainingBlockId('y')));
  });
}
