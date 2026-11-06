import 'dart:math';

import 'package:uuid/uuid.dart';

import '../data/exercise_library.dart';
import '../data/plan_colors.dart';
import '../models/exercise.dart';
import '../models/exercise_template.dart';
import '../models/set.dart';
import '../models/set_template.dart';
import '../models/training_block.dart';
import '../models/training_week.dart';
import '../models/workout_plan.dart';
import '../models/workout_progress.dart';
import '../models/workout_session.dart';
import '../utils/training_block_identity.dart';
import 'hive_service.dart';
import 'sync_service.dart';
import 'training_block_migration.dart';
import 'training_block_restore.dart';

/// One prescribed lift. [reps] is the Strength-block (current) target; earlier
/// blocks add their rep bonus. Loads follow `start + step * progressionStep`,
/// rounded to the equipment's [increment], so light lifts plateau for a week
/// or two the way dumbbell racks and cable stacks force them to.
class _Lift {
  final String name;
  final int sets;
  final int reps;
  final double start;
  final double step;
  final double increment;

  const _Lift(
    this.name,
    this.sets,
    this.reps,
    this.start,
    this.step,
    this.increment,
  );
}

class _PlanSpec {
  final String name;

  /// Day of the seven-day training week; [altDay] is the rest day it
  /// sometimes slides onto.
  final int day;
  final int? altDay;
  final int hour;
  final List<_Lift> lifts;

  const _PlanSpec(this.name, this.day, this.hour, this.lifts, {this.altDay});
}

class _BlockSpec {
  final String name;
  final int plannedWeeks;
  final int repBonus;
  final int firstStep;

  const _BlockSpec(this.name, this.plannedWeeks, this.repBonus, this.firstStep);

  /// Every sample block finishes with a deload in its planned final week.
  bool isDeload(int week) => week == plannedWeeks;
}

/// The generated training graph for one split, before it is merged into the
/// stored graph. Public so tests can check the dataset without storage.
class SampleDataset {
  final List<TrainingBlock> blocks;
  final List<TrainingWeek> weeks;
  final List<WorkoutPlan> plans;
  final List<WorkoutSession> sessions;
  final List<WorkoutProgress> progress;

  const SampleDataset({
    required this.blocks,
    required this.weeks,
    required this.plans,
    required this.sessions,
    required this.progress,
  });
}

class SampleDataSeeder {
  /// A five-day week: Push, Pull, Legs, rest, Upper, Full body, rest.
  static const _plans = [
    _PlanSpec('Push Day', 0, 18, [
      _Lift('Bench Press', 4, 5, 60, 2.5, 2.5),
      _Lift('Overhead Press', 3, 6, 37.5, 1.25, 1.25),
      _Lift('Incline Dumbbell Press', 3, 8, 22, 1, 2),
      _Lift('Lateral Raise', 3, 12, 8, 0.5, 1),
      _Lift('Tricep Pushdown', 3, 10, 25, 1.25, 2.5),
    ]),
    _PlanSpec('Pull Day', 1, 18, [
      _Lift('Deadlift', 3, 4, 110, 2.5, 2.5),
      _Lift('Lat Pulldown', 3, 8, 50, 1.25, 2.5),
      _Lift('Seated Cable Row', 3, 8, 45, 1.25, 2.5),
      _Lift('Face Pull', 3, 12, 15, 0.75, 2.5),
      _Lift('Bicep Curl', 3, 8, 10, 0.6, 2),
    ]),
    _PlanSpec('Leg Day', 2, 18, [
      _Lift('Squat', 4, 5, 80, 2.5, 2.5),
      _Lift('Romanian Deadlift', 3, 6, 70, 2.5, 2.5),
      _Lift('Leg Press', 3, 10, 140, 5, 5),
      _Lift('Leg Curl', 3, 10, 35, 1.25, 2.5),
      _Lift('Calf Raise', 4, 12, 60, 2.5, 5),
    ]),
    _PlanSpec('Upper Body', 4, 18, altDay: 3, [
      _Lift('Incline Bench Press', 4, 6, 50, 2.5, 2.5),
      _Lift('Barbell Row', 4, 6, 60, 2.5, 2.5),
      _Lift('Dumbbell Shoulder Press', 3, 8, 18, 0.75, 2),
      _Lift('Cable Fly', 3, 10, 12.5, 0.75, 2.5),
      _Lift('Hammer Curl', 3, 8, 12, 0.6, 2),
      _Lift('Overhead Tricep Extension', 3, 10, 20, 1, 2.5),
    ]),
    _PlanSpec('Full Body', 5, 10, altDay: 6, [
      _Lift('Front Squat', 3, 5, 60, 2.5, 2.5),
      _Lift('Dumbbell Press', 3, 8, 26, 1, 2),
      _Lift('Hip Thrust', 3, 8, 90, 5, 5),
      _Lift('T-Bar Row', 3, 8, 40, 2.5, 2.5),
      _Lift('Cable Ab Crunch', 3, 12, 30, 1.25, 2.5),
    ]),
  ];

