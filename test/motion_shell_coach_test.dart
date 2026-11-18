import 'package:flutter/material.dart' hide Split;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/app_shell.dart';
import 'package:gymapp/models/split.dart';
import 'package:gymapp/models/split_preference.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/coach_provider.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/split_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/screens/coach_screen.dart';
import 'package:gymapp/screens/home_screen.dart';
import 'package:gymapp/services/coach/coach_client.dart';
import 'package:gymapp/services/coach/coach_disclosure.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/theme/app_theme.dart';
import 'package:gymapp/theme/motion.dart';
import 'package:gymapp/widgets/app_bottom_nav.dart';

import 'support/coach_fixtures.dart';
import 'support/hive_test_harness.dart';
import 'support/pump_with_storage.dart';
import 'support/test_fonts.dart';

const String _userId = 'motion-coach-user';
final DateTime _seeded = DateTime(2026, 9, 1);

class _SilentCoach implements CoachClient {
  @override
  Future<CoachClientResult> send(CoachRequest request) async =>
      const CoachFailure(CoachFailureKind.unavailable);
}

void main() {
  final hiveHarness = HiveTestHarness();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
    await hiveHarness.open(includeSplits: true);
    await loadTestFonts();
  });

  setUp(() async {
    await HiveService.clearTrainingData();
    SharedPreferences.setMockInitialValues({});
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<Split>(HiveService.splitsBox).clear();
    await Hive.box<SplitPreference>(HiveService.splitPreferencesBox).clear();
    await HiveService.putSplitRaw(
      Split(
        id: kSplitId,
        name: 'Push Pull Legs',
        userId: _userId,
        createdAt: _seeded,
        updatedAt: _seeded,
        dirty: false,
      ),
    );
    await HiveService.putSplitPreferenceRaw(
      SplitPreference(
        userId: _userId,
        activeSplitId: kSplitId,
        updatedAt: _seeded,
        dirty: false,
      ),
    );
  });

  tearDownAll(() async {
    await hiveHarness.close();
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    const timerChannel = MethodChannel(
      'com.aalishms.opengym/workout_timer_notification',
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(timerChannel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(timerChannel, null));
    final splits = SplitProvider(userIdProvider: () => _userId);
    final coach = CoachProvider(
      splitProvider: splits,
      client: _SilentCoach(),
      userIdProvider: () => _userId,
      isConfigured: () => true,
      probeConnection: () async => true,
      now: () => DateTime(2026, 10, 10, 9),
      signOut: () async {},
    );
    final plans = WorkoutPlanProvider(splits);
    final sessions = WorkoutSessionProvider(splits);
    addTearDown(() {
      plans.dispose();
      sessions.dispose();
      coach.dispose();
      splits.dispose();
    });
    await tester.runAsync(() => CoachDisclosure.accept(_userId));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: splits),
          ChangeNotifierProvider.value(value: coach),
          ChangeNotifierProvider.value(value: plans),
          ChangeNotifierProvider.value(value: sessions),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF00A2FF), Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 800),
              disableAnimations: reduceMotion,
            ),
            child: const AppShell(),
          ),
        ),
      ),
    );
    await pumpWithStorage(tester);
  }

  /// Taps the Coach button and lets the disclosure check resolve, stopping on
  /// the first frame of the Coach's arrival.
  Future<void> openCoach(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('coach-button')));
    for (
      var i = 0;
      i < 20 && find.byType(CoachScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(CoachScreen), findsOneWidget);
  }

  Finder coachLayer() =>
      find
          .ancestor(
            of: find.byType(CoachScreen),
            matching: find.byType(Opacity),
          )
          .first;
  Finder homeIgnoring() => find.ancestor(
    of: find.byType(HomeScreen, skipOffstage: false),
    matching: find.byWidgetPredicate(
      (widget) => widget is IgnorePointer && widget.ignoring,
    ),
  );

  testWidgets('the Coach arrives over Home, which stays alive beneath', (
    tester,
  ) async {
    await pumpShell(tester);
    final homeState = tester.state(find.byType(HomeScreen));

    await openCoach(tester);
    // First frame: the Coach is in the tree and takes taps at once; Home is
    // still painted beneath it but takes none.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(homeIgnoring(), findsWidgets);
    expect(
      find.ancestor(
        of: find.byType(CoachScreen),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsNothing,
    );
    // The opaque Coach is fully there before it finishes moving.
    await tester.pump(AppMotion.standard ~/ 8);
    final arriving = tester.widget<Opacity>(coachLayer()).opacity;
    expect(arriving, inExclusiveRange(0, 1));
    expect(
      tester.getTopLeft(find.byType(CoachScreen)).dx,
      inExclusiveRange(0, AppMotion.shift),
    );

    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(coachLayer()).opacity, 1);
    expect(tester.getTopLeft(find.byType(CoachScreen)).dx, 0);
    // Covered: hidden, but the same State.
    expect(find.byType(HomeScreen), findsNothing);
    expect(
      tester.state(find.byType(HomeScreen, skipOffstage: false)),
      homeState,
    );
    // The navigation stays on screen throughout.
    expect(find.byType(AppBottomNav), findsOneWidget);
  });

  testWidgets('closing uncovers Home at once and the Coach takes no taps', (
    tester,
  ) async {
    await pumpShell(tester);
    final homeState = tester.state(find.byType(HomeScreen));
    await openCoach(tester);
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byKey(const ValueKey('coach-input')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('Back to plans'));
    await tester.pump();
    // Home is back, interactive, from the first frame; the leaving Coach is
    // still painted but holds no taps, focus or semantics.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(homeIgnoring(), findsNothing);
    expect(find.byType(CoachScreen), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(CoachScreen),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsWidgets,
    );
    expect(
      find.ancestor(
        of: find.byType(CoachScreen),
        matching: find.byWidgetPredicate(
          (widget) => widget is ExcludeSemantics && widget.excluding,
        ),
      ),
      findsWidgets,
    );
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('coach-input')),
    );
    expect(input.focusNode?.hasFocus ?? false, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.pump(AppMotion.standard ~/ 2);
    expect(
      tester.widget<Opacity>(coachLayer()).opacity,
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CoachScreen, skipOffstage: false), findsNothing);
    expect(tester.state(find.byType(HomeScreen)), homeState);

    // A tap during the leave lands on Home, not the Coach: reopen, close, and
    // tap the Coach button again at once.
    await openCoach(tester);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('coach-button')));
    await pumpWithStorage(tester);
    expect(find.byType(CoachScreen), findsOneWidget);
    expect(tester.widget<Opacity>(coachLayer()).opacity, 1);
  });

  testWidgets('a Coach left open behind another tab closes without moving', (
    tester,
  ) async {
    await pumpShell(tester);
    await openCoach(tester);
    await tester.pumpAndSettle();
    final nav = find.byType(AppBottomNav);
    await tester.tap(find.descendant(of: nav, matching: find.text('History')));
    await tester.pumpAndSettle();
    // Returning to Home finds the Coach as it was, with no second arrival.
    await tester.tap(find.descendant(of: nav, matching: find.text('Home')));
    await tester.pump();
    expect(tester.widget<Opacity>(coachLayer()).opacity, 1);
    expect(tester.getTopLeft(find.byType(CoachScreen)).dx, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('Back from another tab closes a hidden Coach without showing '
      'it leave', (tester) async {
    await pumpShell(tester);
    await openCoach(tester);
    await tester.pumpAndSettle();
    final nav = find.byType(AppBottomNav);
    await tester.tap(find.descendant(of: nav, matching: find.text('History')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(CoachScreen, skipOffstage: false), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('opens and closes at once under reduced motion', (tester) async {
    await pumpShell(tester, reduceMotion: true);
    await openCoach(tester);
    expect(tester.widget<Opacity>(coachLayer()).opacity, 1);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.tap(find.byTooltip('Back to plans'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CoachScreen, skipOffstage: false), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
