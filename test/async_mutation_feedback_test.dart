import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart' as gym;
import 'package:gymapp/models/split.dart' as gym_split;
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/screens/intro_screen.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/screens/settings_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/widgets/workout/exercise_card.dart';

import 'support/hive_test_harness.dart';

void main() {
  final harness = HiveTestHarness();
  final plan = WorkoutPlan(
    id: 'plan',
    name: 'Strength',
    splitId: 'split',
    exercises: [ExerciseTemplate(name: 'Squat', sets: 1)],
  );
  WorkoutSession draft() => WorkoutSession(
    id: 'draft',
    planId: plan.id,
    planName: plan.name,
    splitId: 'split',
    weekNumber: 1,
    date: DateTime(2026),
    isCompleted: false,
    exercises: [
      Exercise(name: 'Squat', sets: [gym.Set(reps: 5, weight: 60)]),
    ],
  );

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
    );
    await harness.open(includeSplits: true);
    await HiveService.putSplitRaw(
      gym_split.Split(
        id: 'split',
        name: 'Strength split',
        createdAt: DateTime(2026),
      ),
    );
  });
  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
  });
  tearDownAll(harness.close);

  Widget host(Widget screen, {_Plans? plans, _Sessions? sessions}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkoutPlanProvider>(
            create: (_) => plans ?? _Plans([plan]),
          ),
          ChangeNotifierProvider<WorkoutSessionProvider>(
            create: (_) => sessions ?? _Sessions(),
          ),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
          ChangeNotifierProvider<SplitProvider>(
            create: (_) => SplitProvider(userIdProvider: () => null),
          ),
          ChangeNotifierProvider<UpdateProvider>(create: (_) => _Updates()),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
          home: screen,
        ),
      );

  testWidgets(
    'plan save guards repeat taps and keeps the editable draft on failure',
    (tester) async {
      final plans = _Plans([plan]);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PlanEditorScreen.edit(plan),
                          ),
                        ),
                    child: const Text('Open editor'),
                  ),
            ),
          ),
          plans: plans,
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My strength plan');
      await tester.tap(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(plans.writes.length, 1);
      expect(find.text('Saving plan'), findsOneWidget);
      expect(find.text('Plan saved'), findsNothing);
      plans.pending.completeError(StateError('storage unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your edits are still here'), findsOneWidget);
      expect(find.text('My strength plan'), findsOneWidget);
      plans.pending = Completer<void>();
      await tester.tap(find.text('Save'));
      expect(plans.writes.length, 2);
      plans.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Plan saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copy waits for storage and retries the same copy after failure',
    (tester) async {
      final plans = _Plans([plan]);
      await tester.pumpWidget(host(const HomeScreen(), plans: plans));
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plan actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate plan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(plans.writes.length, 1);
      expect(find.text('Copying plan'), findsOneWidget);
      expect(find.text('Plan copied'), findsNothing);
      plans.pending.completeError(StateError('storage unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Try again'), findsOneWidget);
      plans.pending = Completer<void>();
      await tester.tap(find.text('Duplicate'));
      await tester.tap(find.text('Duplicate'));
      await tester.pump();
      expect(plans.writes.length, 2);
      expect(identical(plans.writes[0], plans.writes[1]), isTrue);
      plans.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Plan copied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings load guards repeat submission and retains failed confirmation',
    (tester) async {
      var calls = 0;
      var pending = Completer<void>();
      await tester.pumpWidget(
        host(
          SettingsScreen(
            onLoadSampleData: () {
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Load sample data'));
      await tester.tap(find.text('Load sample data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      await tester.tap(find.text('Load'));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Loading sample data'), findsWidgets);
      expect(find.text('Sample data refreshed'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Load sample data?'), findsOneWidget);
      pending.completeError(StateError('storage unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Try again or cancel'), findsOneWidget);
      pending = Completer<void>();
      await tester.tap(find.text('Load'));
      expect(calls, 2);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sample data refreshed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'color save retains selection and deletion retains confirmation on failure',
    (tester) async {
      final plans = _Plans([plan]);
      await tester.pumpWidget(host(const HomeScreen(), plans: plans));
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plan actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change color'));
      await tester.pumpAndSettle();
      final swatch = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Plan color 2',
      );
      await tester.tap(swatch);
      await tester.tap(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(plans.writes.length, 1);
      expect(find.text('Saving color'), findsOneWidget);
      plans.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(swatch).properties.selected, isTrue);
      expect(
        find.textContaining('Your selection is still here'),
        findsOneWidget,
      );
      plans.pending = Completer<void>();
      await tester.tap(find.text('Save'));
      plans.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Plan color saved'), findsOneWidget);

      plans.pending = Completer<void>();
      await tester.tap(find.byTooltip('Plan actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(plans.deleted, ['plan']);
      expect(find.text('Deleting plan'), findsOneWidget);
      plans.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.text('Delete plan?'), findsOneWidget);
      expect(find.textContaining('Could not delete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear guards repeated taps, reconciles partial failure and allows retry',
    (tester) async {
      var calls = 0;
      var pending = Completer<void>();
      final plans = _Plans([plan]);
      await tester.pumpWidget(
        host(
          SettingsScreen(
            onClearData: (_) {
              calls++;
              return pending.future;
            },
          ),
          plans: plans,
        ),
      );
      await tester.ensureVisible(find.text('Clear current split data'));
      await tester.tap(find.text('Clear current split data'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Clear split data');
      final reloadsBefore = plans.reloads;
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Clearing split data'), findsWidgets);
      pending.completeError(StateError('partial failure'));
      await tester.pumpAndSettle();
      expect(plans.reloads, greaterThan(reloadsBefore));
      expect(find.textContaining('Try again or cancel'), findsOneWidget);
      pending = Completer<void>();
      await tester.tap(button);
      expect(calls, 2);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Data cleared for "Strength split"'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'autosave serializes edits, survives failure, and retries the latest draft',
    (tester) async {
      await tester.runAsync(
        () => Hive.box<WorkoutSession>(
          HiveService.sessionsBox,
        ).put('draft', draft()),
      );
      final sessions = _Sessions();
      await tester.pumpWidget(
        host(WorkoutScreen(plan: plan, planIndex: 0), sessions: sessions),
      );
      await tester.pump();
      final card = tester.widget<ExerciseCard>(find.byType(ExerciseCard));
      card.onAddSet(0);
      card.onAddSet(0);
      await tester.pump();
      expect(sessions.writes.length, 1);
      expect(find.text('Saving workout'), findsOneWidget);
      sessions.pending.complete();
      sessions.pending = Completer<void>();
      await tester.pump();
      expect(sessions.writes.length, 2);
      expect(sessions.writes.last.exercises.single.sets.length, 3);
      sessions.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ExerciseCard>(find.byType(ExerciseCard))
            .exercise
            .sets
            .length,
        3,
      );
      expect(find.text('Retry'), findsOneWidget);
      sessions.pending = Completer<void>();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(sessions.writes.length, 3);
      sessions.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timer rejects repeated starts and preserves stopped state on storage failure',
    (tester) async {
      const channel = MethodChannel(
        'com.aalishms.opengym/workout_timer_notification',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'requestPermission' ? true : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.runAsync(
        () => Hive.box<WorkoutSession>(
          HiveService.sessionsBox,
        ).put('draft', draft()),
      );
      final sessions = _Sessions();
      await tester.pumpWidget(
        host(WorkoutScreen(plan: plan, planIndex: 0), sessions: sessions),
      );
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(sessions.writes.length, 1);
      expect(find.text('Starting workout'), findsOneWidget);
      sessions.pending.complete();
      sessions.pending = Completer<void>();
      await tester.pump();
      expect(sessions.writes.length, 2);
      sessions.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not change the timer'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      sessions.pending = Completer<void>();
      await tester.tap(find.text('Start'));
      sessions.pending.complete();
      sessions.pending = Completer<void>();
      await tester.pump();
      expect(sessions.writes.last.isTimerRunning, isTrue);
      sessions.pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);

      sessions.pending = Completer<void>();
      await tester.tap(find.text('Pause'));
      sessions.pending.complete();
      sessions.pending = Completer<void>();
      await tester.pump();
      expect(sessions.writes.last.isTimerRunning, isFalse);
      sessions.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('intro names progress and allows retry after failure', (
    tester,
  ) async {
    var calls = 0;
    var pending = Completer<void>();
    await tester.pumpWidget(
      host(
        IntroScreen(
          onFinish: () {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.tap(find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Saving your choice'), findsOneWidget);
    pending.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Try again'), findsOneWidget);
    pending = Completer<void>();
    await tester.tap(find.text('Skip'));
    expect(calls, 2);
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workout editor exposes a named saving live region and retains its draft',
    (tester) async {
      final sessions = _Sessions();
      await tester.pumpWidget(
        host(EditSessionScreen(session: draft()), sessions: sessions),
      );
      await tester.enterText(
        find.byKey(const ValueKey('workout-name-field')),
        'Edited workout',
      );
      await tester.tap(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(sessions.writes.length, 1);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Saving workout' &&
              widget.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
      sessions.pending.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.text('Edited workout'), findsOneWidget);
      expect(find.textContaining('Your edits are still here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Plans extends WorkoutPlanProvider {
  _Plans(this.values);
  final List<WorkoutPlan> values;
  final List<WorkoutPlan> writes = [];
  final List<String> deleted = [];
  int reloads = 0;
  Completer<void> pending = Completer<void>();
  @override
  List<WorkoutPlan> get plans => values;
  @override
  Future<void> addPlan(WorkoutPlan plan) {
    writes.add(plan);
    return pending.future;
  }

  @override
  Future<void> updatePlan(WorkoutPlan plan) => addPlan(plan);
  @override
  Future<void> deletePlan(String id) {
    deleted.add(id);
    return pending.future;
  }

  @override
  void loadPlans() {
    reloads++;
    super.loadPlans();
  }
}

class _Sessions extends WorkoutSessionProvider {
  final List<WorkoutSession> writes = [];
  Completer<void> pending = Completer<void>();
  @override
  Future<void> upsertSession(WorkoutSession session) async {
    writes.add(session);
    await pending.future;
    notifyListeners();
  }
}

class _Updates extends UpdateProvider {
  @override
  Future<void> loadInstalledVersion() async {}
}