  /// Rep bonuses fall as loads climb, so estimated 1RMs rise block on block.
  static const _blocks = [
    _BlockSpec('Foundation', 4, 3, 0),
    _BlockSpec('Hypertrophy', 5, 2, 2),
    _BlockSpec('Strength', 5, 0, 8),
  ];

  /// Calendar weeks, oldest first, as (block index, week number). `null` is a
  /// week off between blocks. The last entry is the current calendar week.
  static const _calendar = <(int, int)?>[
    (0, 1), (0, 2), (0, 3), (0, 4), //
    (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), //
    null,
    (2, 1), (2, 2), (2, 3),
  ];

  /// Today is the third day of the current calendar week: Push and Pull are
  /// done, Legs is next, so plans sit on different weeks of the block.
  static const _today = 2;

  /// Missed workouts, as (plan, block index, week). Logging is what advances a
  /// plan, so a missed deload simply never gets logged.
  static const _missed = {('Full Body', 0, 4)};

  static const _deloadFactor = 0.85;

  static Future<void> seedIfEmpty({required String splitId}) async {
    final plans = HiveService.getPlans(splitId: splitId);
    if (plans.isNotEmpty) return;

    await seedSampleData(splitId: splitId);
  }

  /// Replaces only [splitId]'s workouts with the sample training history.
  static Future<void> seedSampleData({required String splitId}) async {
    await SyncService.instance.runExclusiveLocalMutation(() async {
      final owner = HiveService.trainingCacheOwner();
      await HiveService.recoverTrainingOperations(ownerId: owner);
      final current = TrainingBlockMigration.prepareGraph(
        HiveService.readTrainingGraph(ownerId: owner).ownedBy(owner),
      );
      final cleared = current.clearWorkouts(splitId: splitId);
      // clearWorkouts supplies an unsaved bootstrap Block 1 / Week 1; the
      // sample brings its own structure, so that placeholder is dropped.
      final bootstrap =
          cleared.blocks
              .singleWhere((b) => b.splitId == splitId && b.deletedAt == null)
              .id;
      final sample = buildDataset(
        splitId: splitId,
        ownerId: owner,
        now: DateTime.now(),
      );
      final graph = TrainingBlockMigration.prepareGraph(
        cleared.copyWith(
          blocks: [
            ...cleared.blocks.where((b) => b.id != bootstrap),
            ...sample.blocks,
          ],
          weeks: [
            ...cleared.weeks.where((w) => w.blockId != bootstrap),
            ...sample.weeks,
          ],
          plans: [...cleared.plans, ...sample.plans],
          sessions: [...cleared.sessions, ...sample.sessions],
          progress: [...cleared.progress, ...sample.progress],
        ),
      );
      await TrainingBlockRestore().replaceUnderGate(
        graph: graph.explicitPlanRevisions(
          sample.plans.map((p) => p.id!).toSet(),
        ),
        stampRecords: false,
      );
    });
    SyncService.instance.scheduleSync();
  }

