import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/widgets/workout/workout_finish_summary.dart';

WorkoutSession session(
  String id,
  int day, {
  String plan = 'plan',
  String split = 'split',
  bool completed = true,
  List<Exercise> exercises = const [],
}) => WorkoutSession(
  id: id,
  date: DateTime(2026, 1, day),
  planName: 'Strength',
  planId: plan,
  splitId: split,
  isCompleted: completed,
  exercises: exercises,
);

void main() {
  test('mixed work excludes seconds from volume and ignores zero-rep rows', () {
    final work = WorkoutFinishWork.fromSession(
      session(
        'today',
        3,
        exercises: [
          Exercise(
            name: 'Bench Press',
            sets: [gym.Set(weight: 50, reps: 5), gym.Set(weight: 100, reps: 0)],
          ),
          Exercise(name: 'Push-up', sets: [gym.Set(weight: 0, reps: 12)]),
          Exercise(name: 'Plank', sets: [gym.Set(weight: 10, reps: 90)]),
        ],
      ),
    );
    expect(work.volume, 250);
    expect(work.sets, 3);
    expect(work.bodyweightReps, 12);
    expect(work.timedSeconds, 90);
  });

  test(
    'comparison selects only earlier completed workout in same plan and split',
    () {
      final previous = session('previous', 2);
      expect(
        WorkoutFinishWork.previous(session('today', 3), [
          session('future', 4),
          session('other', 2, plan: 'other'),
          session('split', 2, split: 'other'),
          session('draft', 2, completed: false),
          previous,
        ]),
        same(previous),
      );
    },
  );

  testWidgets(
    'empty summary gives honest empty state and can close at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showDialog<void>(
                        context: context,
                        builder:
                            (_) => WorkoutFinishSummary(
                              session: session('today', 3),
                              records: const [],
                              weightUnit: 'lbs',
                            ),
                      ),
                  child: const Text('Open'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Workout logged'), findsOneWidget);
      expect(find.text('No sets logged'), findsOneWidget);
      expect(find.textContaining('Volume load'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Workout logged'), findsNothing);
    },
  );
}
