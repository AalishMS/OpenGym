import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/navigation/workout_destination.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/exercise_catalog.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/utils/training_block_identity.dart';

import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

void main() {
  final harness = HiveTestHarness();

  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });
  setUp(() => harness.open());

  // Close Hive while the widget test can still pump its write zone.
  void workoutTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        try {
          await body(tester);
        } finally {
          await closeStorageWithFrames(tester, harness.close);
        }
      });

  final push = WorkoutPlan(
    id: 'push',
    name: 'Push',
    exercises: [
      ExerciseTemplate(name: 'Bench Press', sets: 2),
      ExerciseTemplate(name: 'Cable Fly', sets: 1),
    ],
  );
  final upper = WorkoutPlan(
    id: 'upper',
    name: 'Upper',
    exercises: [
      ExerciseTemplate(name: 'bench press', sets: 3),
      ExerciseTemplate(name: 'Squat', sets: 3),
    ],
  );

  WorkoutSession log(
    String id,
    String planId,
    DateTime date,
    List<Exercise> exercises,
  ) => WorkoutSession(
    id: id,
    planId: planId,
    planName: planId == 'push' ? 'Push' : 'Upper',
    date: date,
    weekNumber: 1,
    exercises: exercises,
  );

  /// Push Week 1 is logged, so the logger opens Week 2 seeded from it.
  Future<void> open(
    WidgetTester tester, {
    List<WorkoutSession> extra = const [],
    WorkoutDestination? destination,
    List<Exercise>? week1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final sessions = Hive.box<WorkoutSession>(HiveService.sessionsBox);
      for (final plan in [push, upper]) {
        await Hive.box<WorkoutPlan>(HiveService.plansBox).put(plan.id, plan);
      }
      for (final session in [
        log(
          'push-1',
          'push',
          DateTime(2026, 1, 1),
          week1 ??
              [
                Exercise(
                  name: 'Bench Press',
                  sets: [Set(weight: 80, reps: 8), Set(weight: 75, reps: 10)],
                ),
                Exercise(name: 'Cable Fly', sets: [Set(weight: 20, reps: 12)]),
              ],
        ),
        ...extra,
      ]) {
        await sessions.put(session.id, session);
      }
      await harness.prepareTraining([push, upper]);
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
            destination: destination,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String exercise) async {
    await tester.tap(find.byTooltip('Exercise actions for $exercise'));
    await tester.pumpAndSettle();
  }

  List<String> names(Iterable<dynamic> exercises) => [
    for (final exercise in exercises) exercise.name as String,
  ];

  workoutTest('exercise menu keeps Delete last and offers Replace', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    final labels = [
      for (final item in tester.widgetList<PopupMenuItem<Object?>>(
        find.byWidgetPredicate((w) => w is PopupMenuItem),
      ))
        switch (item.child) {
          Text(:final data) => data,
          _ => null,
        },
    ];
    expect(labels, [
      'Exercise note',
      'Rename exercise',
      'Replace exercise',
      'Move down',
      'Delete exercise',
    ]);
  });

  workoutTest('the next week carries over last week\'s exercises', (
    tester,
  ) async {
    // Week 1 swapped Cable Fly for Dumbbell Fly and added Chest Dips at the end.
    await open(
      tester,
      week1: [
        Exercise(
          name: 'Bench Press',
          sets: [Set(weight: 80, reps: 8), Set(weight: 75, reps: 10)],
        ),
        Exercise(
          name: 'Dumbbell Fly',
          exerciseId: 'builtin:dumbbell-fly',
          sets: [Set(weight: 14, reps: 12)],
        ),
        Exercise(
          name: 'Chest Dips',
          exerciseId: 'builtin:chest-dips',
          sets: [Set(weight: 0, reps: 10), Set(weight: 0, reps: 9)],
        ),
      ],
    );
    expect(find.text('Dumbbell Fly'), findsOneWidget);
    expect(find.text('Chest Dips'), findsOneWidget);
    expect(find.text('Cable Fly'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Dumbbell Fly')).dy,
      lessThan(tester.getTopLeft(find.text('Chest Dips')).dy),
    );
    // Logging any value saves Week 2 with the carried lineup and its sets.
    await openMenu(tester, 'Chest Dips');
    await tester.tap(find.text('Exercise note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lean forward');
    await tester.tap(find.text('Save'));
    await pumpWithStorage(tester);
    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(draft.exercises.map((e) => e.exerciseId), [
      ExerciseCatalog.identity('Bench Press'),
      'builtin:dumbbell-fly',
      'builtin:chest-dips',
    ]);
    expect(draft.exercises[1].sets.single.weight, 14);
    expect(draft.exercises[2].sets, hasLength(2));
    expect(draft.planExerciseIds, [
      ExerciseCatalog.identity('Bench Press'),
      ExerciseCatalog.identity('Cable Fly'),
    ]);
    expect(tester.takeException(), isNull);
  });

  workoutTest('deleting an exercise from the current week says the next week '
      'will leave it out', (tester) async {
    await open(tester);
    await openMenu(tester, 'Cable Fly');
    await tester.tap(find.text('Delete exercise'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This will permanently delete "Cable Fly" and all its sets. '
        'Next week will start without it too.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await pumpWithStorage(tester);
    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(draft.exercises.map((e) => e.name), ['Bench Press']);
    // The plan still lists it; the draft remembers that it was dropped here.
    expect(draft.planExerciseIds, [
      ExerciseCatalog.identity('Bench Press'),
      ExerciseCatalog.identity('Cable Fly'),
    ]);
    expect(tester.takeException(), isNull);
  });

  workoutTest("renaming to another exercise's name offers a merge", (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Rename exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'plank');
    await tester.pump();
    // Plank is another movement: same name means same movement, a merge.
    expect(find.byKey(const ValueKey('rename-merge-note')), findsOneWidget);
    expect(find.text('Plank is already an exercise'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Merge'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Rename'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await pumpWithStorage(tester);

    // Cancelling keeps them apart, and keeps the lift weighted.
    expect(
      ExerciseCatalog.canonicalId('builtin:bench-press'),
      isNot('builtin:plank'),
    );
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('80 × 8'), findsOneWidget);
    expect(find.text('80 × 8 s'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  workoutTest('rename changes the name everywhere without rewriting logs', (
    tester,
  ) async {
    await open(tester);
    final loggedAt = HiveService.getSessionById('push-1')!.updatedAt;
    final planAt = HiveService.getPlanById('upper')!.updatedAt;
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Rename exercise'));
    await tester.pumpAndSettle();
    // Week 2 is still an unsaved preview, so only the Week 1 log counts.
    expect(
      find.textContaining('Used in 2 plans and 1 workout.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rename-merge-note')), findsNothing);

    await tester.enterText(find.byType(TextField), 'Flat bench press');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await pumpWithStorage(tester);

    expect(
      ExerciseCatalog.getById('builtin:bench-press')!.name,
      'Flat bench press',
    );
    // The workout shows the new name and still finds last week's sets.
    expect(find.text('Flat bench press'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('80 × 8'), findsOneWidget);
    // Every plan and log shows it, whatever name it stored.
    for (final e in [
      ...HiveService.getPlanById('push')!.exercises,
      ...HiveService.getPlanById('upper')!.exercises,
    ].where((e) => e.name.toLowerCase() == 'bench press')) {
      expect(ExerciseCatalog.label(e.name, e.exerciseId), 'Flat bench press');
    }
    final logged = HiveService.getSessionById('push-1')!.exercises.first;
    expect(
      ExerciseCatalog.label(logged.name, logged.exerciseId),
      'Flat bench press',
    );
    expect(logged.sets.first.weight, 80);
    expect(HiveService.getSessionById('push-1')!.updatedAt, loggedAt);
    expect(HiveService.getPlanById('upper')!.updatedAt, planAt);
    expect(tester.takeException(), isNull);
  });

  workoutTest('merging from the workout combines the two movements', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Cable Fly');
    await tester.tap(find.text('Rename exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Dumbbell Fly');
    await tester.pump();
    expect(find.byKey(const ValueKey('rename-merge-note')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
    await pumpWithStorage(tester);

    final fly = ExerciseCatalog.identity('Cable Fly');
    expect(fly, ExerciseCatalog.identity('Dumbbell Fly'));
    expect(find.text('Merged into Dumbbell Fly'), findsOneWidget);
    expect(find.text('Dumbbell Fly'), findsWidgets);
    expect(find.text('Cable Fly'), findsNothing);
    // The log keeps its sets and stored name; only what it resolves to moved.
    final logged = HiveService.getSessionById('push-1')!.exercises.last;
    expect(logged.name, 'Cable Fly');
    expect(logged.sets.single.weight, 20);
    expect(tester.takeException(), isNull);
  });

  workoutTest('replace uses the latest logged sets for the new exercise', (
    tester,
  ) async {
    await open(
      tester,
      extra: [
        log('upper-old', 'upper', DateTime(2026, 1, 2), [
          Exercise(name: 'Squat', sets: [Set(weight: 90, reps: 3)]),
        ]),
        log('upper-new', 'upper', DateTime(2026, 1, 9), [
          Exercise(
            name: 'Squat',
            sets: [Set(weight: 100, reps: 5, rpe: 8, note: 'Belt')],
            note: 'Old cue',
          ),
        ]),
      ],
    );
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Replace exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Replace Bench Press'), findsOneWidget);
    // A single choice closes the picker, so there is no selection footer.
    expect(find.text('Done'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'squat',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squat').first);
    await pumpWithStorage(tester);

    expect(find.text('Replace Bench Press'), findsNothing);
    // The swap is in the workout already; the plan is only changed on request.
    expect(find.text('Also change the plan?'), findsOneWidget);
    expect(
      find.text(
        'Squat replaced Bench Press in this workout. Change it in the Push '
        'plan too?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep plan'));
    await pumpWithStorage(tester);
    expect(find.text('Also change the plan?'), findsNothing);
    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(names(draft.exercises), ['Squat', 'Cable Fly']);
    final squat = draft.exercises.first;
    expect(squat.exerciseId, 'builtin:squat');
    expect(squat.note, isNull);
    // Two sets kept; both take the latest Squat performance in the split.
    expect(
      [for (final s in squat.sets) (s.weight, s.reps, s.rpe, s.note)],
      [(100.0, 5, null, null), (100.0, 5, null, null)],
    );
    // Keeping the plan leaves it, and what the draft recorded of it, alone.
    expect(names(HiveService.getPlanById('push')!.exercises), [
      'Bench Press',
      'Cable Fly',
    ]);
    expect(draft.planExerciseIds, [
      ExerciseCatalog.identity('Bench Press'),
      ExerciseCatalog.identity('Cable Fly'),
    ]);
    expect(tester.takeException(), isNull);
  });

  Future<void> replace(
    WidgetTester tester,
    String exercise, {
    required String search,
    required String pick,
  }) async {
    await openMenu(tester, exercise);
    await tester.tap(find.text('Replace exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      search,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(pick).first);
    await pumpWithStorage(tester);
  }

  workoutTest('after a swap, Change plan makes the same swap in the plan', (
    tester,
  ) async {
    await open(
      tester,
      extra: [
        log('upper-new', 'upper', DateTime(2026, 1, 9), [
          Exercise(name: 'Squat', sets: [Set(weight: 100, reps: 5)]),
        ]),
      ],
    );
    await replace(tester, 'Bench Press', search: 'squat', pick: 'Squat');
    await tester.tap(find.widgetWithText(FilledButton, 'Change plan'));
    await pumpWithStorage(tester);

    expect(find.text('Also change the plan?'), findsNothing);
    expect(find.text('Push plan now has Squat'), findsOneWidget);
    final plan = HiveService.getPlanById('push')!;
    expect(names(plan.exercises), ['Squat', 'Cable Fly']);
    final squat = plan.exercises.first;
    expect(squat.exerciseId, 'builtin:squat');
    // The plan's two sets, with the replacement's latest logged values.
    expect(squat.sets, 2);
    expect(
      [for (final t in squat.setTargets!) (t.reps, t.weight)],
      [(5, 100.0), (5, 100.0)],
    );
    // Only this plan changes, and the workout keeps what was swapped in.
    expect(names(HiveService.getPlanById('upper')!.exercises), [
      'bench press',
      'Squat',
    ]);
    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(names(draft.exercises), ['Squat', 'Cable Fly']);
    // The draft has seen the plan's swap, so next week does not read Squat
    // as an exercise the plan gained since.
    expect(draft.planExerciseIds, [
      'builtin:squat',
      ExerciseCatalog.identity('Cable Fly'),
    ]);
    expect(tester.takeException(), isNull);
  });

  workoutTest('a swap of an exercise the plan does not have asks nothing', (
    tester,
  ) async {
    // Week 1 swapped Cable Fly for Dumbbell Fly, so Week 2 carries an
    // exercise the plan never listed.
    await open(
      tester,
      week1: [
        Exercise(name: 'Bench Press', sets: [Set(weight: 80, reps: 8)]),
        Exercise(
          name: 'Dumbbell Fly',
          exerciseId: 'builtin:dumbbell-fly',
          sets: [Set(weight: 14, reps: 12)],
        ),
      ],
    );
    await replace(
      tester,
      'Dumbbell Fly',
      search: 'chest dips',
      pick: 'Chest Dips',
    );
    expect(find.text('Also change the plan?'), findsNothing);
    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(names(draft.exercises), ['Bench Press', 'Chest Dips']);
    expect(names(HiveService.getPlanById('push')!.exercises), [
      'Bench Press',
      'Cable Fly',
    ]);
    expect(tester.takeException(), isNull);
  });

  workoutTest('replace without history keeps reps and starts at weight 0', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Replace exercise'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'romanian',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Romanian Deadlift'));
    await pumpWithStorage(tester);

    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(draft.exercises.first.name, 'Romanian Deadlift');
    expect(
      [for (final s in draft.exercises.first.sets) (s.weight, s.reps)],
      [(0.0, 8), (0.0, 10)],
    );
  });

  workoutTest('replace refuses an exercise already in the workout', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Replace exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises'),
      'cable fly',
    );
    await tester.pumpAndSettle();
    final row = find.bySemanticsLabel(RegExp('^Cable Fly, .*already added'));
    expect(row, findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    await tester.tap(find.text('Cable Fly').last);
    await tester.pumpAndSettle();
    // Still choosing; nothing was swapped.
    expect(find.text('Replace Bench Press'), findsOneWidget);
    expect(
      HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split'),
      isNull,
    );
  });

  workoutTest('a completed log can be renamed but not replaced', (
    tester,
  ) async {
    await open(
      tester,
      destination: WorkoutDestination.week(
        'push',
        legacyTrainingWeekId('test-split', 1),
      ),
    );
    expect(find.text('Bench Press'), findsOneWidget);
    // Logged workouts are edited in place; swapping a movement is only for
    // a workout still being trained.
    await openMenu(tester, 'Bench Press');
    expect(find.text('Rename exercise'), findsOneWidget);
    expect(find.text('Replace exercise'), findsNothing);
  });
}
