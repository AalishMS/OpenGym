import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/navigation/workout_destination.dart';
import 'package:gymapp/repositories/training_block_repository.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/training_block_migration.dart';
import 'package:gymapp/utils/workout_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hive_test_harness.dart';

void main() {
  final storage = HiveTestHarness();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await storage.open(includeSplits: true);
    await HiveService.putSplitRaw(
      Split(id: 's', name: 'Training', createdAt: DateTime(2026)),
    );
    await HiveService.putPlanRaw(
      WorkoutPlan(id: 'p', splitId: 's', name: 'Push', exercises: []),
    );
    await TrainingBlockMigration().normalize(ownerId: null);
  });
  tearDown(storage.close);

  test(
    'active and explicit week destinations distinguish two Week 1s',
    () async {
      final repository = TrainingBlockRepository(ownerId: () => null);
      final first = repository.blocksForSplit('s').first;
      final firstWeek = repository.weeksForBlock('s', first.id).single;
      final second = await repository.createBlock(
        splitId: 's',
        name: 'Strength',
        weekCount: 1,
      );
      final secondWeek = repository.weeksForBlock('s', second.id).single;
      final active =
          const WorkoutDestination.active('p').resolve(ownerId: null)!;
      final explicit =
          WorkoutDestination.week('p', secondWeek.id).resolve(ownerId: null)!;
      expect(active.week!.id, firstWeek.id);
      expect(explicit.week!.id, secondWeek.id);
      expect(explicit.session, isNull);
      expect(HiveService.getAllSessionsRaw(), isEmpty);
    },
  );

  test(
    'exact destination re-fetches duplicate ID and renamed plan at delivery',
    () async {
      final week = HiveService.getAllTrainingWeeksRaw().single;
      final old = WorkoutSession(
        id: 'old',
        planId: 'p',
        splitId: 's',
        trainingWeekId: week.id,
        planName: 'Push',
        date: DateTime(2026),
        exercises: [],
      );
      await HiveService.putSessionRaw(old);
      await HiveService.putSessionRaw(
        old.copyWith(id: 'new', date: DateTime(2026, 2)),
      );
      const destination = WorkoutDestination.session('old');
      await HiveService.putPlanRaw(
        HiveService.getPlanById('p')!.copyWith(name: 'Renamed'),
      );
      final resolved = destination.resolve(ownerId: null)!;
      expect(resolved.session!.id, 'old');
      expect(resolved.plan!.name, 'Renamed');
      await HiveService.softDeletePlan('p');
      expect(destination.resolve(ownerId: null)!.plan, isNull);
      expect(destination.resolve(ownerId: null)!.session!.id, 'old');
      expect(destination.resolve(ownerId: 'other'), isNull);
      await HiveService.softDeleteSession('old');
      expect(destination.resolve(ownerId: null), isNull);
    },
  );

  test(
    'exact orphan with missing plan and week resolves to details without guessing',
    () async {
      await HiveService.putSessionRaw(
        WorkoutSession(
          id: 'orphan',
          splitId: 's',
          planName: 'Retired',
          date: DateTime(2025),
          exercises: [],
        ),
      );
      final resolved =
          const WorkoutDestination.session('orphan').resolve(ownerId: null)!;
      expect(resolved.plan, isNull);
      expect(resolved.week, isNull);
      expect(resolved.session!.planName, 'Retired');
    },
  );

  test(
    'history context falls back to retained week for missing or deleted structure',
    () async {
      final week = HiveService.getAllTrainingWeeksRaw().single;
      final row = WorkoutSession(
        planName: 'Push',
        splitId: 's',
        trainingWeekId: week.id,
        weekNumber: 7,
        date: DateTime(2026),
        exercises: [],
      );
      expect(workoutContext(row), 'Block 1 · Week 1');
      final block = HiveService.getTrainingBlockById(week.blockId)!;
      await HiveService.putTrainingBlockRaw(
        block.copyWith(deletedAt: DateTime(2026)),
      );
      expect(workoutContext(row), 'Block 1 · Week 7');
      expect(workoutContext(row.copyWith(trainingWeekId: 'missing')), 'Week 7');
    },
  );
}
