import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
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
import 'package:gymapp/widgets/underline_tab_strip.dart';

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
      weekNumber: 1,
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

    expect(snapshot.isRunning, isTrue);
    expect(snapshot.elapsedSeconds(DateTime(2026, 9, 5, 10, 1, 10)), 100);
  });

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

  group('Delete week', () {
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
      await hive.open();
    });
    tearDownAll(hive.close);

    setUp(() async {
      if (!Hive.isBoxOpen(HiveService.sessionsBox)) {
        await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
      }
      await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
      await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
      await HiveService.putPlanRaw(plan);
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

    Future<void> open(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        notifications,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          notifications,
          null,
        ),
      );
      sessions = WorkoutSessionProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
            ChangeNotifierProvider.value(value: sessions),
          ],
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF008D8D), Brightness.light),
            home: WorkoutScreen(plan: plan, planIndex: 0),
          ),
        ),
      );
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
      of: find.byType(UnderlineTabStrip),
      matching: find.text('Week $week'),
    );

    Future<void> deleteWeek(WidgetTester tester, int week) async {
      await tester.longPress(weekTab(week));
      await tester.pumpAndSettle();
      expect(find.text('Rename week'), findsOneWidget);
      await tester.tap(find.text('Delete week'));
      await pumpWithStorage(tester);
    }

    Future<void> confirm(WidgetTester tester) async {
      expect(find.text('Delete week?'), findsOneWidget);
      expect(find.text('Discard workout?'), findsNothing);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await pumpWithStorage(tester);
      expect(find.text('Delete week?'), findsNothing);
    }

    testWidgets('the current empty week is removed without a dialog', (
      tester,
    ) async {
      await tester.runAsync(() => seed(1, completed: true));
      await open(tester);
      expect(weekTab(2), findsOneWidget);

      await deleteWeek(tester, 2);

      expect(find.byType(AlertDialog), findsNothing);
      expect(weekTab(2), findsNothing);
      expect(weekTab(1), findsOneWidget);
      // The logged week next to it is untouched.
      expect(HiveService.getSessionById('week-1')!.deletedAt, isNull);
    });

    testWidgets('the current week with sets in progress is tombstoned', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seed(1, completed: true);
        await seed(2, completed: false);
      });
      await open(tester);
      expect(weekTab(2), findsOneWidget);

      await deleteWeek(tester, 2);
      await confirm(tester);

      expect(weekTab(2), findsNothing);
      expect(HiveService.getSessionById('week-2')!.deletedAt, isNotNull);
      expect(HiveService.getSessionById('week-1')!.deletedAt, isNull);
      await releaseSessions(tester);
    });

    testWidgets('a logged past week leaves the tabs and the provider', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seed(1, completed: true);
        await seed(2, completed: true);
      });
      await open(tester);
      expect(sessions.sessions.map((s) => s.id), contains('week-1'));

      await deleteWeek(tester, 1);
      await confirm(tester);

      expect(weekTab(1), findsNothing);
      expect(weekTab(2), findsOneWidget);
      expect(HiveService.getSessionById('week-1')!.deletedAt, isNotNull);
      // History and Stats read the provider; no manual reload is needed.
      expect(sessions.sessions.map((s) => s.id), isNot(contains('week-1')));
      expect(sessions.sessions.map((s) => s.id), contains('week-2'));
      await releaseSessions(tester);
    });

    testWidgets('the only week explains why it stays', (tester) async {
      await open(tester);
      expect(weekTab(1), findsOneWidget);

      await deleteWeek(tester, 1);

      expect(find.text("You can't delete the only week"), findsOneWidget);
      expect(weekTab(1), findsOneWidget);
    });
  });
}
