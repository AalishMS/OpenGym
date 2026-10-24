import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/navigation/app_navigation_observer.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/plan_editor_screen.dart';
import 'package:gymapp/screens/workout_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';

import 'support/hive_test_harness.dart';
import 'support/test_fonts.dart';

void main() {
  final hive = HiveTestHarness();
  const channel = MethodChannel(
    'com.aalishms.opengym/workout_timer_notification',
  );
  late WorkoutPlan plan;
  late WorkoutSession session;

  setUpAll(() async {
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
    );
    await hive.open(includeSplits: true);
  });
  tearDownAll(hive.close);
  setUp(() async {
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    plan = WorkoutPlan(
      id: 'push',
      name: 'Push',
      exercises: [ExerciseTemplate(name: 'Bench Press', sets: 1)],
    );
    session = WorkoutSession(
      id: 'draft',
      planId: plan.id,
      planName: plan.name,
      date: DateTime(2026),
      isCompleted: false,
      startedAt: DateTime(2026),
      durationSeconds: 60,
      exercises: [],
    );
    await HiveService.putPlanRaw(plan);
    await HiveService.putSessionRaw(session);
  });

  Future<void> openShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SplitProvider(userIdProvider: () => null),
          ),
          ChangeNotifierProvider(create: (_) => WorkoutPlanProvider()),
          ChangeNotifierProvider(create: (_) => WorkoutSessionProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ],
        child: MaterialApp(
          navigatorObservers: [AppNavigationObserver()],
          theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> notify(
    WidgetTester tester,
    int revision, {
    bool stop = false,
    bool settle = true,
  }) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('notificationIntent', {
          'action': stop ? 'stop' : 'open',
          'snapshot': {
            'sessionId': session.id,
            'planId': plan.id,
            'splitId': session.splitId,
            'planName': plan.name,
            'weekNumber': 1,
            'accumulatedSeconds': 60,
            'running': false,
            'actionRevision': revision,
            'pendingStop': stop,
          },
        }),
      ),
      (_) {},
    );
    if (settle) await tester.pumpAndSettle();
  }

  Finder allWorkouts() => find.byType(WorkoutScreen, skipOffstage: false);

  testWidgets('repeated notification opens leave one workout route', (
    tester,
  ) async {
    await openShell(tester);
    await notify(tester, 1);
    expect(allWorkouts(), findsOneWidget);
    await notify(tester, 2);
    expect(allWorkouts(), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(allWorkouts(), findsNothing);
    expect(find.text('Start workout'), findsOneWidget);
  });

  testWidgets('stop notification reuses an already open workout', (
    tester,
  ) async {
    await openShell(tester);
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    await notify(tester, 1, stop: true);
    expect(allWorkouts(), findsOneWidget);
    expect(find.text('Log workout?'), findsOneWidget);
  });

  testWidgets('rapid notification intents do not race the first route build', (
    tester,
  ) async {
    await openShell(tester);
    await notify(tester, 1, settle: false);
    await notify(tester, 2, settle: false);
    await tester.pumpAndSettle();
    expect(allWorkouts(), findsOneWidget);
  });

  testWidgets('a different workout leaves through its normal Back flow', (
    tester,
  ) async {
    final other = WorkoutPlan(id: 'pull', name: 'Pull', exercises: []);
    await tester.runAsync(() => HiveService.putPlanRaw(other));
    await openShell(tester);
    await notify(tester, 1);
    Navigator.of(tester.element(find.byType(WorkoutScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutScreen(plan: other, planIndex: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(allWorkouts(), findsNWidgets(2));
    await notify(tester, 2);
    expect(allWorkouts(), findsOneWidget);
    expect(tester.widget<WorkoutScreen>(allWorkouts()).plan.id, 'push');
  });

  testWidgets(
    'notification respects an editor discard prompt above the workout',
    (tester) async {
      await openShell(tester);
      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(WorkoutScreen));
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlanEditorScreen.edit(plan)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Unsaved name');
      await notify(tester, 1);
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(allWorkouts(), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved name'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanEditorScreen), findsNothing);
      expect(allWorkouts(), findsOneWidget);
    },
  );

  testWidgets('a blocking modal is not bypassed by a notification', (
    tester,
  ) async {
    await openShell(tester);
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(WorkoutScreen));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Saving'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Complete'),
                ),
              ],
            ),
          ),
    );
    await tester.pumpAndSettle();
    await notify(tester, 1, stop: true);
    expect(find.text('Saving'), findsOneWidget);
    expect(allWorkouts(), findsOneWidget);
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(find.text('Log workout?'), findsOneWidget);
  });

  testWidgets('notification opens the exact session identity', (tester) async {
    final other = session.copyWith(id: 'other-draft', date: DateTime(2026, 2));
    await tester.runAsync(() => HiveService.putSessionRaw(other));
    await openShell(tester);
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    await notify(tester, 1);
    // Same plan/week is not the same session: keep the existing draft underneath.
    expect(allWorkouts(), findsNWidgets(2));
    expect(
      tester
          .widget<WorkoutScreen>(find.byType(WorkoutScreen))
          .initialSession
          ?.id,
      'draft',
    );
  });
}
