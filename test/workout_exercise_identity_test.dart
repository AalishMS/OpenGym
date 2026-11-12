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
        log('push-1', 'push', DateTime(2026, 1, 1), [
          Exercise(
            name: 'Bench Press',
            sets: [Set(weight: 80, reps: 8), Set(weight: 75, reps: 10)],
          ),
          Exercise(name: 'Cable Fly', sets: [Set(weight: 20, reps: 12)]),
        ]),
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

  workoutTest('rename rejects changing reps to seconds before saving', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Rename exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Plank');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Timed exercises need a timed exercise name.'),
      findsOneWidget,
    );
    expect(find.text('Rename exercise'), findsOneWidget);
    expect(
      names(HiveService.getPlanById('push')!.exercises).first,
      'Bench Press',
    );
    expect(
      names(HiveService.getSessionById('push-1')!.exercises).first,
      'Bench Press',
    );
    expect(
      HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split'),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  workoutTest('rename everywhere updates plans, history and providers', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Rename exercise'));
    await tester.pumpAndSettle();

    final everywhere = find.byKey(const ValueKey('rename-everywhere'));
    expect(
      tester.widget<CheckboxListTile>(everywhere).value,
      isTrue,
      reason: 'Renaming everywhere is the default',
    );
    expect(find.text('Also rename in plans and past workouts'), findsOneWidget);
    // Week 2 is still an unsaved preview, so only the Week 1 log counts.
    expect(
      find.text('2 plans and 1 workout in this split use Bench Press.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rename-merge-note')), findsNothing);

    await tester.enterText(find.byType(TextField), 'Flat bench press');
    await tester.pump();
    await tester.tap(find.text('Rename'));
    await pumpWithStorage(tester);

    expect(names(HiveService.getPlanById('push')!.exercises), [
      'Flat bench press',
      'Cable Fly',
    ]);
    expect(names(HiveService.getPlanById('upper')!.exercises), [
      'Flat bench press',
      'Squat',
    ]);
    expect(HiveService.getPlanById('upper')!.dirty, isTrue);
    expect(names(HiveService.getSessionById('push-1')!.exercises), [
      'Flat bench press',
      'Cable Fly',
    ]);
    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(names(draft.exercises), ['Flat bench press', 'Cable Fly']);
    expect(draft.exercises.first.sets.first.weight, 80);

    // The renamed workout still finds last week's sets under the new name.
    expect(find.text('Flat bench press'), findsOneWidget);
    expect(find.text('80 × 8'), findsOneWidget);
    final context = tester.element(find.byType(WorkoutScreen));
    expect(
      context
          .read<WorkoutPlanProvider>()
          .plans
          .expand((plan) => plan.exercises)
          .where((e) => e.name == 'Flat bench press'),
      hasLength(2),
    );
    expect(
      names(context.read<WorkoutSessionProvider>().sessions.single.exercises),
      ['Flat bench press', 'Cable Fly'],
    );
    expect(tester.takeException(), isNull);
  });

  workoutTest('renaming to an existing name warns that histories merge', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Rename exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'squat');
    await tester.pump();
    expect(find.byKey(const ValueKey('rename-merge-note')), findsOneWidget);
    expect(
      find.text(
        'squat already exists, so the two histories and records will merge.',
      ),
      findsOneWidget,
    );
    // The note only applies while the rename reaches the other records.
    await tester.tap(find.byKey(const ValueKey('rename-everywhere')));
    await tester.pump();
    expect(find.byKey(const ValueKey('rename-merge-note')), findsNothing);
  });

  workoutTest('unchecked rename changes this workout only', (tester) async {
    await open(tester);
    await openMenu(tester, 'Bench Press');
    await tester.tap(find.text('Rename exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-everywhere')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Flat bench press');
    await tester.pump();
    await tester.tap(find.text('Rename'));
    await pumpWithStorage(tester);

    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(names(draft.exercises), ['Flat bench press', 'Cable Fly']);
    expect(names(HiveService.getPlanById('push')!.exercises), [
      'Bench Press',
      'Cable Fly',
    ]);
    expect(names(HiveService.getPlanById('upper')!.exercises), [
      'bench press',
      'Squat',
    ]);
    expect(names(HiveService.getSessionById('push-1')!.exercises), [
      'Bench Press',
      'Cable Fly',
    ]);
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
    final draft =
        HiveService.getSessionForPlanAndWeek('Push', 2, 'test-split')!;
    expect(names(draft.exercises), ['Squat', 'Cable Fly']);
    final squat = draft.exercises.first;
    expect(squat.note, isNull);
    // Two sets kept; both take the latest Squat performance in the split.
    expect(
      [for (final s in squat.sets) (s.weight, s.reps, s.rpe, s.note)],
      [(100.0, 5, null, null), (100.0, 5, null, null)],
    );
    // Other plans and logs are untouched.
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

  workoutTest('a completed log offers no exercise menu', (tester) async {
    await open(
      tester,
      destination: WorkoutDestination.week(
        'push',
        legacyTrainingWeekId('test-split', 1),
      ),
    );
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.byTooltip('Exercise actions for Bench Press'), findsNothing);
  });
}
