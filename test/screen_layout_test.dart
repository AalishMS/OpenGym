import 'dart:io';
import 'package:gymapp/models/statistics.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'package:gymapp/models/exercise.dart';
import 'package:gymapp/models/exercise_template.dart';
import 'package:gymapp/models/set.dart';
import 'package:gymapp/models/set_template.dart';
import 'package:gymapp/models/workout_plan.dart';
import 'package:gymapp/models/workout_session.dart';
import 'package:gymapp/providers/workout_plan_provider.dart';
import 'package:gymapp/providers/workout_session_provider.dart';
import 'package:gymapp/providers/settings_provider.dart';
import 'package:gymapp/providers/update_provider.dart';
import 'package:gymapp/screens/dashboard_screen.dart';
import 'package:gymapp/screens/history_screen.dart';
import 'package:gymapp/screens/stats_screen.dart';
import 'package:gymapp/screens/settings_screen.dart';
import 'package:gymapp/services/hive_service.dart';
import 'package:gymapp/services/update_service.dart';
import 'package:gymapp/theme/app_theme.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    hiveDirectory = await Directory.systemTemp.createTemp('opengym_layout_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(SetAdapter());
    Hive.registerAdapter(SetTemplateAdapter());
    Hive.registerAdapter(ExerciseAdapter());
    Hive.registerAdapter(ExerciseTemplateAdapter());
    Hive.registerAdapter(WorkoutPlanAdapter());
    Hive.registerAdapter(WorkoutSessionAdapter());
    await Hive.openBox<WorkoutPlan>(HiveService.plansBox);
    await Hive.openBox<WorkoutSession>(HiveService.sessionsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  Widget host(
    Widget screen, {
    Size size = const Size(390, 800),
    Brightness brightness = Brightness.dark,
    double textScale = 1,
    List<WorkoutPlan> plans = const [],
    List<WorkoutSession> sessions = const [],
    WorkoutSessionProvider? sessionProvider,
    SettingsProvider? settingsProvider,
    UpdateProvider? updateProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WorkoutPlanProvider>(
          create: (_) => _Plans(plans),
        ),
        ChangeNotifierProvider<WorkoutSessionProvider>(
          create: (_) => sessionProvider ?? _Sessions(sessions),
        ),
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider ?? SettingsProvider(),
        ),
        ChangeNotifierProvider<UpdateProvider>.value(
          value: updateProvider ?? _Updates(UpdateStatus.idle),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(const Color(0xFF00A2FF), brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: screen,
          ),
        ),
      ),
    );
  }

  Future<void> seedPopulatedData({String exerciseName = 'Bench Press'}) async {
    final now = DateTime(2026, 8, 28);
    final plan = WorkoutPlan(
      id: 'plan-1',
      name: 'Push Day',
      exercises: [ExerciseTemplate(name: exerciseName, sets: 3)],
    );
    final sessions = [
      WorkoutSession(
        id: 'session-1',
        planName: 'Push Day',
        date: now,
        exercises: [
          Exercise(
            name: exerciseName,
            sets: [Set(reps: 5, weight: 80), Set(reps: 5, weight: 82.5)],
          ),
        ],
      ),
      WorkoutSession(
        id: 'session-2',
        planName: 'Push Day',
        date: now.subtract(const Duration(days: 7)),
        exercises: [
          Exercise(name: exerciseName, sets: [Set(reps: 5, weight: 75)]),
        ],
      ),
    ];
    await Hive.box<WorkoutPlan>(HiveService.plansBox).clear();
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).clear();
    await Hive.box<WorkoutPlan>(HiveService.plansBox).add(plan);
    await Hive.box<WorkoutSession>(HiveService.sessionsBox).addAll(sessions);
  }

  List<WorkoutPlan> storedPlans() =>
      Hive.box<WorkoutPlan>(HiveService.plansBox).values.toList();
  List<WorkoutSession> storedSessions() =>
      Hive.box<WorkoutSession>(HiveService.sessionsBox).values.toList();

  void expectNoOverflow(WidgetTester tester, String reason) {
    expect(tester.takeException(), isNull, reason: reason);
  }

  testWidgets('review screens use sans headings and do not overflow', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.3, 2.0]) {
        await tester.pumpWidget(
          host(
            HistoryScreen(key: ValueKey('history-$brightness-$scale')),
            brightness: brightness,
            textScale: scale,
          ),
        );
        await tester.pump();
        expect(find.text('WORKOUT HISTORY'), findsOneWidget);
        expect(find.text('> WORKOUT HISTORY'), findsNothing);
        expectNoOverflow(tester, 'history $brightness ${scale}x');

        await tester.pumpWidget(
          host(
            StatsScreen(key: ValueKey('stats-$brightness-$scale')),
            size: const Size(1200, 800),
            brightness: brightness,
            textScale: scale,
          ),
        );
        await tester.pump();
        expect(find.text('Statistics'), findsOneWidget);
        expect(find.text('STATISTICS'), findsNothing);
        expect(find.text('[OVERALL]'), findsNothing);
        expect(find.text('[EXERCISE]'), findsNothing);
        expectNoOverflow(tester, 'stats $brightness ${scale}x');

        await tester.pumpWidget(
          host(
            DashboardScreen(key: ValueKey('dashboard-$brightness-$scale')),
            size: const Size(1200, 800),
            brightness: brightness,
            textScale: scale,
          ),
        );
        await tester.pump();
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('> DASHBOARD'), findsNothing);
        expectNoOverflow(tester, 'dashboard $brightness ${scale}x');
      }
    }
  });

  testWidgets(
    'compact and populated review screens stay readable across themes and scales',
    (tester) async {
      await tester.runAsync(seedPopulatedData);
      final plans = storedPlans();
      final sessions = storedSessions();

      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final size in [const Size(390, 800), const Size(1200, 800)]) {
            await tester.pumpWidget(
              host(
                StatsScreen(key: ValueKey('stats-$brightness-$scale-$size')),
                size: size,
                brightness: brightness,
                textScale: scale,
                plans: plans,
                sessions: sessions,
              ),
            );
            await tester.pump();
            expect(find.text('Weekly training'), findsOneWidget);
            expectNoOverflow(tester, 'stats $brightness ${scale}x $size');

            await tester.pumpWidget(
              host(
                DashboardScreen(
                  key: ValueKey('dashboard-$brightness-$scale-$size'),
                ),
                size: size,
                brightness: brightness,
                textScale: scale,
                plans: plans,
                sessions: sessions,
              ),
            );
            await tester.pump();
            expect(find.text('LAST SESSION'), findsOneWidget);
            expect(find.text('ACTIVITY'), findsOneWidget);
            expect(find.text('PROGRESSION'), findsOneWidget);
            expectNoOverflow(tester, 'dashboard $brightness ${scale}x $size');
          }
        }
      }
    },
  );

  testWidgets('ordinary review headers use the neutral text role', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          HistoryScreen(key: ValueKey('history-$brightness')),
          brightness: brightness,
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('WORKOUT HISTORY')).style?.color,
        textPrimaryColor(tester.element(find.text('WORKOUT HISTORY'))),
      );

      await tester.pumpWidget(
        host(
          StatsScreen(key: ValueKey('stats-$brightness')),
          brightness: brightness,
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('Statistics')).style?.color,
        textPrimaryColor(tester.element(find.text('Statistics'))),
      );

      await tester.pumpWidget(
        host(
          DashboardScreen(key: ValueKey('dashboard-$brightness')),
          brightness: brightness,
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('Dashboard')).style?.color,
        textPrimaryColor(tester.element(find.text('Dashboard'))),
      );
    }
  });

  testWidgets('populated history keeps summary and moves actions to overflow', (
    tester,
  ) async {
    final session = WorkoutSession(
      id: 'session-1',
      planName: 'Push Day',
      date: DateTime(2026, 8, 28),
      exercises: [
        Exercise(name: 'Bench Press', sets: [Set(reps: 5, weight: 80)]),
      ],
    );
    await tester.pumpWidget(host(const HistoryScreen(), sessions: [session]));
    await tester.pump();
    expect(find.text('PUSH DAY'), findsOneWidget);
    expect(find.textContaining('1 EXERCISES'), findsOneWidget);
    expect(find.byTooltip('Session actions'), findsOneWidget);
    expect(find.text('[EDIT]'), findsNothing);
    expect(find.text('[DEL]'), findsNothing);
    expectNoOverflow(tester, 'populated history');
  });

  testWidgets('history overflow actions use bracket-control typography', (
    tester,
  ) async {
    final session = WorkoutSession(
      id: 'session-1',
      planName: 'Push Day',
      date: DateTime(2026, 8, 28),
      exercises: [
        Exercise(name: 'Bench Press', sets: [Set(reps: 5, weight: 80)]),
      ],
    );
    await tester.pumpWidget(host(const HistoryScreen(), sessions: [session]));
    await tester.pump();

    await tester.tap(find.byTooltip('Session actions'));
    await tester.pumpAndSettle();

    final editStyle = tester.widget<Text>(find.text('[EDIT]')).style!;
    final deleteStyle = tester.widget<Text>(find.text('[DELETE]')).style!;
    expect(
      editStyle.fontFamily,
      GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold).fontFamily,
    );
    expect(editStyle.fontSize, 9);
    expect(editStyle.fontWeight, FontWeight.bold);
    expect(editStyle.letterSpacing, 0.06);
    expect(editStyle.color, accentColor(tester.element(find.text('[EDIT]'))));
    expect(
      deleteStyle.fontFamily,
      GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold).fontFamily,
    );
    expect(deleteStyle.fontSize, 9);
    expect(deleteStyle.fontWeight, FontWeight.bold);
    expect(deleteStyle.letterSpacing, 0.06);
    expect(
      deleteStyle.color,
      errorColor(tester.element(find.text('[DELETE]'))),
    );
  });

  testWidgets('selected exercise stays readable with long names', (
    tester,
  ) async {
    const name = 'Single Arm Dumbbell Bulgarian Split Squat';
    await tester.runAsync(() => seedPopulatedData(exerciseName: name));
    await tester.pumpWidget(
      host(
        const StatsScreen(),
        textScale: 2,
        plans: storedPlans(),
        sessions: storedSessions(),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Exercise progress'));
    await tester.pumpAndSettle();
    expect(find.text(name), findsWidgets);
    expectNoOverflow(tester, 'long progression heading');
  });

  testWidgets(
    'statistics controls expose selected semantics and 48px targets',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final session = WorkoutSession(
        id: 'session-controls',
        planName: 'Push Day',
        date: DateTime.now(),
        exercises: [
          Exercise(name: 'Bench Press', sets: [Set(reps: 5, weight: 80)]),
        ],
      );
      await tester.pumpWidget(host(const StatsScreen(), sessions: [session]));
      await tester.pump();

      final control = find.byType(DropdownButtonFormField<StatisticsPeriod>);
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
      expect(
        tester
            .widget<DropdownButtonFormField<StatisticsPeriod>>(control)
            .initialValue,
        StatisticsPeriod.fourWeeks,
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 weeks').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<StatisticsPeriod>>(control)
            .initialValue,
        StatisticsPeriod.twelveWeeks,
      );
      expect(find.text('Recent sessions'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('statistics refreshes when sessions provider changes', (
    tester,
  ) async {
    final session = WorkoutSession(
      id: 'session-1',
      planName: 'Push Day',
      date: DateTime.now(),
      exercises: [
        Exercise(name: 'Bench Press', sets: [Set(reps: 5, weight: 80)]),
      ],
    );
    final sessions = _Sessions([session]);

    await tester.pumpWidget(
      host(const StatsScreen(), sessionProvider: sessions),
    );
    await tester.pump();
    expect(find.text('400 kg'), findsWidgets);

    sessions.values.add(session.copyWith(id: 'session-2'));
    sessions.notifyListeners();
    await tester.pump();

    expect(find.text('800 kg'), findsWidgets);
  });

  testWidgets(
    'settings uses clear sections and accessible full-size controls',
    (tester) async {
      await tester.pumpWidget(
        host(const SettingsScreen(), size: const Size(390, 4000)),
      );
      await tester.pump();

      for (final name in [
        'Appearance',
        'Workout',
        'Data',
        'Danger zone',
        'Updates',
        'About',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
      for (var index = 0; index < SettingsProvider.accents.length; index++) {
        final size = tester.getSize(
          find.byKey(ValueKey('accent-swatch-$index')),
        );
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.text('Clear all data'), findsOneWidget);
      expect(find.text('CHECK FOR UPDATES'), findsNothing);
    },
  );

  testWidgets('settings sections render in the documented order', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const SettingsScreen(), size: const Size(390, 4000)),
    );
    await tester.pump();
    final names = [
      'Appearance',
      'Workout',
      'Data',
      'Danger zone',
      'Updates',
      'About',
    ];
    final tops = [
      for (final name in names) tester.getTopLeft(find.text(name)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]));
    }
  });

  testWidgets('workout switches use the page background', (tester) async {
    await tester.pumpWidget(
      host(const SettingsScreen(), size: const Size(390, 4000)),
    );
    await tester.pump();

    for (final title in ['High refresh rate', 'Auto-fill last weights']) {
      final tile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(tile.tileColor, backgroundColor(tester.element(find.text(title))));
    }
  });

  testWidgets('settings does not expose a Units section', (tester) async {
    await tester.pumpWidget(
      host(const SettingsScreen(), size: const Size(390, 4000)),
    );
    await tester.pump();
    expect(find.text('Units'), findsNothing);
    expect(find.text('Weight unit'), findsNothing);
    expect(find.text('KILOGRAMS (KG)'), findsNothing);
    expect(find.text('POUNDS (LBS)'), findsNothing);
  });

  testWidgets('settings rows expose 48px hit regions', (tester) async {
    await tester.pumpWidget(
      host(const SettingsScreen(), size: const Size(390, 4000)),
    );
    await tester.pump();
    for (final title in [
      'Load sample data',
      'Export data',
      'Import data',
      'Clear all data',
      'Check for updates',
    ]) {
      final target = find.ancestor(
        of: find.text(title),
        matching: find.byType(InkWell),
      );
      expect(target, findsOneWidget);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('settings confirmation actions do not overflow when narrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const SettingsScreen(), size: const Size(220, 500), textScale: 2),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Clear all data'));
    await tester.tap(find.text('Clear all data'));
    await tester.pump();
    expect(find.text('[CLEAR ALL]'), findsOneWidget);
    expectNoOverflow(tester, 'clear confirmation at narrow width');
  });

  testWidgets('update states remain visible in the settings subtitle', (
    tester,
  ) async {
    for (final status in UpdateStatus.values.skip(1)) {
      final updates = _Updates(status, errorValue: 'Network unavailable');
      await tester.pumpWidget(
        host(
          const SettingsScreen(),
          size: const Size(390, 4000),
          updateProvider: updates,
        ),
      );
      await tester.pump();
      expect(find.byType(SettingsScreen), findsOneWidget);
      final expected =
          !UpdateService.isSupportedPlatform
              ? 'Only available on Android'
              : status == UpdateStatus.failed
              ? 'Network unavailable'
              : status == UpdateStatus.available
              ? 'ready'
              : status == UpdateStatus.upToDate
              ? 'up to date'
              : status == UpdateStatus.checking
              ? 'Checking'
              : status == UpdateStatus.downloading
              ? 'Downloading'
              : 'Opening';
      expect(find.textContaining(expected), findsOneWidget);
    }
  });

  testWidgets('destructive settings row uses the error color role', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const SettingsScreen(), size: const Size(390, 4000)),
    );
    await tester.pump();
    final title = find.text('Clear all data');
    final context = tester.element(title);
    expect(tester.widget<Text>(title).style?.color, errorColor(context));
  });

  testWidgets('settings callbacks run through confirmation controls', (
    tester,
  ) async {
    var clearCalls = 0;
    var sampleCalls = 0;
    var signOutCalls = 0;
    final settings = SettingsProvider();
    await tester.pumpWidget(
      host(
        SettingsScreen(
          onClearData: () async => clearCalls++,
          onLoadSampleData: () async => sampleCalls++,
          onSignOut: () async => signOutCalls++,
        ),
        size: const Size(390, 4000),
        settingsProvider: settings,
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Load sample data'));
    await tester.tap(find.text('Load sample data'));
    await tester.pump();
    await tester.tap(find.text('[LOAD]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all data'));
    await tester.pump();
    await tester.tap(find.text('[CLEAR ALL]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(sampleCalls, 1);
    expect(clearCalls, 1);
    expect(signOutCalls, 1);
  });

  testWidgets('settings callback failures are shown to the user', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SettingsScreen(
          onClearData: () async => throw StateError('clear failed'),
          onLoadSampleData: () async => throw StateError('sample failed'),
          onSignOut: () async => throw StateError('sign out failed'),
        ),
        size: const Size(390, 4000),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Load sample data'));
    await tester.tap(find.text('Load sample data'));
    await tester.pump();
    await tester.tap(find.text('[LOAD]'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sample failed'), findsOneWidget);
  });

  testWidgets('settings stays readable in both themes at large text', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          SettingsScreen(key: ValueKey(brightness)),
          brightness: brightness,
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(find.text('Danger zone'), findsOneWidget);
      expectNoOverflow(tester, 'settings $brightness');
    }
  });
}

class _Plans extends WorkoutPlanProvider {
  _Plans(this.values);

  final List<WorkoutPlan> values;

  @override
  List<WorkoutPlan> get plans => values;
}

class _Sessions extends WorkoutSessionProvider {
  _Sessions(this.values);

  final List<WorkoutSession> values;

  @override
  List<WorkoutSession> get sessions => values;
}

class _Updates extends UpdateProvider {
  _Updates(this.state, {this.errorValue});

  final UpdateStatus state;
  final String? errorValue;

  @override
  UpdateStatus get status => state;

  @override
  String? get error => errorValue;

  @override
  Future<void> loadInstalledVersion() async {}
}
