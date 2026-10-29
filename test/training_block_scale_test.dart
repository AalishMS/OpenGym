import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/split.dart' as gym;
import 'package:gymapp/models/training_block.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_progress.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/training_block_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/training_block_identity.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

class _MeasuredTraining extends TrainingBlockProvider {
  int reloads = 0;
  _MeasuredTraining()
    : super(splitIdProvider: () => 'scale', ownerId: () => null);
  @override
  void reload() {
    reloads++;
    super.reload();
  }
}

void main() {
  testWidgets(
    '100 blocks and 10000 sessions keep indexes stable on timer ticks',
    (tester) async {
      final storage = HiveTestHarness();
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        await loadTestFonts();
        await storage.open(includeSplits: true);
        await HiveService.putSplitRaw(
          gym.Split(
            id: 'scale',
            name: 'Scale trial',
            createdAt: DateTime(2026),
          ),
        );
        await HiveService.putPlanRaw(
          WorkoutPlan(
            id: 'p',
            splitId: 'scale',
            name: 'Push',
            exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
          ),
        );
        await Hive.box<TrainingBlock>(HiveService.trainingBlocksBox).putAll({
          for (var b = 0; b < 100; b++)
            'b$b': TrainingBlock(
              id: 'b$b',
              splitId: 'scale',
              name: 'Block ${b + 1}',
              position: b,
              createdAt: DateTime(2026),
            ),
        });
        await Hive.box<TrainingWeek>(HiveService.trainingWeeksBox).putAll({
          for (var b = 0; b < 100; b++)
            for (var w = 1; w <= 52; w++)
              'b$b-w$w': TrainingWeek(
                id: 'b$b-w$w',
                splitId: 'scale',
                blockId: 'b$b',
                number: w,
                createdAt: DateTime(2026),
              ),
        });
        await Hive.box<WorkoutSession>(HiveService.sessionsBox).putAll({
          for (var i = 0; i < 10000; i++)
            's$i': WorkoutSession(
              id: 's$i',
              planId: 'p',
              splitId: 'scale',
              planName: 'Push',
              trainingWeekId:
                  i == 9999 ? 'b99-w52' : 'b${i % 99}-w${i % 52 + 1}',
              weekNumber: i == 9999 ? 52 : i % 52 + 1,
              date: DateTime(2026).add(Duration(minutes: i)),
              isCompleted: i != 9999,
              startedAt:
                  i == 9999
                      ? DateTime.now().subtract(const Duration(minutes: 1))
                      : null,
              timerStartedAt:
                  i == 9999
                      ? DateTime.now().subtract(const Duration(minutes: 1))
                      : null,
              exercises: [
                Exercise(name: 'Squat', sets: [gym.Set(weight: 100, reps: 5)]),
              ],
            ),
        });
        final progress = WorkoutProgress(
          id: workoutProgressId('scale', 'p'),
          splitId: 'scale',
          planId: 'p',
          activeWeekId: 'b99-w52',
          availableWeekIds: [for (var w = 1; w <= 52; w++) 'b99-w$w'],
          revision: 'initial',
          state: WorkoutProgressState.ready,
        );
        await HiveService.putWorkoutProgressRaw(progress);
      });
      final load = Stopwatch()..start();
      final training = _MeasuredTraining();
      load.stop();
      final reload = Stopwatch()..start();
      final oldIndex = training.sessionById;
      training.reload();
      reload.stop();
      expect(training.reloads, 2);
      expect(identical(training.sessionById, oldIndex), isFalse);
      expect(training.weekById, hasLength(5200));
      expect(training.sessionById, hasLength(10000));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TrainingBlockProvider>.value(
                value: training,
              ),
              ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
              ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
            ],
            child: MaterialApp(
              theme: buildTheme(const Color(0xFF008D8D), Brightness.dark),
              home: WorkoutScreen(
                plan: HiveService.getPlanById('p')!,
                planIndex: 0,
              ),
            ),
          ),
        );
        await pumpWithStorage(tester);
        final index = training.sessionById;
        final reloads = training.reloads;
        final weeks = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('training-week-'),
        );
        expect(weeks, findsNWidgets(52));
        expect(
          find.byKey(const ValueKey('training-week-b98-w1')),
          findsNothing,
        );
        final selected = find.byKey(const ValueKey('training-week-b99-w52'));
        expect(tester.getRect(selected).right, lessThanOrEqualTo(390));
        await tester.pump(const Duration(seconds: 5));
        expect(training.reloads, reloads);
        expect(identical(training.sessionById, index), isTrue);
        expect(weeks, findsNWidgets(52));
        expect(tester.takeException(), isNull);
        debugPrint(
          'Scale trial (host VM, not Android frames): first index ${load.elapsedMicroseconds}us; explicit reload ${reload.elapsedMicroseconds}us; 5200 weeks, 10000 sessions, 52 week controls, timer reload delta ${training.reloads - reloads}.',
        );
      } finally {
        training.dispose();
        await closeStorageWithFrames(tester, storage.close);
      }
    },
  );
}
