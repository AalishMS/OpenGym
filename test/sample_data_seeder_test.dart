import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/data/exercise_library.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/sample_data_seeder.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/utils/set_history.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/hive_test_harness.dart';

const owner = '00000000-0000-4000-8000-000000000021';
const splitId = '00000000-0000-4000-8000-000000000022';
const otherSplitId = '00000000-0000-4000-8000-000000000023';
final stamp = DateTime.utc(2026, 1, 1);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

double _topWeight(WorkoutSession s, String exercise) => s.exercises
    .where((e) => e.name == exercise)
    .expand((e) => e.sets)
    .fold(0, (best, set) => set.weight > best ? set.weight : best);

void main() {
  group('sample dataset', () {
    final now = DateTime(2026, 11, 6, 9, 30);
    final data = SampleDataSeeder.buildDataset(
      splitId: splitId,
      ownerId: owner,
      now: now,
    );
    final blockIndex = {for (final (i, b) in data.blocks.indexed) b.id: i};
    final weekById = {for (final w in data.weeks) w.id: w};
    int blockOf(WorkoutSession s) =>
        blockIndex[weekById[s.trainingWeekId]!.blockId]!;
    bool deload(WorkoutSession s) {
      final week = weekById[s.trainingWeekId]!;
      final block = data.blocks[blockIndex[week.blockId]!];
      return week.number == block.plannedWeekCount;
    }

    test('logs every plan in every block on a realistic schedule', () {
      expect(data.plans, hasLength(5));
      expect(data.blocks.map((b) => b.position), [0, 1, 2]);
      for (final plan in data.plans) {
        final logs = data.sessions.where((s) => s.planId == plan.id).toList();
        expect(logs.length, greaterThanOrEqualTo(10), reason: plan.name);
        expect(logs.map(blockOf).toSet(), {0, 1, 2}, reason: plan.name);
        logs.sort((a, b) => a.date.compareTo(b.date));
        for (var i = 1; i < logs.length; i++) {
          final gap = _day(logs[i].date).difference(_day(logs[i - 1].date));
          expect(gap.inDays, greaterThanOrEqualTo(5), reason: plan.name);
        }
      }
      final days = data.sessions.map((s) => _day(s.date)).toList();
      expect(days.toSet(), hasLength(days.length), reason: 'one per day');
      expect(data.sessions.every((s) => s.date.isBefore(now)), isTrue);
      expect(
        _day(
          data.sessions
              .map((s) => s.date)
              .reduce((a, b) => a.isAfter(b) ? a : b),
        ),
        _day(now).subtract(const Duration(days: 1)),
      );
      // Calendar order follows block and week order.
      final ordered = [...data.sessions]
        ..sort((a, b) => a.date.compareTo(b.date));
      for (var i = 1; i < ordered.length; i++) {
        final prev = (blockOf(ordered[i - 1]), ordered[i - 1].weekNumber);
        final next = (blockOf(ordered[i]), ordered[i].weekNumber);
        expect(
          next.$1 > prev.$1 || (next.$1 == prev.$1 && next.$2 >= prev.$2),
          isTrue,
        );
      }
      // Plausible workout lengths, logged through the timer.
      for (final s in data.sessions) {
        expect(s.durationSeconds, inInclusiveRange(30 * 60, 90 * 60));
        expect(s.isCompleted, isTrue);
        expect(s.startedAt, s.date);
      }
    });

    test('links every log to its plan, split, week and catalog exercise', () {
      final plans = {for (final p in data.plans) p.id: p};
      for (final s in data.sessions) {
        final plan = plans[s.planId]!;
        final week = weekById[s.trainingWeekId]!;
        expect(s.planName, plan.name);
        expect(s.splitId, splitId);
        expect(week.number, s.weekNumber);
        expect(week.splitId, splitId);
        expect(
          s.exercises.map((e) => e.name),
          plan.exercises.map((e) => e.name),
        );
        for (final e in s.exercises) {
          expect(e.exerciseId, ExerciseLibrary.idsByName[e.name]);
          expect(e.exerciseId, isNotNull, reason: e.name);
          expect(e.sets.every((set) => set.weight > 0 && set.reps > 0), isTrue);
        }
      }
      for (final plan in data.plans) {
        for (final e in plan.exercises) {
          expect(e.exerciseId, ExerciseLibrary.idsByName[e.name]);
          expect(e.setTargets, hasLength(e.sets));
        }
      }
    });

    test('gains gradually with deloads and normal set variability', () {
      for (final plan in data.plans) {
        final logs =
            data.sessions.where((s) => s.planId == plan.id).toList()
              ..sort((a, b) => a.date.compareTo(b.date));
        for (final exercise in plan.exercises.map((e) => e.name)) {
          double best(int block) => logs
              .where((s) => blockOf(s) == block && !deload(s))
              .map((s) => _topWeight(s, exercise))
              .reduce((a, b) => a > b ? a : b);
          expect(best(1), greaterThan(best(0)), reason: exercise);
          expect(best(2), greaterThan(best(1)), reason: exercise);
          final working = logs.where((s) => !deload(s)).toList();
          for (var i = 1; i < working.length; i++) {
            final before = _topWeight(working[i - 1], exercise);
            final after = _topWeight(working[i], exercise);
            // Never a drop between working weeks; a rise is gradual, or a
            // single plate or dumbbell step on light lifts.
            expect(after, greaterThanOrEqualTo(before), reason: exercise);
            expect(
              after / before <= 1.15 || after - before <= 2.5,
              isTrue,
              reason: '$exercise $before -> $after on ${working[i].date}',
            );
          }
        }
      }
      final deloads = data.sessions.where(deload).toList();
      expect(deloads, isNotEmpty);
      for (final s in deloads) {
        expect(
          s.exercises.expand((e) => e.sets).every((x) => x.rpe! <= 6),
          isTrue,
        );
      }
      final working = data.sessions.where((s) => !deload(s));
      final rpes = working
          .expand((s) => s.exercises)
          .expand((e) => e.sets)
          .map((x) => x.rpe!);
      expect(rpes.toSet().length, greaterThanOrEqualTo(4));
      expect(rpes.every((r) => r >= 6 && r <= 10), isTrue);
      final missedReps = working
          .expand((s) => s.exercises)
          .where((e) => e.sets.map((x) => x.reps).toSet().length > 1);
      expect(missedReps.length, greaterThan(20));
      expect(
        data.sessions
            .expand((s) => s.exercises)
            .expand((e) => e.sets)
            .where((x) => x.note != null),
        isNotEmpty,
      );
    });

    test('plans advance independently through lazily allocated weeks', () {
      final current = data.blocks.last;
      final allocated =
          data.weeks.where((w) => w.blockId == current.id).toList();
      final actives = <int>{};
      for (final p in data.progress) {
        final week = weekById[p.activeWeekId]!;
        expect(week.blockId, current.id);
        actives.add(week.number);
        expect(p.availableWeekIds!.last, p.activeWeekId);
        // The week before the active one holds this plan's latest log.
        final before = allocated.singleWhere(
          (w) => w.number == week.number - 1,
        );
        expect(
          data.sessions.where(
            (s) => s.planId == p.planId && s.trainingWeekId == before.id,
          ),
          hasLength(1),
        );
        expect(
          data.sessions.where(
            (s) => s.planId == p.planId && s.trainingWeekId == week.id,
          ),
          isEmpty,
        );
      }
      expect(actives.length, greaterThan(1));
      final highest = allocated
          .map((w) => w.number)
          .reduce((a, b) => a > b ? a : b);
      expect(highest, actives.reduce((a, b) => a > b ? a : b));
      expect(highest, lessThan(current.plannedWeekCount!));
      for (final w in data.weeks.where((w) => w.number > 1)) {
        expect(w.id, lazyTrainingWeekId(splitId, w.blockId, w.number));
      }
      expect(
        data.sessions.where((s) => s.trainingWeekId == allocated.last.id),
        isEmpty,
      );
    });
  });

  group('seeding storage', () {
    final storage = HiveTestHarness();
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-key',
      );
    });
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await storage.open(includeSplits: true);
      for (final (id, name) in [(splitId, 'Main'), (otherSplitId, 'Other')]) {
        await HiveService.putSplitRaw(
          Split(
            id: id,
            name: name,
            createdAt: stamp,
            userId: owner,
            updatedAt: stamp,
          ),
        );
      }
      await HiveService.putPlanRaw(
        WorkoutPlan(
          id: 'kept',
          name: 'Kept',
          exercises: [],
          splitId: otherSplitId,
          userId: owner,
          updatedAt: stamp,
        ),
      );
      await TrainingBlockMigration().normalize(ownerId: owner);
    });
    tearDown(storage.close);

    test(
      'replaces only the active split and fills Previous for every plan',
      () async {
        final otherBlock =
            HiveService.blocksForSplit(otherSplitId).single.toJson();
        await SampleDataSeeder.seedSampleData(splitId: splitId);
        await SampleDataSeeder.seedSampleData(splitId: splitId);

        HiveService.readTrainingGraph(ownerId: owner).validate();
        expect(
          HiveService.blocksForSplit(otherSplitId).single.toJson(),
          otherBlock,
        );
        expect(HiveService.getPlans(splitId: otherSplitId).map((p) => p.id), [
          'kept',
        ]);

        final plans = HiveService.getPlans(splitId: splitId);
        final sessions = HiveService.getSessions(splitId: splitId);
        final blocks = HiveService.blocksForSplit(splitId);
        final weeks = <TrainingWeek>[
          for (final b in blocks) ...HiveService.weeksForBlock(splitId, b.id),
        ];
        // Re-seeding leaves exactly one live sample.
        expect(plans, hasLength(5));
        expect(blocks, hasLength(3));
        expect(
          sessions.map((s) => s.planId).toSet(),
          plans.map((p) => p.id).toSet(),
        );
        expect(
          HiveService.getAllSessionsRaw().where(
            (s) => s.splitId == splitId && s.deletedAt != null,
          ),
          hasLength(sessions.length),
        );
        expect(
          [...plans, ...sessions].every(
            (r) =>
                (r as dynamic).dirty == true && (r as dynamic).userId == owner,
          ),
          isTrue,
        );

        final progress = HiveService.getAllWorkoutProgressRaw().where(
          (p) => p.splitId == splitId && p.deletedAt == null,
        );
        expect(progress, hasLength(5));
        for (final plan in plans) {
          final p = progress.singleWhere((p) => p.planId == plan.id);
          final active = weeks.singleWhere((w) => w.id == p.activeWeekId);
          expect(active.blockId, blocks.last.id, reason: plan.name);
          final latest = sessions
              .where((s) => s.planId == plan.id)
              .reduce((a, b) => a.date.isAfter(b.date) ? a : b);
          for (final exercise in plan.exercises) {
            final previous = previousExerciseSets(
              sessions,
              exercise.name,
              planId: plan.id,
              splitId: splitId,
              beforeWeekId: active.id,
              blocks: blocks,
              weeks: weeks,
            );
            expect(
              previous,
              isNotEmpty,
              reason: '${plan.name} ${exercise.name}',
            );
            expect(
              previous.map((s) => (s.reps, s.weight)),
              latest.exercises
                  .singleWhere((e) => e.name == exercise.name)
                  .sets
                  .map((s) => (s.reps, s.weight)),
            );
          }
        }

        final stats = const StatisticsAnalyticsService().blockStatistics(
          sessions,
          blocks: blocks,
          weeksByBlock: {
            for (final b in blocks)
              b.id: HiveService.weeksForBlock(splitId, b.id),
          },
        );
        expect(stats.every((b) => b.workouts >= 10), isTrue);
        expect(stats.every((b) => b.records > 0), isTrue);
        expect(stats.last.weeks.where((w) => w.weekId == null), isNotEmpty);
        expect(stats.map((b) => b.block.name), [
          'Foundation',
          'Hypertrophy',
          'Strength',
        ]);
        expect(
          blocks.every((TrainingBlock b) => b.plannedWeekCount != null),
          isTrue,
        );
      },
    );
  });
}
