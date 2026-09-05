import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/services/pr_tracking_service.dart';
import 'package:gymapp/services/workout_completion_service.dart';
import 'package:gymapp/services/workout_session_initializer.dart';

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
}