  /// Builds roughly three months of training ending at [now]: a Foundation
  /// block with a deload, a Hypertrophy block with a deload, a week off, and
  /// the current Strength block in progress. Values are deterministic; only
  /// IDs and dates (relative to [now]) differ between calls.
  static SampleDataset buildDataset({
    required String splitId,
    required String? ownerId,
    required DateTime now,
  }) {
    const uuid = Uuid();
    final rng = Random(2026);
    final today = DateTime(now.year, now.month, now.day);
    final currentIndex = _calendar.length - 1;
    DateTime day(int calendarWeek, int dayOfWeek, [int hour = 0, int min = 0]) {
      final ago = currentIndex * 7 + _today - (calendarWeek * 7 + dayOfWeek);
      return DateTime(today.year, today.month, today.day - ago, hour, min);
    }

    // Plans first: their IDs anchor sessions and progress.
    final planIds = {for (final p in _plans) p.name: uuid.v4()};

    // Sessions, oldest first.
    final logged = <(int, int, String, WorkoutSession)>[];
    for (final (index, slot) in _calendar.indexed) {
      if (slot == null) continue;
      final (blockIndex, week) = slot;
      final block = _blocks[blockIndex];
      for (final plan in _plans) {
        if (_missed.contains((plan.name, blockIndex, week))) continue;
        // Alternate days are rest days, so a moved workout never collides.
        final dayOfWeek =
            plan.altDay != null && rng.nextDouble() < 0.25
                ? plan.altDay!
                : plan.day;
        if (index == currentIndex && dayOfWeek >= _today) continue;
        final start = day(
          index,
          dayOfWeek,
          plan.hour + rng.nextInt(2),
          rng.nextInt(12) * 5,
        );
        final exercises = [
          for (final lift in plan.lifts)
            Exercise(
              name: lift.name,
              exerciseId: ExerciseLibrary.idsByName[lift.name],
              sets: _sets(lift, block, week, rng),
            ),
        ];
        _annotate(plan.name, blockIndex, week, block, exercises);
        final setCount = exercises.fold<int>(0, (n, e) => n + e.sets.length);
        logged.add((
          blockIndex,
          week,
          plan.name,
          WorkoutSession(
            id: uuid.v4(),
            date: start,
            startedAt: start,
            durationSeconds: setCount * 150 + 300 + rng.nextInt(16) * 60,
            planName: plan.name,
            planId: planIds[plan.name],
            splitId: splitId,
            weekNumber: week,
            exercises: exercises,
            userId: ownerId,
            updatedAt: now,
            dirty: true,
          ),
        ));
      }
    }

    // Each plan's next week: the one after its latest log in the last block.
    final active = <String, int>{
      for (final plan in _plans)
        plan.name:
            logged
                .where((l) => l.$3 == plan.name && l.$1 == _blocks.length - 1)
                .map((l) => l.$2)
                .reduce(max) +
            1,
    };

    // Blocks start the day before their first workout; weeks after Week 1 are
    // allocated lazily, when the first workout of the week before is logged.
    final blocks = <TrainingBlock>[];
    final weeks = <TrainingWeek>[];
    for (final (blockIndex, spec) in _blocks.indexed) {
      final firstWeek = _calendar.indexWhere((c) => c?.$1 == blockIndex);
      final created = day(firstWeek, -1, 20);
      final block = TrainingBlock(
        id: uuid.v4(),
        splitId: splitId,
        name: spec.name,
        plannedWeekCount: spec.plannedWeeks,
        position: blockIndex,
        createdAt: created,
        userId: ownerId,
        updatedAt: now,
        dirty: true,
      );
      blocks.add(block);
      final reached = [
        ...logged.where((l) => l.$1 == blockIndex).map((l) => l.$2),
        if (blockIndex == _blocks.length - 1) ...active.values,
      ].reduce(max);
      for (var number = 1; number <= reached; number++) {
        final opener = logged
            .where((l) => l.$1 == blockIndex && l.$2 == number - 1)
            .map((l) => l.$4.date)
            .fold<DateTime?>(
              null,
              (a, b) => a == null || b.isBefore(a) ? b : a,
            );
        weeks.add(
          TrainingWeek(
            id:
                number == 1
                    ? uuid.v4()
                    : lazyTrainingWeekId(splitId, block.id, number),
            splitId: splitId,
            blockId: block.id,
            number: number,
            createdAt: opener ?? created,
            userId: ownerId,
            updatedAt: now,
            dirty: true,
          ),
        );
      }
    }
    String weekId(int blockIndex, int number) =>
        weeks
            .singleWhere(
              (w) => w.blockId == blocks[blockIndex].id && w.number == number,
            )
            .id;

    final sessions = [
      for (final (blockIndex, week, _, session) in logged)
        session.copyWith(trainingWeekId: weekId(blockIndex, week)),
    ];

    final current = _blocks.last;
    final plans = [
      for (final (position, spec) in _plans.indexed)
        WorkoutPlan(
          id: planIds[spec.name],
          name: spec.name,
          planColor: kPlanColors[position],
          position: position,
          splitId: splitId,
          userId: ownerId,
          updatedAt: now,
          dirty: true,
          exercises: [
            for (final lift in spec.lifts)
              _template(lift, current, active[spec.name]!),
          ],
        ),
    ];

    // Every reached slot stays available: earlier blocks in full (a plan that
    // missed a week still reached it), the current block up to its next week.
    final progress = [
      for (final spec in _plans)
        WorkoutProgress(
          id: workoutProgressId(splitId, planIds[spec.name]!),
          splitId: splitId,
          planId: planIds[spec.name]!,
          activeWeekId: weekId(_blocks.length - 1, active[spec.name]!),
          state: WorkoutProgressState.ready,
          revision: initialProgressRevision(splitId, planIds[spec.name]!),
          availableWeekIds: [
            for (final (blockIndex, block) in blocks.indexed)
              for (final w in weeks.where(
                (w) =>
                    w.blockId == block.id &&
                    (blockIndex < blocks.length - 1 ||
                        w.number <= active[spec.name]!),
              ))
                w.id,
          ],
          userId: ownerId,
          updatedAt: now,
          dirty: true,
        ),
    ];

    return SampleDataset(
      blocks: blocks,
      weeks: weeks,
      plans: plans,
      sessions: sessions,
      progress: progress,
    );
  }

