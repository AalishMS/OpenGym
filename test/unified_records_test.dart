import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/statistics.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/navigation/workout_destination.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/screens/workout_summary_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/statistics_analytics_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/training_block_identity.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

/// Live PR marks, logged-workout editing, the summary after Finish, History
/// and Stats all read one record definition. These tests pin them together.
void main() {
  const analytics = StatisticsAnalyticsService();
  const bench = 'builtin:bench-press';
  const plank = 'builtin:plank';

  WorkoutSession workout(
    String id,
    int day,
    List<Exercise> exercises, {
    bool completed = true,
  }) => WorkoutSession(
    id: id,
    splitId: 'split',
    planId: 'plan',
    planName: 'Push',
    date: DateTime(2026, 3, day),
    isCompleted: completed,
    exercises: exercises,
  );

  Exercise lift(String name, String? id, List<Set> sets) =>
      Exercise(name: name, exerciseId: id, sets: sets);

  List<(RecordType, double, double?, int?, int?)> flat(
    Iterable<RecordEvent> events,
  ) => [
    for (final event in events)
      for (final a in event.achievements)
        (a.type, a.value, a.previousValue, a.exerciseIndex, a.setIndex),
  ];

  group('RecordJudge judges a candidate exactly like recordEvents', () {
    final history = [
      workout('w1', 1, [
        lift('Bench Press', bench, [Set(weight: 100, reps: 5)]),
        lift('Plank', plank, [Set(weight: 0, reps: 45)]),
        lift('Pull-ups', 'builtin:pull-ups', [Set(weight: 0, reps: 10)]),
      ]),
      workout('w2', 8, [
        lift('Bench Press', bench, [Set(weight: 90, reps: 8)]),
      ]),
    ];
    final candidates = <String, WorkoutSession>{
      'heavier sets, zero-rep set ignored': workout('c', 15, [
        lift('Bench Press', bench, [
          Set(weight: 105, reps: 5),
          Set(weight: 110, reps: 3),
          Set(weight: 150, reps: 0),
        ]),
      ]),
      'rep best needs to beat N-or-more reps': workout('c', 15, [
        lift('Bench Press', bench, [Set(weight: 90, reps: 5)]),
      ]),
      'longest hold only, even with weight': workout('c', 15, [
        lift('Front hold', plank, [Set(weight: 10, reps: 60)]),
      ]),
      'added load after bodyweight': workout('c', 15, [
        lift('Pull-ups', 'builtin:pull-ups', [Set(weight: 10, reps: 6)]),
      ]),
      'a first-time lift is a baseline': workout('c', 15, [
        lift('Squat', 'builtin:squat', [Set(weight: 140, reps: 5)]),
      ]),
    };
    for (final MapEntry(key: name, value: candidate) in candidates.entries) {
      test(name, () {
        final judged = analytics.recordJudge(history).recordsFor(candidate);
        final reference = analytics.sessionRecords([
          ...history,
          candidate,
        ], candidate);
        expect(flat(judged), flat(reference));
      });
    }

    test('the rules the cases above pin', () {
      List<(RecordType, double, double?, int?, int?)> judge(String name) =>
          flat(analytics.recordJudge(history).recordsFor(candidates[name]!));
      // One heaviest weight for the workout's top set, never the zero-rep one.
      expect(
        judge(
          'heavier sets, zero-rep set ignored',
        ).where((r) => r.$1 == RecordType.heaviestWeight),
        [(RecordType.heaviestWeight, 110.0, 100.0, 0, 1)],
      );
      // 90 × 5 does not beat 100 × 5 (or 90 × 8, which has more reps).
      expect(judge('rep best needs to beat N-or-more reps'), isEmpty);
      expect(judge('longest hold only, even with weight'), [
        (RecordType.longestHold, 60.0, 45.0, 0, 0),
      ]);
      expect(judge('added load after bodyweight'), [
        (RecordType.heaviestWeight, 10.0, 0.0, 0, 0),
      ]);
      expect(judge('a first-time lift is a baseline'), isEmpty);
    });
  });

  group('the workout screen', () {
    final harness = HiveTestHarness();
    final plan = WorkoutPlan(
      id: 'push',
      name: 'Push',
      exercises: [
        ExerciseTemplate(name: 'Bench Press', exerciseId: bench, sets: 3),
        ExerciseTemplate(name: 'Plank', exerciseId: plank, sets: 1),
        ExerciseTemplate(
          name: 'Cable Fly',
          exerciseId: 'builtin:cable-fly',
          sets: 1,
        ),
      ],
    );

    setUpAll(() async {
      await loadTestFonts();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-publishable-key',
      );
    });
    setUp(() => harness.open());

    WorkoutSession week(
      int number,
      List<Exercise> exercises, {
      bool completed = true,
    }) => WorkoutSession(
      id: 'push-$number',
      planId: 'push',
      planName: 'Push',
      date: DateTime(2026, 1, number * 7),
      weekNumber: number,
      isCompleted: completed,
      startedAt: completed ? null : DateTime(2026, 1, number * 7),
      durationSeconds: completed ? null : 600,
      exercises: exercises,
    );

    Future<void> open(
      WidgetTester tester,
      List<WorkoutSession> sessions, {
      required int weekNumber,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2000);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await Hive.box<WorkoutPlan>(HiveService.plansBox).put(plan.id, plan);
        for (final session in sessions) {
          await Hive.box<WorkoutSession>(
            HiveService.sessionsBox,
          ).put(session.id, session);
        }
        await harness.prepareTraining([plan], weekCount: 3);
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
            ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
          ],
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF00A8FF), Brightness.light),
            home: WorkoutScreen(
              plan: HiveService.getPlanById('push')!,
              planIndex: 0,
              destination: WorkoutDestination.week(
                'push',
                legacyTrainingWeekId('test-split', weekNumber),
              ),
            ),
          ),
        ),
      );
      await pumpWithStorage(tester);
    }

    Finder mark(String exercise, int set) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is ExerciseCard && w.exercise.name == exercise,
      ),
      matching: find.byKey(ValueKey('live-record-$set')),
    );

    void workoutTest(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          try {
            await body(tester);
          } finally {
            await closeStorageWithFrames(tester, harness.close);
          }
        });

    final week1 = week(1, [
      lift('Bench Press', bench, [Set(weight: 100, reps: 5)]),
      lift('Plank', plank, [Set(weight: 0, reps: 45)]),
    ]);

    workoutTest('live marks are the shared heaviest-weight record and '
        'match the summary after Finish', (tester) async {
      await open(tester, [
        week1,
        week(2, completed: false, [
          lift('Bench Press', bench, [
            Set(weight: 105, reps: 5),
            Set(weight: 110, reps: 3),
            Set(weight: 150, reps: 0),
          ]),
          lift('Plank', plank, [Set(weight: 0, reps: 60)]),
          lift('Cable Fly', 'builtin:cable-fly', [Set(weight: 20, reps: 12)]),
        ]),
      ], weekNumber: 2);

      // One mark per lift, on the workout's top set; never a zero-rep set,
      // a hold, or a lift's first workout.
      expect(mark('Bench Press', 0), findsNothing);
      expect(mark('Bench Press', 1), findsOneWidget);
      expect(mark('Bench Press', 2), findsNothing);
      expect(mark('Plank', 0), findsNothing);
      expect(mark('Cable Fly', 0), findsNothing);

      await tester.tap(find.byKey(const ValueKey('finish-workout')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log workout'));
      await pumpWithStorage(tester);

      final summary = tester.widget<WorkoutSummaryScreen>(
        find.byType(WorkoutSummaryScreen),
      );
      final record = summary.records.single;
      expect(record.exerciseId, bench);
      expect(record.newPR, 110);
      expect(record.previousPR, 100);
      expect(record.reps, 3);
      expect(tester.takeException(), isNull);
    });

    workoutTest('editing a logged workout compares only with earlier logs', (
      tester,
    ) async {
      await open(tester, [
        week1,
        week(2, [
          lift('Bench Press', bench, [Set(weight: 105, reps: 5)]),
        ]),
        // A later, heavier log must not hide week 2's record.
        week(3, [
          lift('Bench Press', bench, [Set(weight: 120, reps: 5)]),
        ]),
      ], weekNumber: 2);

      expect(mark('Bench Press', 0), findsOneWidget);
      final sessions = HiveService.getCompletedSessions();
      final history = analytics.recordEvents(sessions);
      final week2 = history.where((e) => e.session.id == 'push-2');
      expect(
        week2.single.achievements
            .where((a) => a.type == RecordType.heaviestWeight)
            .single
            .setIndex,
        0,
        reason: 'History and Stats mark the same set',
      );
      expect(tester.takeException(), isNull);
    });

    workoutTest('a log at the same time is judged in the shared order', (
      tester,
    ) async {
      // Same timestamp as week 2; Finish orders push-1 before push-2 by ID.
      final sameTime = WorkoutSession(
        id: 'push-1',
        planId: 'push',
        planName: 'Push',
        date: DateTime(2026, 1, 14),
        weekNumber: 1,
        isCompleted: true,
        exercises: [
          lift('Bench Press', bench, [Set(weight: 100, reps: 5)]),
        ],
      );
      final current = week(2, completed: false, [
        lift('Bench Press', bench, [Set(weight: 110, reps: 3)]),
      ]);
      expect(current.date, sameTime.date);
      await open(tester, [sameTime, current], weekNumber: 2);

      expect(mark('Bench Press', 0), findsOneWidget);
      final shared = analytics.sessionRecords([
        sameTime,
        current.copyWith(isCompleted: true),
      ], current);
      expect(
        flat(shared).map((r) => r.$1),
        contains(RecordType.heaviestWeight),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
