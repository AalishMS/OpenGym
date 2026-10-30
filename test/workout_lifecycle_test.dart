import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/training_week.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/pr_tracking_service.dart';
import 'package:gymapp/services/workout_completion_service.dart';
import 'package:gymapp/services/workout_session_initializer.dart';
import 'package:gymapp/services/workout_timer_notification_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/training_block_strip.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

void main() {
  WorkoutSession draft({
    String? id = 'draft',
    DateTime? startedAt,
    DateTime? timerStartedAt,
    int? durationSeconds = 0,
    List<gym.Set>? sets,
  }) => WorkoutSession(
    id: id,
    date: DateTime(2026, 9, 5, 10),
    planName: 'Strength',
    weekNumber: 1,
    splitId: 'split-a',
    isCompleted: false,
    startedAt: startedAt,
    timerStartedAt: timerStartedAt,
    durationSeconds: durationSeconds,
    exercises: [
      Exercise(name: 'Squat', sets: sets ?? [gym.Set(reps: 5, weight: 100)]),
    ],
  );

  test('legacy JSON defaults to completed with no misleading duration', () {
    final session = WorkoutSession.fromJson({
      'date': DateTime(2025).toIso8601String(),
      'planName': 'Legacy',
      'weekNumber': 1,
      'exercises': <Map<String, dynamic>>[],
    });
    expect(session.isCompleted, isTrue);
    expect(session.durationSeconds, isNull);
  });

  test('timer metadata survives the existing JSON sync and backup payload', () {
    final start = DateTime(2026, 9, 5, 10);
    final restored = WorkoutSession.fromJson(
      draft(
        startedAt: start,
        timerStartedAt: start.add(const Duration(minutes: 1)),
        durationSeconds: 42,
      ).toJson(),
    );
    expect(restored.isCompleted, isFalse);
    expect(restored.startedAt, start);
    expect(restored.timerStartedAt, start.add(const Duration(minutes: 1)));
    expect(restored.durationSeconds, 42);
  });

  test('new Week 1 prescriptions are incomplete drafts', () {
    final session = WorkoutSessionInitializer.initialize(
      plan: WorkoutPlan(
        name: 'Strength',
        splitId: 'split-a',
        exercises: [
          ExerciseTemplate(
            name: 'Squat',
            sets: 1,
            setTargets: [SetTemplate(reps: 5, weight: 100)],
          ),
        ],
      ),
      week: TrainingWeek(
        id: 'week-1',
        splitId: 'split-a',
        blockId: 'block',
        number: 1,
        createdAt: DateTime(2026),
      ),
    );
    expect(session.isCompleted, isFalse);
    expect(session.durationSeconds, 0);
    expect(session.exercises.single.sets.single.weight, 100);
  });

  test('elapsed time combines persisted accumulation and wall clock delta', () {
    final session = draft(
      startedAt: DateTime(2026, 9, 5, 10),
      timerStartedAt: DateTime(2026, 9, 5, 10, 1),
      durationSeconds: 30,
    );
    expect(session.elapsedSeconds(DateTime(2026, 9, 5, 10, 2, 10)), 100);
  });

  test('notification snapshot uses the same persisted timer semantics', () {
    final snapshot = WorkoutTimerNotificationSnapshot.fromMap({
      'sessionId': 'draft',
      'planId': 'plan',
      'splitId': 'split-a',
      'planName': 'Strength',
      'weekNumber': 2,
      'accumulatedSeconds': 30,
      'runningSinceMillis': DateTime(2026, 9, 5, 10).millisecondsSinceEpoch,
      'running': true,
      'actionRevision': 42,
      'pendingStop': false,
    });

    expect(snapshot.blockName, isNull);
    expect(snapshot.isRunning, isTrue);
    expect(snapshot.elapsedSeconds(DateTime(2026, 9, 5, 10, 1, 10)), 100);
  });

  test(
    'notification optional block context round trips without becoming identity',
    () {
      final snapshot = WorkoutTimerNotificationSnapshot.fromMap({
        'sessionId': 'exact-old-draft',
        'planId': 'p',
        'splitId': 's',
        'planName': 'Push',
        'weekNumber': 1,
        'blockName': 'Strength',
        'accumulatedSeconds': 90,
        'running': false,
        'actionRevision': 44,
      });
      expect(snapshot.blockName, 'Strength');
      expect(snapshot.sessionId, 'exact-old-draft');
      expect(snapshot.elapsedSeconds(), 90);
    },
  );

  test('notification stop event opens the workout and requests logging', () {
    final event = WorkoutTimerNotificationEvent.fromMap({
      'action': 'stop',
      'snapshot': {
        'sessionId': 'draft',
        'planId': 'plan',
        'splitId': 'split-a',
        'planName': 'Strength',
        'weekNumber': 2,
        'accumulatedSeconds': 90,
        'runningSinceMillis': null,
        'running': false,
        'actionRevision': 43,
        'pendingStop': true,
      },
    });

    expect(event.openWorkout, isTrue);
    expect(event.requestLogConfirmation, isTrue);
    expect(event.snapshot.pendingStop, isTrue);
    expect(event.snapshot.elapsedSeconds(), 90);
  });

  test(
    'completion excludes self, writes once, and counts prescriptions',
    () async {
      final start = DateTime(2026, 9, 5, 10);
      final candidate = draft(startedAt: start, timerStartedAt: start);
      final oldSelf = candidate.copyWith(
        isCompleted: true,
        timerStartedAt: null,
      );
      final older = WorkoutSession(
        id: 'older',
        date: DateTime(2026, 8),
        planName: 'Strength',
        splitId: 'split-a',
        exercises: [
          Exercise(name: 'Squat', sets: [gym.Set(reps: 5, weight: 90)]),
        ],
      );
      var writes = 0;
      late WorkoutSession written;
      final result = await WorkoutCompletionService.complete(
        candidate,
        now: start.add(const Duration(minutes: 5)),
        history: [oldSelf, older],
        upsert: (session) async {
          writes++;
          written = session;
        },
      );
      expect(writes, 1);
      expect(written.isCompleted, isTrue);
      expect(written.timerStartedAt, isNull);
      expect(written.durationSeconds, 300);
      expect(result.personalRecords.single.previousPR, 90);
      expect(result.personalRecords.single.newPR, 100);
    },
  );

  test('zero placeholders do not count as performed PR sets', () {
    final results = PRTrackingService.checkAgainstHistory([
      Exercise(name: 'Squat', sets: [gym.Set(reps: 0, weight: 0)]),
    ], const []);
    expect(results, isEmpty);
  });

  test('failed completion leaves the original draft retryable', () async {
    final start = DateTime(2026, 9, 5, 10);
    final candidate = draft(startedAt: start, timerStartedAt: start);
    await expectLater(
      WorkoutCompletionService.complete(
        candidate,
        now: start.add(const Duration(minutes: 1)),
        history: const [],
        upsert: (_) async => throw StateError('disk full'),
      ),
      throwsStateError,
    );
    expect(candidate.isCompleted, isFalse);
    expect(candidate.timerStartedAt, start);
    expect(candidate.durationSeconds, 0);
  });

  group('Workout screen', () {
    final hive = HiveTestHarness();
    final plan = WorkoutPlan(
      id: 'strength',
      name: 'Strength',
      exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
    );
    // The timer notification is Android-only; widget tests report Android.
    const notifications = MethodChannel(
      'com.aalishms.opengym/workout_timer_notification',
    );
    late WorkoutSessionProvider sessions;

    setUpAll(() async {
      await loadTestFonts();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-publishable-key',
      );
    });
    tearDownAll(hive.close);

    setUp(() async {
      await hive.open();
      if (!Hive.isBoxOpen(HiveService.sessionsBox)) {
        await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
      }
      await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
      await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
      await HiveService.putPlanRaw(plan.copyWith());
    });

    void workoutTest(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          try {
            await body(tester);
          } finally {
            await closeStorageWithFrames(tester, hive.close);
          }
        });

    Future<void> seed(int week, {required bool completed}) =>
        HiveService.putSessionRaw(
          WorkoutSession(
            id: 'week-$week',
            planId: plan.id,
            planName: plan.name,
            date: DateTime(2026, 9, week),
            weekNumber: week,
            isCompleted: completed,
            durationSeconds: 0,
            exercises: [
              Exercise(name: 'Squat', sets: [gym.Set(reps: 5, weight: 100)]),
            ],
          ),
        );

    Future<void> open(
      WidgetTester tester, {
      Future<Object?> Function(MethodCall)? notificationHandler,
      WorkoutSessionProvider? provider,
      bool pushed = false,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        notifications,
        notificationHandler ?? (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          notifications,
          null,
        ),
      );
      await tester.runAsync(() => hive.prepareTraining([plan]));
      sessions = provider ?? WorkoutSessionProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
            ChangeNotifierProvider.value(value: sessions),
          ],
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
            home:
                pushed
                    ? Builder(
                      builder:
                          (context) => Scaffold(
                            body: TextButton(
                              onPressed:
                                  () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder:
                                          (_) => WorkoutScreen(
                                            plan: plan,
                                            planIndex: 0,
                                          ),
                                    ),
                                  ),
                              child: const Text('Open workout'),
                            ),
                          ),
                    )
                    : WorkoutScreen(plan: plan, planIndex: 0),
          ),
        ),
      );
      if (pushed) {
        await tester.tap(find.text('Open workout'));
      }
      await pumpWithStorage(tester);
    }

    // The screen's deletes write to Hive inside the test's fake-async zone.
    // Closing that box after the zone is gone never completes, which would
    // hang tearDownAll, so close it here and let setUp reopen it.
    Future<void> releaseSessions(WidgetTester tester) async {
      var closed = false;
      Hive.box<WorkoutSession>(
        HiveService.sessionsBox,
      ).close().then((_) => closed = true);
      for (var attempt = 0; attempt < 50 && !closed; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(closed, isTrue);
    }

    Finder weekTab(int week) => find.descendant(
      of: find.byType(TrainingBlockStrip),
      matching: find.text('Week $week'),
    );

    WorkoutSession oldRunning() {
      final start = DateTime.now().subtract(const Duration(minutes: 20));
      return WorkoutSession(
        id: 'old-running',
        planId: 'push',
        planName: 'Push Day',
        splitId: 'another-split',
        weekNumber: 6,
        date: start,
        startedAt: start,
        timerStartedAt: start,
        durationSeconds: 120,
        isCompleted: false,
        exercises: [
          Exercise(name: 'Bench Press', sets: [gym.Set(reps: 8, weight: 60)]),
        ],
      );
    }

    Future<void> waitForTimerConflict(
      WidgetTester tester, {
      String? planLabel,
    }) async {
      // Starting remains busy behind the confirmation, so its progress
      // indicator intentionally keeps scheduling frames until we answer.
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final confirmation =
            planLabel == null
                ? find.text('Pause and start')
                : find.textContaining(planLabel);
        if (confirmation.evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 300));
          return;
        }
      }
      fail('The timer conflict confirmation did not open.');
    }

    workoutTest('a failed first draft write retries with its assigned ID', (
      tester,
    ) async {
      final failing = _FailFirstWriteProvider();
      await open(tester, provider: failing);
      await tester.tap(find.text('Start'));
      await pumpWithStorage(tester);
      expect(find.text('Retry'), findsOneWidget);
      expect(HiveService.getSessionById(failing.assignedId!), isNull);
      await tester.tap(find.text('Retry'));
      await pumpWithStorage(tester);
      final saved = HiveService.getSessionById(failing.assignedId!)!;
      expect(saved.exercises.single.name, 'Squat');
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.text('Start'));
      await pumpWithStorage(tester);
      expect(HiveService.getRunningSession()!.id, saved.id);
      await tester.pumpWidget(const SizedBox.shrink());
      await releaseSessions(tester);
    });

    workoutTest(
      'Start applies a notification pause before checking conflicts',
      (tester) async {
        await tester.runAsync(() => HiveService.putSessionRaw(oldRunning()));
        await open(
          tester,
          notificationHandler: (call) async {
            if (call.method == 'requestPermission') return true;
            if (call.method != 'snapshot') return null;
            return {
              'sessionId': 'old-running',
              'planName': 'Push Day',
              'weekNumber': 6,
              'accumulatedSeconds': 600,
              'running': false,
              'actionRevision': DateTime.now().millisecondsSinceEpoch,
            };
          },
        );
        await tester.tap(find.text('Start'));
        await pumpWithStorage(tester);

        expect(find.text('Pause and start'), findsNothing);
        expect(find.byTooltip('Pause workout'), findsOneWidget);
        final old = HiveService.getSessionById('old-running')!;
        expect(old.isTimerRunning, isFalse);
        expect(old.durationSeconds, 600);
        expect(old.exercises.single.sets.single.weight, 60);
        expect(HiveService.getRunningSession()!.planName, plan.name);
        await tester.pumpWidget(const SizedBox.shrink());
        await releaseSessions(tester);
      },
    );

    workoutTest('an old running flag can be paused without losing its sets', (
      tester,
    ) async {
      await tester.runAsync(() => HiveService.putSessionRaw(oldRunning()));
      final calls = <String>[];
      await open(
        tester,
        notificationHandler: (call) async {
          calls.add(call.method);
          return call.method == 'requestPermission' ? true : null;
        },
      );
      await tester.tap(find.text('Start'));
      await waitForTimerConflict(tester);
      expect(find.textContaining('Push Day, Block 1 · Week 6'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await pumpWithStorage(tester);
      expect(HiveService.getSessionById('old-running')!.isTimerRunning, isTrue);
      expect(find.text('Start'), findsOneWidget);

      await tester.tap(find.text('Start'));
      await waitForTimerConflict(tester);
      // Preserve any newer sets that arrive while the confirmation is open.
      await tester.runAsync(
        () => HiveService.putSessionRaw(
          oldRunning().copyWith(
            exercises: [
              Exercise(
                name: 'Bench Press',
                sets: [gym.Set(reps: 9, weight: 65)],
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Pause and start'));
      await pumpWithStorage(tester);
      final old = HiveService.getSessionById('old-running')!;
      expect(old.isTimerRunning, isFalse);
      expect(old.isCompleted, isFalse);
      expect(old.durationSeconds, greaterThanOrEqualTo(1320));
      expect(old.exercises.single.sets.single.weight, 65);
      expect(old.exercises.single.sets.single.reps, 9);
      expect(
        HiveService.getSessions().where((s) => s.isTimerRunning),
        hasLength(1),
      );
      expect(HiveService.getRunningSession()!.planName, plan.name);
      expect(calls, containsAllInOrder(['pause', 'show']));
      expect(find.byTooltip('Pause workout'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await releaseSessions(tester);
    });

    workoutTest('a failed pause cannot start a second running timer', (
      tester,
    ) async {
      await tester.runAsync(() => HiveService.putSessionRaw(oldRunning()));
      await open(tester, provider: _FailingPauseProvider());
      await tester.tap(find.text('Start'));
      await waitForTimerConflict(tester);
      await tester.tap(find.text('Pause and start'));
      await pumpWithStorage(tester);
      expect(find.textContaining('Could not change the timer'), findsOneWidget);
      expect(HiveService.getRunningSession()!.id, 'old-running');
      expect(
        HiveService.getSessions().where((s) => s.isTimerRunning),
        hasLength(1),
      );
      expect(find.text('Start'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await releaseSessions(tester);
    });

    workoutTest('Start resolves every saved running timer before starting', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await HiveService.putSessionRaw(oldRunning());
        await HiveService.putSessionRaw(
          oldRunning().copyWith(
            id: 'second-running',
            planName: 'Pull Day',
            date: DateTime.now(),
          ),
        );
      });
      await open(tester);
      await tester.tap(find.text('Start'));
      await waitForTimerConflict(
        tester,
        planLabel: 'Pull Day, Block 1 · Week 6',
      );
      await tester.tap(find.text('Pause and start'));
      await waitForTimerConflict(
        tester,
        planLabel: 'Push Day, Block 1 · Week 6',
      );
      await tester.tap(find.text('Pause and start'));
      await pumpWithStorage(tester);
      expect(
        HiveService.getSessions().where((s) => s.isTimerRunning),
        hasLength(1),
      );
      expect(HiveService.getRunningSession()!.planName, plan.name);
      await tester.pumpWidget(const SizedBox.shrink());
      await releaseSessions(tester);
    });

    for (final change in ['sets', 'completed', 'deleted']) {
      workoutTest(
        'Start respects current draft $change changed during confirmation',
        (tester) async {
          await tester.runAsync(() => HiveService.putSessionRaw(oldRunning()));
          await open(tester, pushed: change == 'deleted');
          await tester.tap(find.text('Start'));
          await waitForTimerConflict(tester);
          final current =
              HiveService.getSessionForPlanAndWeek(plan.name, 1, null)!;
          await tester.runAsync(
            () => HiveService.putSessionRaw(
              current.copyWith(
                isCompleted: change == 'completed',
                deletedAt: change == 'deleted' ? DateTime.now() : null,
                exercises: [
                  Exercise(
                    name: 'Squat',
                    sets: [gym.Set(reps: 7, weight: 110)],
                  ),
                ],
              ),
            ),
          );
          await tester.tap(find.text('Pause and start'));
          await pumpWithStorage(tester);
          final saved = HiveService.getSessionById(current.id!)!;
          expect(saved.exercises.single.sets.single.weight, 110);
          expect(saved.isCompleted, change == 'completed');
          expect(saved.deletedAt != null, change == 'deleted');
          expect(saved.isTimerRunning, change == 'sets');
          if (change == 'deleted') {
            await tester.tap(find.byTooltip('Back'));
            await pumpWithStorage(tester);
            expect(find.text('Open workout'), findsOneWidget);
            expect(
              HiveService.getSessionById(current.id!)!.deletedAt,
              isNotNull,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await releaseSessions(tester);
        },
      );
    }

    workoutTest(
      'empty supplied weeks remain available and the block menu has no week actions',
      (tester) async {
        await tester.runAsync(() => seed(1, completed: true));
        await open(tester);
        expect(weekTab(2), findsOneWidget);
        await tester.tap(find.text('Block 1'));
        await tester.pumpAndSettle();
        expect(find.text('Delete week'), findsNothing);
        expect(find.text('Rename week'), findsNothing);
        expect(
          find.byTooltip('Complete this block to add a week'),
          findsOneWidget,
        );
        expect(HiveService.getSessionById('week-1')!.deletedAt, isNull);
      },
    );
    workoutTest('browsing a supplied week keeps its saved incomplete draft', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seed(1, completed: true);
        await seed(2, completed: false);
      });
      await open(tester);
      await tester.tap(weekTab(1));
      await pumpWithStorage(tester);
      expect(HiveService.getSessionById('week-2')!.deletedAt, isNull);
      expect(HiveService.getSessionById('week-1')!.deletedAt, isNull);
      expect(weekTab(2), findsOneWidget);
    });
    workoutTest(
      'deleting a historical log keeps its supplied week and remaining history',
      (tester) async {
        await tester.runAsync(() async {
          await seed(1, completed: true);
          await seed(2, completed: true);
        });
        await open(tester);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => sessions.deleteSession('week-1'));
        await pumpWithStorage(tester);
        expect(weekTab(1), findsOneWidget);
        expect(weekTab(2), findsOneWidget);
        expect(HiveService.getSessionById('week-1')!.deletedAt, isNotNull);
        expect(sessions.sessions.map((s) => s.id), isNot(contains('week-1')));
        expect(sessions.sessions.map((s) => s.id), contains('week-2'));
      },
    );
    workoutTest(
      'opening block actions on empty structure never deletes or logs a week',
      (tester) async {
        await open(tester);
        final ids =
            HiveService.getAllTrainingWeeksRaw().map((w) => w.id).toSet();
        await tester.tap(find.text('Block 1'));
        await tester.pumpAndSettle();
        expect(find.text('Create block'), findsOneWidget);
        expect(find.text('Delete week'), findsNothing);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(
          HiveService.getAllTrainingWeeksRaw().map((w) => w.id).toSet(),
          ids,
        );
        expect(HiveService.getAllSessionsRaw(), isEmpty);
      },
    );
  });
}

class _FailingPauseProvider extends WorkoutSessionProvider {
  @override
  Future<void> upsertSession(WorkoutSession session) async {
    if (session.id == 'old-running' && !session.isTimerRunning) {
      throw StateError('disk full');
    }
    await super.upsertSession(session);
  }
}

class _FailFirstWriteProvider extends WorkoutSessionProvider {
  String? assignedId;
  bool _failed = false;

  @override
  Future<void> upsertSession(WorkoutSession session) async {
    if (!_failed) {
      _failed = true;
      // The initializer assigns identity before the first write.
      assignedId = session.id;
      throw StateError('disk full');
    }
    await super.upsertSession(session);
  }
}
