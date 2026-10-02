import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/dashboard_screen.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/intro_screen.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/dashboard/progression_sparkline.dart';
import 'package:gymapp/widgets/history/history_journal_data.dart';
import 'package:gymapp/widgets/history/history_journal_widgets.dart';
import 'package:gymapp/widgets/history/workout_details_widgets.dart';
import 'package:gymapp/widgets/home/home_plan_row.dart';
import 'package:gymapp/widgets/statistics/statistics_widgets.dart';
import 'package:gymapp/widgets/workout/workout_dialogs.dart';

import 'support/hive_test_harness.dart';
import 'support/test_fonts.dart';

void main() {
  final harness = HiveTestHarness();
  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
    await harness.open();
  });
  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });
  tearDownAll(() async {
    await harness.close();
    await Supabase.instance.dispose();
  });

  WorkoutPlan plan({String name = 'Push day'}) => WorkoutPlan(
    id: 'plan-1',
    name: name,
    exercises: [ExerciseTemplate(name: 'Bench press', sets: 1)],
  );
  WorkoutSession session({
    bool completed = true,
    String id = 'selected',
    int week = 7,
  }) => WorkoutSession(
    id: id,
    planId: 'plan-1',
    planName: 'Push day',
    weekNumber: week,
    date: DateTime(2026, 10, 1),
    isCompleted: completed,
    exercises: [
      Exercise(name: 'Selected exercise', sets: [gym.Set(weight: 80, reps: 8)]),
    ],
  );

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    List<WorkoutPlan> plans = const [],
    List<WorkoutSession> sessions = const [],
    WorkoutSessionProvider? sessionProvider,
    double scale = 1,
    Size size = const Size(1200, 900),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>(
            create: (_) => _Plans(plans),
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>(
            create: (_) => sessionProvider ?? _Sessions(sessions),
          ),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF00A8FF), Brightness.dark),
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ordinary plan overflow is named, 48dp, and independent of opening',
    (tester) async {
      var opened = 0;
      var actions = 0;
      final semantics = tester.ensureSemantics();
      await pumpScreen(
        tester,
        Scaffold(
          body: HomePlanRow(
            plan: plan(),
            isNext: true,
            onOpen: () => opened++,
            onShowActions: () => actions++,
          ),
        ),
        size: const Size(390, 800),
        scale: 2,
      );
      final button = find.byTooltip('Actions for Push Day');
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(button).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      await tester.tap(button);
      await tester.pump();
      expect(actions, 1);
      expect(opened, 0);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final kind in ['existing', 'renamed', 'deleted']) {
    testWidgets('Dashboard views the exact completed workout with $kind plan', (
      tester,
    ) async {
      final selected = session();
      final plans =
          kind == 'deleted'
              ? <WorkoutPlan>[]
              : [plan(name: kind == 'renamed' ? 'Renamed plan' : 'Push day')];
      await pumpScreen(
        tester,
        const DashboardScreen(),
        plans: plans,
        sessions: [selected],
      );
      expect(find.text('Resume'), findsNothing);
      await tester.tap(find.text('View workout'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkoutDetailsScreen>(find.byType(WorkoutDetailsScreen))
            .sessionIdentity,
        selected.id,
      );
      expect(find.text('Selected exercise'), findsOneWidget);
      expect(find.byType(WorkoutScreen), findsNothing);
    });
  }

  for (final kind in ['existing', 'renamed', 'deleted']) {
    testWidgets(
      'Dashboard resumes the selected draft with $kind plan and retains identity',
      (tester) async {
        final selected = session(completed: false);
        final competing = selected.copyWith(
          id: 'competing',
          date: DateTime(2026, 10, 2),
          exercises: [
            Exercise(
              name: 'Wrong exercise',
              sets: [gym.Set(weight: 20, reps: 5)],
            ),
          ],
        );
        await tester.runAsync(() async {
          await Hive.box<WorkoutSession>(
            HiveService.sessionsBox,
          ).put(selected.id, selected);
          await Hive.box<WorkoutSession>(
            HiveService.sessionsBox,
          ).put(competing.id, competing);
        });
        final plans =
            kind == 'deleted'
                ? <WorkoutPlan>[]
                : [plan(name: kind == 'renamed' ? 'Renamed plan' : 'Push day')];
        final provider = _Sessions([selected]);
        await pumpScreen(
          tester,
          const DashboardScreen(),
          plans: plans,
          sessionProvider: provider,
        );
        await tester.tap(find.text('Resume'));
        await tester.pumpAndSettle();
        final workout = tester.widget<WorkoutScreen>(
          find.byType(WorkoutScreen),
        );
        expect(workout.initialSession?.id, 'selected');
        expect(find.text('Selected exercise'), findsOneWidget);
        expect(find.text('Wrong exercise'), findsNothing);
        provider.notifyListeners();
        await tester.pump();
        expect(find.text('Selected exercise'), findsOneWidget);
        expect(find.text('Wrong exercise'), findsNothing);
      },
    );
  }

  testWidgets(
    'Finish explains the Start prerequisite beside the disabled button',
    (tester) async {
      await pumpScreen(
        tester,
        WorkoutScreen(plan: plan(), planIndex: 0),
        plans: [plan()],
        size: const Size(390, 800),
      );
      expect(find.textContaining('Tap Start in the toolbar'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Finish workout'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('week rename reports invalid input and submits with Done', (
    tester,
  ) async {
    int? renamed;
    await pumpScreen(
      tester,
      Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed:
                    () => WorkoutDialogs.showRenameWeekDialog(
                      context,
                      currentWeek: 7,
                      onRename: (value) => renamed = value,
                    ),
                child: const Text('Open rename'),
              ),
            ),
      ),
    );
    await tester.tap(find.text('Open rename'));
    await tester.pumpAndSettle();
    for (final invalid in ['', '0', 'abc']) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        find.text('Enter a whole number greater than zero.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
        isNotNull,
      );
      expect(renamed, isNull);
    }
    await tester.enterText(find.byType(TextField), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(renamed, 12);
    expect(find.text('Rename week'), findsNothing);
  });

  testWidgets('sparkline exposes rise and fall in session order', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(
      tester,
      const Scaffold(
        body: ProgressionSparkline(
          exercise: 'Bench press',
          values: [80, 100, 90],
        ),
      ),
    );
    final node = tester.getSemantics(
      find.bySemanticsLabel('Bench press maximum weight by session'),
    );
    expect(
      node.value,
      'Oldest to newest. Session 1: 80 kilograms; Session 2: 100 kilograms; Session 3: 90 kilograms',
    );
    semantics.dispose();
  });

  testWidgets('Plan editor Back has button semantics and a name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester, const PlanEditorScreen.create());
    final back = find.byTooltip('Back');
    expect(back, findsOneWidget);
    expect(
      tester.getSemantics(back).getSemanticsData().flagsCollection.isButton,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets(
    'Intro announces page position and exposes its title as a heading',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(
        tester,
        IntroScreen(onFinish: () async {}),
        size: const Size(390, 800),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Page 1 of 2'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.text('Make a plan that fits you'))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Page 2 of 2'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('History and Statistics headings have heading roles', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(
      tester,
      const Scaffold(
        body: Column(
          children: [
            HistoryMonthHeader(
              group: HistoryMonthGroup(year: 2026, month: 10, workouts: []),
            ),
            StatisticsSectionHeader(title: 'Training frequency'),
          ],
        ),
      ),
    );
    for (final title in ['October 2026', 'Training frequency']) {
      expect(
        tester
            .getSemantics(find.text(title))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
    }
    semantics.dispose();
  });

  testWidgets('saved sets expose contextual values, units, and PRs', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(
      tester,
      Scaffold(
        body: WorkoutExerciseDetails(
          exercise: Exercise(
            name: 'Bench press',
            sets: [gym.Set(weight: 100, reps: 8, rpe: 9, note: 'PR')],
          ),
          weightUnit: 'lbs',
        ),
      ),
    );
    final weight = tester.getSemantics(find.bySemanticsLabel('Set 1 weight'));
    expect(weight.value, startsWith('220.5 pounds'));
    expect(tester.getSemantics(find.bySemanticsLabel('Set 1 reps')).value, '8');
    expect(tester.getSemantics(find.bySemanticsLabel('Set 1 RPE')).value, '9');
    semantics.dispose();
  });
}

class _Plans extends WorkoutPlanProvider {
  final List<WorkoutPlan> values;
  _Plans(this.values);
  @override
  List<WorkoutPlan> get plans => values;
}

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> values;
  _Sessions(this.values);
  @override
  List<WorkoutSession> get sessions => values;
}