  static double _load(_Lift lift, int step) {
    final raw = lift.start + lift.step * step;
    final rounded = (raw / lift.increment).round() * lift.increment;
    return (rounded * 100).round() / 100;
  }

  static double _deloadLoad(_Lift lift, _BlockSpec block) {
    final raw = _load(lift, block.firstStep) * _deloadFactor;
    final rounded = (raw / lift.increment).round() * lift.increment;
    return (rounded * 100).round() / 100;
  }

  /// The plan prescribes what its next workout should hit.
  static ExerciseTemplate _template(_Lift lift, _BlockSpec block, int week) {
    final deload = block.isDeload(week);
    final weight =
        deload
            ? _deloadLoad(lift, block)
            : _load(lift, block.firstStep + week - 1);
    final sets = deload ? max(2, lift.sets - 1) : lift.sets;
    return ExerciseTemplate(
      name: lift.name,
      exerciseId: ExerciseLibrary.idsByName[lift.name],
      sets: sets,
      setTargets: List.generate(
        sets,
        (_) => SetTemplate(reps: lift.reps + block.repBonus, weight: weight),
      ),
    );
  }

  /// Straight sets: an occasional extra rep on a fresh first set, reps that
  /// slip on the final sets more often as the block gets heavier, and RPE that
  /// climbs across sets and weeks. Deloads drop a set and stay easy.
  static List<Set> _sets(_Lift lift, _BlockSpec block, int week, Random rng) {
    final reps = lift.reps + block.repBonus;
    if (block.isDeload(week)) {
      final weight = _deloadLoad(lift, block);
      final count = max(2, lift.sets - 1);
      return [
        for (var i = 0; i < count; i++)
          Set(reps: reps, weight: weight, rpe: i == count - 1 ? 6 : 5),
      ];
    }
    final into = week - 1;
    final weight = _load(lift, block.firstStep + into);
    return [
      for (var i = 0; i < lift.sets; i++)
        () {
          final last = i == lift.sets - 1;
          var done = reps;
          var rpe = 7 + into ~/ 2 + (last ? 1 : 0);
          if (i == 0 && into == 0 && rng.nextDouble() < 0.3) done += 1;
          if (i >= lift.sets - 2 &&
              i > 0 &&
              rng.nextDouble() < 0.15 + 0.12 * into) {
            done -= 1;
            rpe += 1;
          }
          if (!last && rng.nextDouble() < 0.25) rpe -= 1;
          return Set(reps: done, weight: weight, rpe: rpe.clamp(6, 10));
        }(),
    ];
  }

  /// A few training-log notes at the moments a lifter would write one.
  static void _annotate(
    String plan,
    int blockIndex,
    int week,
    _BlockSpec block,
    List<Exercise> exercises,
  ) {
    void note(int exercise, int set, String text) {
      final sets = exercises[exercise].sets;
      final s = sets[set];
      sets[set] = Set(reps: s.reps, weight: s.weight, rpe: s.rpe, note: text);
    }

    if (block.isDeload(week)) {
      note(0, 0, 'Deload week: lighter, one set fewer');
    } else if (blockIndex == 0 && week == 1 && plan == 'Push Day') {
      note(0, 0, 'First session of the program, easy start');
    } else if (blockIndex == 1 && week == 3 && plan == 'Pull Day') {
      note(0, exercises[0].sets.length - 1, 'Grip went on the last rep');
    } else if (blockIndex == 2 && week == 1 && plan == 'Push Day') {
      note(0, 0, 'Back after a week off, felt fresh');
    } else if (blockIndex == 2 && week == 2 && plan == 'Leg Day') {
      note(0, 0, 'Belt on, moved well');
    }
  }

  static Future<void> clearAllData() async {
    await HiveService.softDeleteAllWorkoutData();
    SyncService.instance.scheduleSync();
  }

  static Future<void> clearDataForSplit(String splitId) async {
    await HiveService.softDeleteWorkoutDataForSplit(splitId);
    SyncService.instance.scheduleSync();
  }
}
